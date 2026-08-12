// A Chrome DevTools Protocol client in one file, with no dependencies.
//
// Why not Puppeteer/Playwright: this repo's whole dependency budget is `pg` and
// `@sentry/node` on the server and Next + next-intl on the web (decision-16, decision-23).
// A screen recorder is not a reason to add a browser automation framework and a second
// Chromium download to a public repo. Node 22+ ships a global WebSocket, Chrome ships the
// protocol, and everything below is four methods.
//
// It captures ONLY the page: headless Chrome has no window chrome, no tab strip, no
// desktop, no notifications and no other application. That is the point. The previous
// recording in this repo was made with a desktop screen recorder and leaked a chat list
// and a banking app into a public README.
import { spawn } from "node:child_process";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";

const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Chrome, headless, in a throwaway profile. No profile of a real person is ever opened. */
export async function launchChrome({ port = 9333, width = 1280, height = 800 } = {}) {
  const profile = `/tmp/ts-demo/chrome-profile-${port}`;
  rmSync(profile, { recursive: true, force: true });
  mkdirSync(profile, { recursive: true });

  const child = spawn(
    CHROME,
    [
      "--headless=new",
      `--remote-debugging-port=${port}`,
      `--user-data-dir=${profile}`,
      `--window-size=${width},${height}`,
      "--no-first-run",
      "--no-default-browser-check",
      "--disable-extensions",
      "--hide-scrollbars",
      "--force-color-profile=srgb",
      "--font-render-hinting=none",
      "about:blank",
    ],
    { stdio: "ignore" },
  );

  // Chrome writes the port to the profile, but polling /json/version is simpler and is
  // the only thing that actually proves the endpoint is answering.
  for (let i = 0; i < 100; i++) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}/json/version`);
      if (res.ok) return { child, port };
    } catch {
      /* not up yet */
    }
    await sleep(100);
  }
  child.kill();
  throw new Error("chrome did not open a debugging port");
}

/** One page target, with the handful of protocol calls this demo needs. */
export async function attach(port) {
  const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  const page = targets.find((t) => t.type === "page");
  if (!page) throw new Error("no page target");

  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((res, rej) => {
    ws.addEventListener("open", res, { once: true });
    ws.addEventListener("error", rej, { once: true });
  });

  let nextId = 1;
  const pending = new Map();
  const listeners = new Map();

  ws.addEventListener("message", (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) {
      const { resolve, reject } = pending.get(msg.id);
      pending.delete(msg.id);
      msg.error ? reject(new Error(`${msg.error.message}`)) : resolve(msg.result);
      return;
    }
    for (const fn of listeners.get(msg.method) ?? []) fn(msg.params);
  });

  const send = (method, params = {}) =>
    new Promise((resolve, reject) => {
      const id = nextId++;
      pending.set(id, { resolve, reject });
      ws.send(JSON.stringify({ id, method, params }));
    });

  const on = (method, fn) => {
    if (!listeners.has(method)) listeners.set(method, []);
    listeners.get(method).push(fn);
  };

  await send("Page.enable");
  await send("Runtime.enable");
  await send("Network.enable");

  return {
    send,
    on,
    close: () => ws.close(),

    /**
     * Force an exact CSS viewport, and prove it took.
     *
     * `--window-size` IS NOT A VIEWPORT. Chrome clamps a window to a platform minimum, so
     * `--window-size=390,844` opened at 500x757 and every „phone“ frame in the first cut of
     * the UX walkthrough was a 500 px layout wearing a caption that said 390. The layout was
     * still the phone one (500 < the 767 px breakpoint), which is exactly why nobody would
     * have caught it by looking. So the width is overridden here and then READ BACK.
     */
    async setViewport(width, height, { deviceScaleFactor = 1, mobile = false } = {}) {
      await send("Emulation.setDeviceMetricsOverride", {
        width,
        height,
        deviceScaleFactor,
        mobile,
      });
      const got = await this.eval("[innerWidth, innerHeight]");
      if (got[0] !== width || got[1] !== height) {
        throw new Error(`asked for a ${width}x${height} viewport and got ${got[0]}x${got[1]}`);
      }
    },

    /** Navigate and wait for the load event AND for React to have painted something. */
    async goto(url, { settle = 900 } = {}) {
      const loaded = new Promise((res) => on("Page.loadEventFired", res));
      await send("Page.navigate", { url });
      await loaded;
      await sleep(settle);
    },

    /** Run JS in the page. Throws with the page's own message so a broken selector is loud. */
    async eval(expression) {
      const r = await send("Runtime.evaluate", {
        expression,
        awaitPromise: true,
        returnByValue: true,
      });
      if (r.exceptionDetails) {
        throw new Error(r.exceptionDetails.exception?.description ?? "page threw");
      }
      return r.result.value;
    },

    /**
     * Wait until `expression` is truthy. Polling, not a mutation observer: this drives a
     * static export whose every screen is one fetch and one render.
     */
    async waitFor(expression, { timeout = 15000, label = expression } = {}) {
      const deadline = Date.now() + timeout;
      while (Date.now() < deadline) {
        if (await this.eval(`!!(${expression})`)) return;
        await sleep(120);
      }
      throw new Error(`timed out waiting for: ${label}`);
    },

    async screenshot(path) {
      const { data } = await send("Page.captureScreenshot", { format: "png" });
      writeFileSync(path, Buffer.from(data, "base64"));
    },

    /**
     * Type into a field one character at a time, through real key events.
     *
     * Setting `.value` would be one line, but it produces a video in which text appears
     * fully formed, which reads as a mock-up rather than as software. It also skips the
     * events a controlled React input listens to.
     */
    async type(selector, text, { perChar = 45 } = {}) {
      await this.eval(`document.querySelector(${JSON.stringify(selector)}).focus()`);
      for (const ch of text) {
        await send("Input.insertText", { text: ch });
        await sleep(perChar);
      }
    },

    /** Click the one element whose accessible name / text contains `text`. */
    async clickText(text, { selector = "button, a" } = {}) {
      const ok = await this.eval(`(() => {
        const wanted = ${JSON.stringify(text)}
        const hit = Array.from(document.querySelectorAll(${JSON.stringify(selector)}))
          .find((el) => ((el.getAttribute('aria-label') || el.textContent || '')).includes(wanted))
        if (!hit) return false
        hit.click()
        return true
      })()`);
      if (!ok) throw new Error(`no clickable element containing: ${text}`);
    },

    /** Pick a <select> option by value and fire the change React is listening for. */
    async select(selector, value) {
      const ok = await this.eval(`(() => {
        const el = document.querySelector(${JSON.stringify(selector)})
        if (!el) return false
        const set = Object.getOwnPropertyDescriptor(el.constructor.prototype, 'value').set
        set.call(el, ${JSON.stringify(value)})
        el.dispatchEvent(new Event('change', { bubbles: true }))
        return true
      })()`);
      if (!ok) throw new Error(`no select matching: ${selector}`);
    },

    /** Scroll an element into view the way a person scrolls: visibly, and then a pause. */
    async scrollTo(selector, { pause = 900, block = "start" } = {}) {
      await this.eval(`(() => {
        const el = document.querySelector(${JSON.stringify(selector)})
        if (el) el.scrollIntoView({ behavior: 'smooth', block: ${JSON.stringify(block)} })
        return !!el
      })()`);
      await sleep(pause);
    },
  };
}

/**
 * Start capturing frames from `page` into `dir`. Returns a handle whose `stop()` writes
 * them out for the concat demuxer.
 *
 * Screencast frames arrive only when something changes, so a still page emits nothing.
 * Each frame is written with the wall-clock ms it arrived and the concat demuxer is given
 * real durations — otherwise a 20-second walkthrough plays back as a 2-second flicker.
 *
 * `stop({ t0, t1 })` is what makes TWO simultaneous captures composable. A screencast's
 * first frame does not arrive at the instant it was asked for, and the two pages do not
 * agree on when that is; without a shared origin the phone pane in the composite runs a
 * fraction of a second ahead of the desktop one and a caption describes the wrong pane.
 * Given `t0` the first frame is held from the shared origin, and given `t1` the last frame
 * is held to the shared end, so both files cover exactly the same wall-clock window. Both
 * are HELD FRAMES — a still picture, never a speed change.
 */
export function startRecording(page, dir) {
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });

  const frames = [];
  page.on("Page.screencastFrame", async (p) => {
    frames.push({ at: Date.now(), data: p.data });
    try {
      await page.send("Page.screencastFrameAck", { sessionId: p.sessionId });
    } catch {
      /* cast already stopped */
    }
  });

  const ready = page.send("Page.startScreencast", {
    format: "jpeg",
    quality: 92,
    everyNthFrame: 1,
  });
  const started = Date.now();

  return {
    started,
    ready,
    async stop({ t0 = null, t1 = null, fps = null } = {}) {
      await page.send("Page.stopScreencast");
      if (frames.length === 0) throw new Error(`no frames captured into ${dir}`);

      const name = (i) => `f${String(i).padStart(5, "0")}.jpg`;
      frames.forEach((f, i) => writeFileSync(`${dir}/${name(i)}`, Buffer.from(f.data, "base64")));

      const lines = [];
      if (fps === null) {
        // Variable cadence: one entry per captured frame, lasting until the next arrives.
        const lead = t0 === null ? 0 : (frames[0].at - t0) / 1000;
        if (lead > 0.02) lines.push(`file '${name(0)}'`, `duration ${lead.toFixed(3)}`);
        frames.forEach((f, i) => {
          const last = i === frames.length - 1;
          const next = last ? (t1 ?? f.at + 500) : frames[i + 1].at;
          lines.push(`file '${name(i)}'`, `duration ${Math.max(0.02, (next - f.at) / 1000).toFixed(3)}`);
        });
      } else {
        // FIXED cadence, and the reason it exists: the concat demuxer will not honour a
        // duration below its own default frame time (0.04 s), so a burst of frames 5 ms
        // apart is silently STRETCHED. On a 290 s capture that added 18 s, it added a
        // different amount to each of the two panes, and it moved every caption off the
        // screen it describes. Sampling the capture onto the output's own grid removes the
        // clamp entirely: each entry is 1/fps, which is above the floor, so the file is
        // exactly (t1 - t0) long and two captures of the same window are frame-aligned.
        if (t0 === null || t1 === null) throw new Error("fixed cadence needs both t0 and t1");
        const step = 1000 / fps;
        const ticks = Math.round((t1 - t0) / step);
        let j = 0;
        for (let i = 0; i < ticks; i++) {
          const at = t0 + i * step;
          while (j + 1 < frames.length && frames[j + 1].at <= at) j++;
          // Before the first frame arrived there is nothing to show but the first frame,
          // held. That is a still picture and is stated in backlog/docs/DEMO.md.
          lines.push(`file '${name(j)}'`, `duration ${(step / 1000).toFixed(3)}`);
        }
        lines.push(`file '${name(j)}'`);
      }
      // The concat demuxer ignores the last duration unless the last file is repeated.
      if (fps === null) lines.push(`file '${name(frames.length - 1)}'`);
      writeFileSync(`${dir}/frames.txt`, `${lines.join("\n")}\n`);
      // The arrival times, kept next to the frames, so a timeline can be re-laid-out later
      // without spending another take on the device.
      writeFileSync(
        `${dir}/frames.json`,
        JSON.stringify({ t0, t1, fps, at: frames.map((f) => f.at) }),
      );

      return {
        dir,
        frames: frames.length,
        seconds: (Date.now() - started) / 1000,
        firstFrameAt: frames[0].at,
        lastFrameAt: frames[frames.length - 1].at,
      };
    },
  };
}

/** Record one page for the duration of `drive`. The single-page case of `startRecording`. */
export async function record(page, dir, drive) {
  const rec = startRecording(page, dir);
  await rec.ready;
  await drive();
  await sleep(400);
  return rec.stop();
}
