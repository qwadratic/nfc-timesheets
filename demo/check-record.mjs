// Proves demo/cdp.mjs still lays a timeline out correctly, in both cadences.
//
//   node demo/check-record.mjs        # needs the demo stack on 127.0.0.1:8082
//
// WHY THIS EXISTS. `record()` was split into `startRecording()` + `stop()` so the UX
// walkthrough could capture two pages at once. Three shipping recorders still call
// `record()`, and the way that refactor breaks is not a crash — it is a three-minute film
// that plays back as a two-second flicker, or two panes that drift a second apart by the
// end. Both are only visible after a full re-record, which is the most expensive place in
// this repo to find a bug.
//
// So both cadences are exercised against a real page here, in about six seconds.
import { readFileSync, rmSync } from "node:fs";
import { attach, launchChrome, record, sleep, startRecording } from "./cdp.mjs";

const BASE = process.env.DEMO_BASE ?? "http://127.0.0.1:8082";
const host = new URL(BASE).hostname;
if (!["127.0.0.1", "localhost", "[::1]", "::1"].includes(host)) {
  console.error(`check-record: refusing to record against "${host}" — loopback only.`);
  process.exit(1);
}

let fails = 0;
const ok = (m) => console.log(`  ok   ${m}`);
const check = (cond, m) => {
  if (cond) ok(m);
  else {
    console.error(`  FAIL ${m}`);
    fails += 1;
  }
};

const lines = (dir) => readFileSync(`${dir}/frames.txt`, "utf8").trim().split("\n");
const entries = (dir) => lines(dir).filter((l) => l.startsWith("file "));
const durations = (dir) => lines(dir).filter((l) => l.startsWith("duration ")).map((l) => Number(l.split(" ")[1]));

/** Something that repaints, so the screencast actually emits frames. A still page emits none. */
async function tick(page, times, ms) {
  for (let i = 0; i < times; i++) {
    await page.eval(`document.body.style.background = '${i % 2 ? "#fff" : "#eee"}'`);
    await sleep(ms);
  }
}

const { child } = await launchChrome({ port: 9359, width: 800, height: 600 });
const page = await attach(9359);
await page.goto(`${BASE}/login/`, { settle: 600 });

// ---------------------------------------------------------------------------
// 1. Variable cadence: the contract record-admin / record-ios / record-android rely on.
// ---------------------------------------------------------------------------
const VAR = "/tmp/ts-demo/frames-check-var";
const varied = await record(page, VAR, () => tick(page, 6, 250));

check(varied.frames > 0, `variable cadence captured ${varied.frames} frames`);
check(
  entries(VAR).length === varied.frames + 1,
  `one entry per frame plus the repeated last (${entries(VAR).length} = ${varied.frames} + 1)`,
);
check(durations(VAR).length === varied.frames, `one duration per frame (${durations(VAR).length})`);
check(
  entries(VAR).at(-1) === entries(VAR).at(-2),
  "the last file is repeated — the concat demuxer drops the final duration otherwise",
);
check(durations(VAR).every((d) => d >= 0.02), "no duration below the floor");
check(
  varied.seconds > 1.4 && varied.seconds < 4,
  `seconds is wall clock, not frame count (${varied.seconds.toFixed(2)}s for a ~1.5 s drive)`,
);

// ---------------------------------------------------------------------------
// 2. Fixed cadence: the contract the two-pane composite rests on. The file must be exactly
//    (t1 - t0) long — not "about", because a caption track is laid out over that number.
// ---------------------------------------------------------------------------
const FIX = "/tmp/ts-demo/frames-check-fix";
const FPS = 10;
const rec = startRecording(page, FIX);
await rec.ready;
const t0 = Date.now();
await tick(page, 8, 200);
await sleep(500);
const t1 = Date.now();
const fixed = await rec.stop({ t0, t1, fps: FPS });

const wanted = Math.round((t1 - t0) / (1000 / FPS));
const total = durations(FIX).reduce((a, b) => a + b, 0);
check(durations(FIX).length === wanted, `one entry per output frame (${durations(FIX).length} = ${wanted})`);
check(
  durations(FIX).every((d) => d === 1 / FPS),
  `every duration is exactly 1/${FPS}s, so nothing is clamped up to the demuxer's 0.04s floor`,
);
check(
  Math.abs(total - (t1 - t0) / 1000) < 0.11,
  `the timeline is the wall-clock window (${total.toFixed(2)}s vs ${((t1 - t0) / 1000).toFixed(2)}s)`,
);
// The first frame of a screencast does not arrive at the instant it was asked for. Whatever
// the gap, the output has to start at t0 — that is what keeps two captures in step.
check(
  fixed.firstFrameAt >= t0 - 50,
  "the first frame is at or after the shared origin, so the lead is a held frame and not a cut",
);

// ---------------------------------------------------------------------------
// 3. The viewport override, which is what makes a „390 px" label true.
// ---------------------------------------------------------------------------
await page.setViewport(390, 844);
const seen = await page.eval("[innerWidth, innerHeight]");
check(seen[0] === 390 && seen[1] === 844, `setViewport imposes an exact viewport (${seen.join("x")})`);

let refused = false;
try {
  // A width Chrome cannot possibly give as a WINDOW is fine as an override; this asserts the
  // read-back exists at all by asking for something and checking it came back.
  await page.setViewport(321, 654);
  refused = (await page.eval("innerWidth")) !== 321;
} catch {
  refused = true;
}
check(!refused, "an odd viewport is honoured too, so the read-back is measuring and not guessing");

page.close();
child.kill();
rmSync(VAR, { recursive: true, force: true });
rmSync(FIX, { recursive: true, force: true });

console.log();
if (fails === 0) console.log("check-record: OK");
else {
  console.log(`check-record: ${fails} FAIL`);
  process.exit(1);
}
