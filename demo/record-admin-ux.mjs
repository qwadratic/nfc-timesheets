// The admin panel after the UX pass: recorded twice, at once, and put side by side.
//
//   node demo/record-admin-ux.mjs                  # record + compose
//   node demo/record-admin-ux.mjs --compose-only   # re-encode from the last run's frames
//   DEMO_BASE=http://127.0.0.1:8082 node demo/record-admin-ux.mjs
//
// Prerequisites are in backlog/docs/DEMO.md and unchanged: a seeded `nfc_demo` database and
// the API serving `web/out` on DEMO_BASE. Like every recorder here it refuses to run against
// anything that is not a loopback address.
//
// WHY A SECOND ADMIN FILM AT ALL. `record-admin.mjs` is a tour of the SCREENS and it stays.
// This one is a tour of what the UX pass CHANGED, which is mostly not a screen:
//
//   · the question line under every h1, and the five load/empty/error states (task-107/109)
//   · cross-links that carry their filter, and the banner the destination shows about it
//   · a well-formed but unknown filter showing EVERY row rather than an empty table
//   · the create forms folded away below the list they used to interrupt (task-108)
//   · the same panel at 390 px, where every table is a labelled card (decision-29)
//
// The last one is why the phone pane exists and why it is on for the WHOLE film rather than
// for one chapter: „works on a phone" is a claim about every screen, so every screen is shown
// on the phone at the same moment it is shown on the desktop. Both panes are real captures of
// real Chrome against the same demo server, driven in one script, with ONE shared clock —
// see `startRecording(...).stop({ t0, t1 })` in demo/cdp.mjs for how they are aligned.
//
// THE ONLY EDITS, STATED: each pane's first and last frame are HELD so both cover the same
// wall-clock window, and the frames are scaled. Nothing is sped up, cut, reordered or drawn.
//
// The NFC tap in the middle is MOCKED and says so in yellow across the top for as long as it
// lasts. It is not a fake: it is `POST /auth/code` and `POST /shifts/open`, byte for byte the
// two requests the app sends after a real tag read, with no radio in the room.
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { captionFilter, fitFontSize } from "./burnin.mjs";
import { attach, launchChrome, sleep, startRecording } from "./cdp.mjs";
import { writePng } from "./png.mjs";

const BASE = process.env.DEMO_BASE ?? "http://127.0.0.1:8082";
const OUT = new URL("../docs/media/", import.meta.url).pathname;
const WORK = "/tmp/ts-demo";
const DESK_DIR = `${WORK}/frames-ux-desktop`;
const PHONE_DIR = `${WORK}/frames-ux-phone`;
const PLAN = `${WORK}/admin-ux-plan.json`;
const COMPOSE_ONLY = process.argv.includes("--compose-only");
// `--draft` renders to /tmp so a layout or caption question can be answered off the frames
// that are already on disk. It NEVER writes docs/media/, and it downgrades the pacing gate to
// a warning — which is exactly why it is not allowed anywhere near the shipped file.
const DRAFT = process.argv.includes("--draft");

// Same refusal as record-admin.mjs, for the same reason: this must never be pointed at the
// live server, and a hostname check is the only form of that sentence a machine reads.
const host = new URL(BASE).hostname;
if (!["127.0.0.1", "localhost", "[::1]", "::1"].includes(host)) {
  console.error(`record-admin-ux: refusing to record against "${host}" — loopback only.`);
  process.exit(1);
}

const ADMIN = { email: "demo@example.test", password: "demo-nur-lokal-2026" };

/**
 * The coarse app-key gate in front of `/auth/code` and `/shifts/open`.
 *
 * READ from `android/branding.properties`, never copied into this file. It is not a secret —
 * it is compiled into every APK and `strings` recovers it from any install, which is why
 * `.gitleaks.toml` allowlists the `tsk_` prefix by pattern rather than by value. But it IS
 * operator configuration with one committed source (decision-24), and a second copy here
 * would be a second thing to rotate. It also keeps this file clean for `psst scan`, which
 * matches vault VALUES and cannot tell a duplicated public constant from a pasted secret.
 */
const APP_KEY = (() => {
  const path = new URL("../android/branding.properties", import.meta.url).pathname;
  const found = /^ts\.appKey=(.+)$/m.exec(readFileSync(path, "utf8"))?.[1]?.trim();
  if (!found) throw new Error(`no ts.appKey in ${path}`);
  return found;
})();

// Desktop capture, and the pane it is scaled into. 1180/1680 = 0.70, a shade larger than the
// 0.686 `admin-walkthrough.mp4` ships at, which was judged legible by reading the P&L table
// back out of the encoded file.
const DESK = { w: 1680, h: 1000, pane: 1180 };
// A phone, at the width the tables-become-cards media query is written for (max-width: 767).
// 300/390 = 0.77, so the phone pane is the least compressed thing in the frame.
const PHONE = { w: 390, h: 844, pane: 300 };
const PANE_H = 720;
const FPS = 10;

const FONT = "/System/Library/Fonts/Supplemental/Arial.ttf";
const ff = (args) => execFileSync("ffmpeg", ["-y", "-loglevel", "error", ...args], { stdio: "inherit" });

// ---------------------------------------------------------------------------
// Captions and pacing.
//
// The previous cut of an admin demo went fast enough that the owner concluded a screen was
// MISSING. So every caption's on-screen time is measured here and the run fails rather than
// shipping another one — see checkPacing(). Nothing about the recording is sped up; the
// pacing is bought with real dwell time, which is why this film is four minutes long.
// ---------------------------------------------------------------------------
const MIN_CAPTION_SECONDS = 5;
/** Characters per second a viewer is assumed to read. Deliberately slow: this is German,
 *  the reader is also looking at two panes of a table, and it is not their first language
 *  in every case. 12 cps is roughly half of comfortable silent reading. */
const READING_CPS = 12;

const captions = [];
let t0 = 0;
/**
 * How long a caption stays up, in SECONDS, because seconds is the unit the pacing gate
 * thinks in, and a bare four-digit millisecond literal was never read as "eight seconds" by
 * anybody at a glance.
 *
 * It also keeps four-digit millisecond literals out of this file. `psst scan` matches vault
 * VALUES, one of which is a port number that happened to equal one of those durations, so the
 * scan reported a leaked secret on seven lines. That is a false positive — and a gate that is
 * routinely bypassed is a gate that is off, so it is cheaper to write the unit the reader
 * wanted anyway than to teach everybody which warnings to ignore.
 */
const dwell = (seconds) => sleep(Math.round(seconds * 1000));
const say = (text) => {
  const at = (Date.now() - t0) / 1000;
  captions.push({ at, text });
  console.log(`  ${at.toFixed(1)}s  ${text}`);
};

/**
 * Every caption must stay up long enough to be read. Fails the build; does not warn.
 *
 * Mutation check, run before this was trusted: dropping MIN_CAPTION_SECONDS to 5 and the
 * dwell on the „Aus einem Link gefiltert" beat to 2 s made it report that beat and exit 1.
 */
function checkPacing(plan) {
  const bad = [];
  plan.captions.forEach((c, i) => {
    const until = plan.captions[i + 1]?.at ?? plan.total;
    const shown = until - c.at;
    const needed = Math.max(MIN_CAPTION_SECONDS, c.text.length / READING_CPS);
    if (shown + 1e-6 < needed) bad.push({ shown, needed, text: c.text });
  });
  if (bad.length > 0) {
    for (const b of bad) {
      console.error(`  TOO FAST  ${b.shown.toFixed(1)}s < ${b.needed.toFixed(1)}s  ${b.text}`);
    }
    const message = `${bad.length} caption(s) are on screen for less time than they take to read`;
    if (!DRAFT) throw new Error(message);
    console.error(`  (draft: ${message})`);
    return;
  }
  console.log(`pacing ok: ${plan.captions.length} captions, none under its reading time`);
}

// ---------------------------------------------------------------------------
// Pre-flight, over HTTP, BEFORE a browser is launched.
//
// Both of these cost one second here and four minutes at the end of a take. Both were paid
// for the expensive way once already — the client-link one killed a full run at the last
// beat, because a portal link is minted by a POST and the SECOND run finds the button
// replaced by „Neuer Link“.
// ---------------------------------------------------------------------------
async function adminState() {
  const login = await fetch(`${BASE}/admin/login`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(ADMIN),
  });
  if (!login.ok) throw new Error(`admin login failed: ${login.status}`);
  const cookie = login.headers.getSetCookie()[0].split(";")[0];
  const data = await (await fetch(`${BASE}/admin/data`, { headers: { cookie } })).json();
  return { cookie, data };
}

const RESEED = "re-seed: psql -q -d nfc_demo -f demo/seed.sql";

function preflight({ data }) {
  const worker = data.workers.find((w) => w.name === "Selim Kaya");
  const tapLocation = data.locations.find((l) => l.slug === "handelskai-94");
  const shared = data.locations.find((l) => l.slug === "donaufeld-101");
  if (!worker || !tapLocation || !shared) {
    throw new Error("demo seed is missing Selim Kaya / handelskai-94 / donaufeld-101");
  }
  // decision-19: the server is authoritative for open shifts, so a leftover open shift turns
  // the mocked tap into a clock-OUT and the dashboard beat narrates a row that never appeared.
  const stale = data.shifts.find((s) => s.worker_id === worker.id && s.end_time === null);
  if (stale) {
    throw new Error(`${worker.name} already has shift ${stale.id} open — ${RESEED}`);
  }
  // A building that is already shared offers „Neuer Link“, not „Mit … teilen“, and the
  // closing beat mints the link ON CAMERA.
  const grant = (data.portal_grants ?? []).find((g) => g.location_id === shared.id);
  if (grant) {
    throw new Error(`${shared.name} is already shared — ${RESEED}`);
  }
  return { worker, tapLocation };
}

// ---------------------------------------------------------------------------
// Recording
// ---------------------------------------------------------------------------
if (!COMPOSE_ONLY) {
  mkdirSync(OUT, { recursive: true });
  const admin = await adminState();
  const { worker: tapWorker, tapLocation } = preflight(admin);
  console.log(`pre-flight ok: ${tapWorker.name} is free, ${tapLocation.name} is tappable`);

  const desktop = await launchChrome({ port: 9333, width: DESK.w, height: DESK.h });
  const phoneChrome = await launchChrome({ port: 9334, width: PHONE.w, height: PHONE.h });
  const desk = await attach(9333);
  const phone = await attach(9334);
  // The pane labels in the finished film state these two numbers, so they are IMPOSED and
  // then read back rather than requested. `--window-size` alone gave the phone 500x757.
  await desk.setViewport(DESK.w, DESK.h);
  await phone.setViewport(PHONE.w, PHONE.h);
  console.log(`viewports pinned: ${DESK.w}x${DESK.h} and ${PHONE.w}x${PHONE.h}`);

  /** Do the same thing on both panes at once, so the two captures stay describable by one caption. */
  const both = (fn) => Promise.all([fn(desk, "desk"), fn(phone, "phone")]);

  /** Every screen the sidebar offers, ticked off as the desktop pane visits it. */
  const visited = new Set();

  async function open(label, path) {
    await both(async (page) => {
      await page.clickText(label, { selector: "nav a" });
      await page.waitFor(`location.pathname === ${JSON.stringify(path)}`, { label });
    });
    visited.add(path);
    await sleep(700);
  }

  /** Go to a URL on both panes. Used for the deep links, which are the point of half of this. */
  async function goBoth(url, settle = 1500) {
    await both((page) => page.goto(url.startsWith("http") ? url : `${BASE}${url}`, { settle }));
  }

  /** Scroll each pane independently: the same content sits at very different offsets. */
  const scroll = (deskY, phoneY) =>
    both((page, which) =>
      page.eval(`window.scrollTo({ top: ${which === "desk" ? deskY : phoneY}, behavior: 'smooth' })`),
    );

  /**
   * The element to scroll to, as an expression, so both halves of reveal() agree on it.
   *
   * `selector` is not decoration. Without it the last match in document order wins, and on
   * /workers/ that was a status span reading „Inaktiv – kein Zugangscode möglich“ rather than
   * the column header, while on /payroll/ it was the screen-reader-only <caption>, whose box
   * is one pixel tall — a target that is "visible" to a rectangle test and to nobody else.
   * Hence also the height filter: an element under 8 px is furniture for assistive tech.
   *
   * ⚠ A rectangle is not proof of visibility. Below 768 px a `thead` is hidden by CLIPPING it
   * to 1 px (globals.css keeps it in the accessibility tree on purpose), and its `th` children
   * keep reporting a 36 px box while painting nothing. So the anchors below are section
   * headings, not column headings — an h2 is visible in both layouts and sits immediately
   * above the table it names.
   */
  const target = (text, selector) => `(() => {
    const wanted = ${JSON.stringify(text)}
    const all = Array.from(document.querySelectorAll(${JSON.stringify(selector)}))
      .filter((el) => (el.textContent || '').includes(wanted))
      .filter((el) => el.getBoundingClientRect().height >= 8)
    return all[all.length - 1] ?? null
  })()`;

  /**
   * Scroll BOTH panes to whatever carries `text`, then prove it is on screen.
   *
   * A fixed pixel offset is a guess about a layout, and one of them was wrong: the beat
   * about the folded-away form scrolled to y=2600 and landed in the middle of the shift
   * table, while an `includes()` assertion about the same text passed happily because the
   * form was in the DOM the whole time. So this MEASURES the rectangle after the scroll has
   * settled and fails if the thing the caption is about is not actually visible. The desktop
   * and the phone need different offsets for the same content, which is the other half of
   * why an offset could never have worked here.
   */
  async function reveal(text, { selector = "h2", block = "start", pause = 1600 } = {}) {
    await both(async (page, which) => {
      const ok = await page.eval(`(() => {
        const hit = ${target(text, selector)}
        if (!hit) return false
        hit.scrollIntoView({ behavior: 'smooth', block: ${JSON.stringify(block)} })
        return true
      })()`);
      if (!ok) throw new Error(`${which} pane has no visible ${selector} containing "${text}"`);
    });
    await sleep(pause);
    await both(async (page, which) => {
      const seen = await page.eval(`(() => {
        const r = ${target(text, selector)}.getBoundingClientRect()
        // How much of it is actually inside the viewport, against how much of it there is.
        // An element taller than the viewport can never be wholly inside one, so the test is
        // "enough of it to read", not "all of it".
        return [Math.min(r.bottom, innerHeight) - Math.max(r.top, 0), r.height]
      })()`);
      const [visible, height] = seen;
      const enough = Math.min(height, 24);
      if (!(visible >= enough)) {
        throw new Error(
          `"${text}" shows ${visible.toFixed(0)}px of ${height.toFixed(0)}px in the ${which} pane`,
        );
      }
    });
  }

  /**
   * Assert some text is on screen in BOTH panes before narrating it.
   *
   * A caption over a screen that does not say what the caption claims is the failure this
   * whole file is written against, and it is not hypothetical: the first cut of
   * `record-admin.mjs` scrolled to elements that were not in the DOM and narrated them anyway.
   */
  async function onScreen(text, where = "both") {
    const check = async (page, which) => {
      if (where !== "both" && where !== which) return;
      const ok = await page.eval(
        `document.body.textContent.includes(${JSON.stringify(text)})`,
      );
      if (!ok) throw new Error(`${which} pane does not say "${text}"`);
    };
    await both(check);
  }

  // -------------------------------------------------------------------------
  // Sign in on both panes, the way the director does (decision-20).
  // -------------------------------------------------------------------------
  await goBoth("/login/", 900);

  const rec = {
    desk: startRecording(desk, DESK_DIR),
    phone: startRecording(phone, PHONE_DIR),
  };
  await Promise.all([rec.desk.ready, rec.phone.ready]);
  t0 = Date.now();

  say("Ein Panel, zwei Breiten: links 1680 px, rechts 390 px. Dasselbe Bundle, dieselbe Datenbank.");
  await dwell(9.5);

  say("Anmeldung mit E-Mail und Passwort — die Admin-PIN gibt es nicht mehr (decision-20).");
  await both(async (page) => {
    await page.type('input[name="email"]', ADMIN.email);
    await page.type('input[name="password"]', ADMIN.password);
    await page.clickText("Anmelden", { selector: 'form button[type="submit"]' });
    await page.waitFor("location.pathname === '/'", { label: "the dashboard after sign-in" });
  });
  visited.add("/");
  await dwell(5.5);

  // -------------------------------------------------------------------------
  // Übersicht: the question line, the triage list, and the phone card layout.
  // -------------------------------------------------------------------------
  await onScreen("Muss ich gerade etwas tun?");
  say("Neu: unter jeder Überschrift steht die Frage, die genau dieser Bildschirm beantwortet.");
  await dwell(7);

  await reveal("Zu erledigen");
  say("„Zu erledigen“ nennt jeden offenen Punkt beim Namen — und verlinkt ihn.");
  await dwell(7);

  await reveal("Zuletzt erfasste Schichten");
  say("Rechts wird aus jeder Tabellenzeile eine Karte. Jeder Wert behält seine Spaltenüberschrift.");
  await dwell(8);

  // -------------------------------------------------------------------------
  // The mocked tap: phone -> API -> panel. Labelled in yellow for its whole length.
  // -------------------------------------------------------------------------
  const tapFrom = (Date.now() - t0) / 1000;
  say("Jetzt ein NFC-TAP — SIMULIERT. Kein Funk, kein Gerät: dieselben zwei HTTP-Aufrufe wie die App.");
  const tapped = await mockTap(admin.cookie, tapWorker, tapLocation);
  await dwell(8.5);

  await scroll(0, 0);
  await both((page) => page.clickText("Aktualisieren"));
  await dwell(2);
  await onScreen(tapped.worker);
  await onScreen(tapped.location);
  say(`Der Server hat die Schicht angelegt. ${tapped.worker} steht jetzt in „Gerade im Einsatz“.`);
  await dwell(8.5);
  const tapUntil = (Date.now() - t0) / 1000;

  // -------------------------------------------------------------------------
  // The cross-link, and what the destination says about the filter it arrived with.
  // -------------------------------------------------------------------------
  await reveal("Zu erledigen");
  await both(async (page) => {
    await page.clickText("Schichten prüfen");
    await page.waitFor("location.pathname === '/shifts/' && location.search.includes('state=unresolved')", {
      label: "the shift log, filtered by the link",
    });
  });
  visited.add("/shifts/");
  await sleep(1500);
  await onScreen("Aus einem Link gefiltert");
  say("Der Link nimmt seinen Filter mit — und das Ziel sagt oben, mit welchem es gefiltert wurde.");
  await dwell(8.5);

  say("„Filter entfernen“ macht das rückgängig. Ein Filter versteckt hier nie etwas stillschweigend.");
  await dwell(7.5);
  await both(async (page) => {
    await page.clickText("Filter entfernen");
    await page.waitFor("!document.body.textContent.includes('Aus einem Link gefiltert')", {
      label: "the filter chip to go away",
    });
  });
  await dwell(2.5);

  // The one that used to look like data loss.
  await goBoth("/shifts/?worker=999&period=last30Days", 2200);
  await onScreen("es fehlt nichts");
  say("Ein Link mit unbekanntem Mitarbeiter: es kommen ALLE Zeilen, plus ein Satz „es fehlt nichts“.");
  await dwell(9);

  await goBoth("/shifts/?period=vorgestern&from=irgendwann", 2200);
  await onScreen("ungültigen Wert");
  say("Kaputte Werte im Link führen nicht ins Leere: Standardansicht, und es steht da, warum.");
  await dwell(8.5);

  // -------------------------------------------------------------------------
  // Schichten: progressive disclosure.
  // -------------------------------------------------------------------------
  await goBoth("/shifts/", 2000);
  await onScreen("Wie diese Seite funktioniert");
  await both((page) => page.clickText("Wie diese Seite funktioniert", { selector: "summary" }));
  await sleep(1800);
  say("Die Erklärung steht nicht mehr dauerhaft über der Liste, sondern hinter „Wie diese Seite funktioniert“.");
  await dwell(9);

  await both((page) => page.clickText("Wie diese Seite funktioniert", { selector: "summary" }));
  await reveal("Schicht von Hand erfassen", { selector: "summary", block: "center" });
  say("Dasselbe für das Formular: eingeklappt, und UNTER der Liste, die es vorher unterbrochen hat.");
  await dwell(8.5);
  await both((page) => page.clickText("Schicht von Hand erfassen", { selector: "summary" }));
  await dwell(4.5);
  await both((page) => page.clickText("Schicht von Hand erfassen", { selector: "summary" }));

  // -------------------------------------------------------------------------
  // Materialanforderungen.
  // -------------------------------------------------------------------------
  await open("Materialanforderungen", "/material-requests/");
  await onScreen("Wartet gerade jemand in einem Haus auf eine Entscheidung von mir?");
  await reveal("Die Liste");
  say("Materialanforderungen: die Warteschlange, in der jemand in einem Haus auf eine Antwort wartet.");
  await dwell(8);
  await both((page) => page.clickText("Genehmigen – Anforderung von Elif Demir"));
  await dwell(2.5);
  say("Ein echter Klick, ein echtes POST: eingereicht → genehmigt. Nichts hier ist nachgestellt.");
  await dwell(7.5);

  // -------------------------------------------------------------------------
  // Mitarbeiter, Objekte, Kunden, Produkte — each with its question and its cross-link.
  // -------------------------------------------------------------------------
  await open("Mitarbeiter", "/workers/");
  await onScreen("Wer darf für mich stempeln – und zu welchem Stundensatz?");
  await reveal("Alle Mitarbeiter");
  say("Mitarbeiter: Stundensätze, Zugangscodes — und je Zeile „Schichten dieser Person“.");
  await dwell(8);

  await both(async (page) => {
    await page.clickText("Schichten dieser Person");
    await page.waitFor("location.search.includes('worker=')", { label: "shifts filtered by worker" });
  });
  await sleep(1800);
  await onScreen("Aus einem Link gefiltert");
  say("Ein Klick später: dasselbe Schichtprotokoll, auf diese eine Person gefiltert und beschriftet.");
  await dwell(8.5);

  await open("Objekte", "/locations/");
  await onScreen("Was ist für dieses Objekt vereinbart – und funktioniert sein Tag?");
  await reveal("Alle Objekte");
  say("Objekte: Adresse, Kunde, Vertrag und die URL, die auf dem NFC-Tag steht.");
  await dwell(7.5);

  await open("Kunden", "/clients/");
  await onScreen("Wem gehören meine Objekte, und wen rufe ich dort an?");
  await reveal("Alle Ansprechpersonen", { selector: "h2, h3" });
  say("Kunden und Ansprechpersonen. Am Telefon: wieder Karten, nie eine seitwärts scrollende Seite.");
  await dwell(8);

  await open("Produkte & Geräte", "/inventory/");
  await onScreen("Was kostet das, was meine Leute anfordern?");
  await reveal("Alle Einträge");
  say("Produkte & Geräte: der Katalog mit einem Stückpreis je Zeile.");
  await dwell(7);

  await open("Vertragsverwaltung", "/contracts/");
  await onScreen("Was war für dieses Objekt wann vereinbart?");
  await sleep(1200);
  await both((page) => page.clickText("Verlauf und Änderung von Buerozentrum Handelskai"));
  await sleep(1400);
  await reveal("Vertragsverlauf", { selector: "h2, h3" });
  say("Vertragsverwaltung: eine Preisänderung beendet die alte Zeile, sie überschreibt sie nie.");
  await dwell(8);

  // -------------------------------------------------------------------------
  // The money screens, and the link that carries an absolute period.
  // -------------------------------------------------------------------------
  await open("Lohnabrechnung", "/payroll/");
  await onScreen("Was zahle ich wem für diesen Zeitraum?");
  await reveal("Stunden und Verdienst");
  say("Lohnabrechnung: Stunden und Geld je Person, für genau einen Abrechnungszeitraum.");
  await dwell(8);

  await both(async (page) => {
    await page.clickText("Diese Stunden nachrechnen");
    await page.waitFor("location.search.includes('from=') && location.search.includes('to=')", {
      label: "shifts filtered by an absolute pay period",
    });
  });
  await sleep(1800);
  await onScreen("Zeitraum:");
  say("„Diese Stunden nachrechnen“ nimmt den Zeitraum ALS DATUM mit, nicht als „letzter Monat“.");
  await dwell(9);
  say("Deshalb zeigt derselbe Link morgen dieselbe Zahl. Genau das ist bei Geld der Punkt.");
  await dwell(8);

  await open("Gewinn & Verlust", "/pl/");
  await onScreen("Verdiene ich an diesem Objekt Geld?");
  await reveal("Ergebnis pro Objekt");
  say("Gewinn & Verlust je Objekt: Erlös, Lohn, Material, Marge — und je Zeile „Arbeit nachrechnen“.");
  await dwell(8.5);

  await open("Objektauswertung", "/analytics/");
  await onScreen("Brauchen wir für dieses Objekt mehr Zeit als vereinbart?");
  await reveal("keinen Google-Maps-Schlüssel", { selector: "p" });
  say("Objektauswertung: geleistete gegen vereinbarte Stunden. Ohne Maps-Schlüssel — und sagt das.");
  await dwell(8.5);

  // -------------------------------------------------------------------------
  // The client portal: the one page a non-employee ever sees.
  // -------------------------------------------------------------------------
  await open("Objekte", "/locations/");
  // Minted on the DESKTOP PANE ONLY. Minting twice is not two links, it is one link and one
  // revocation — „Neuer Link“ kills its predecessor immediately — so two panes racing each
  // other would have left the closing beat opening a URL the server had already withdrawn.
  await desk.clickText("Mit Petra Aigner teilen");
  await desk.waitFor("document.body.textContent.includes('Link für Petra Aigner')", {
    label: "the fresh client link",
  });
  // The phone pane is NOT minting; it stays on the same building's card so the two panes are
  // still looking at the same row while the desktop one shows the link.
  await phone.eval(`(() => {
    const hit = Array.from(document.querySelectorAll('th, td, strong'))
      .find((el) => (el.textContent || '').includes('Wohnhausanlage Donaufeld'))
    if (hit) hit.scrollIntoView({ behavior: 'smooth', block: 'start' })
    return !!hit
  })()`);
  await sleep(1800);
  const portalUrl = await desk.eval("document.querySelector('.share-panel code').textContent");
  say("Zuletzt der Kundenzugang: ein Nur-Lese-Link, hier frisch erzeugt.");
  await dwell(7);

  await goBoth(portalUrl, 2800);
  await onScreen("Reinigungsnachweis");
  await sleep(1200);
  say("Datum, Vorname, Dauer. Mehr verlässt das Unternehmen nicht — auch nicht am Telefon.");
  await dwell(9);

  // -------------------------------------------------------------------------
  // Stop both captures on ONE shared window, so the panes cannot drift apart.
  // -------------------------------------------------------------------------
  await sleep(600);
  const t1 = Date.now();
  // FPS here, not only in the filter chain: it puts both captures on the OUTPUT's own frame
  // grid, which is the only way two independent screencasts of the same window come out the
  // same length. See the `fixed cadence` note in demo/cdp.mjs for what happens without it.
  const deskOut = await rec.desk.stop({ t0, t1, fps: FPS });
  const phoneOut = await rec.phone.stop({ t0, t1, fps: FPS });
  const total = (t1 - t0) / 1000;
  console.log(
    `desktop ${deskOut.frames} frames, phone ${phoneOut.frames} frames, ${total.toFixed(1)}s`,
  );

  // The completeness assertion, same rule as record-admin.mjs: the sidebar is the list, and
  // a screen added there and not here fails the run rather than shipping a partial tour.
  const navSource = readFileSync(new URL("../web/lib/nav.ts", import.meta.url), "utf8");
  const primary = /PRIMARY_NAV: readonly NavItem\[\] = \[([\s\S]*?)\]/.exec(navSource)?.[1] ?? "";
  const navPaths = [...primary.matchAll(/href: '([^']+)'/g)].map((m) => m[1]);
  if (navPaths.length === 0) throw new Error("could not read PRIMARY_NAV out of web/lib/nav.ts");
  const missed = navPaths.filter((p) => !visited.has(p));
  if (missed.length > 0) {
    console.error(`record-admin-ux: never opened ${missed.join(", ")} — incomplete.`);
    process.exit(1);
  }
  console.log(`covered all ${navPaths.length} sidebar screens plus the client portal`);

  // Phone stills. decision-29 is a claim about pictures, so it gets pictures.
  const phoneStills = [
    { path: "/", name: "admin-phone-dashboard", scroll: 900 },
    { path: "/shifts/", name: "admin-phone-shifts", scroll: 1400 },
    { path: "/payroll/", name: "admin-phone-payroll", scroll: 900 },
    { path: "/workers/", name: "admin-phone-workers", scroll: 700 },
  ];
  for (const still of phoneStills) {
    await phone.goto(`${BASE}${still.path}`, { settle: 2200 });
    await phone.eval(`window.scrollTo(0, ${still.scroll})`);
    await sleep(700);
    const raw = `${WORK}/${still.name}-raw.png`;
    await phone.screenshot(raw);
    // Written at capture width. Downscaling a wider capture to 390 would be a picture of a
    // different layout with the right number of pixels, which is the trap this file already
    // fell into once.
    writePng(raw, `${OUT}${still.name}.png`, { width: PHONE.w });
    console.log("still", still.name);
  }

  // One desktop still of the thing this film is mostly about.
  await desk.goto(`${BASE}/shifts/?worker=999&period=last30Days`, { settle: 2400 });
  await desk.eval("window.scrollTo(0, 0)");
  await sleep(700);
  await desk.screenshot(`${WORK}/admin-linkfilter-raw.png`);
  writePng(`${WORK}/admin-linkfilter-raw.png`, `${OUT}admin-linkfilter.png`, { width: 1280 });
  console.log("still admin-linkfilter");

  desk.close();
  phone.close();
  desktop.child.kill();
  phoneChrome.child.kill();

  writeFileSync(
    PLAN,
    JSON.stringify({ captions, total, tap: { from: tapFrom, until: tapUntil }, ...tapped }, null, 2),
  );
}

/**
 * The mocked tap.
 *
 * Two requests, both the real endpoints with the real app key: an enrolment code is redeemed
 * for a worker session (decision-26), and that session opens a shift at the location whose
 * UUID a tag carries (decision-21). Nothing about the panel is stubbed and nothing about the
 * server is swapped — the ONLY thing missing is the radio, and the film says so on screen for
 * as long as this lasts.
 */
async function mockTap(cookie, worker, location) {
  const enrol = await (
    await fetch(`${BASE}/admin/workers/${worker.id}/enrolment-code`, { method: "POST", headers: { cookie } })
  ).json();

  const auth = await fetch(`${BASE}/auth/code`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-app-key": APP_KEY },
    body: JSON.stringify({ code: enrol.code }),
  });
  if (!auth.ok) throw new Error(`worker sign-in failed: ${auth.status}`);
  const workerCookie = auth.headers.getSetCookie()[0].split(";")[0];

  const opened = await fetch(`${BASE}/shifts/open`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-app-key": APP_KEY, cookie: workerCookie },
    body: JSON.stringify({
      location_uuid: location.id,
      start_time: new Date().toISOString(),
      client_uuid: crypto.randomUUID(),
    }),
  });
  if (opened.status !== 201) throw new Error(`clock-in failed: ${opened.status}`);
  console.log(`  mocked tap: ${worker.name} -> ${location.name}`);
  return { worker: worker.name, location: location.name };
}

// ---------------------------------------------------------------------------
// Compose: two panes, one caption band.
// ---------------------------------------------------------------------------
const plan = JSON.parse(readFileSync(PLAN, "utf8"));
checkPacing(plan);

const pane = (dir, out, width) => {
  ff([
    "-f", "concat", "-safe", "0", "-i", `${dir}/frames.txt`,
    "-vf", [
      `scale=${width}:-2`,
      `pad=${width}:${PANE_H}:0:(oh-ih)/2:black`,
      `fps=${FPS}`,
      "setpts=PTS-STARTPTS",
    ].join(","),
    "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p", "-an",
    out,
  ]);
  return out;
};

const deskPane = pane(DESK_DIR, `${WORK}/ux-desk.mp4`, DESK.pane);
const phonePane = pane(PHONE_DIR, `${WORK}/ux-phone.mp4`, PHONE.pane);

/**
 * The two panes and the caption timeline must be the same length, or a caption describes a
 * screen the viewer is not looking at.
 *
 * This is not a hypothetical: the first composite came out 310.4 s against a 290.6 s caption
 * track, with 2.2 s of drift BETWEEN the panes as well, because the concat demuxer had
 * silently stretched every sub-40 ms frame. It was invisible at the start of the film and
 * nearly twenty seconds wrong at the end.
 */
const seconds = (file) =>
  Number(
    execFileSync("ffprobe", [
      "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", file,
    ], { encoding: "utf8" }).trim(),
  );
const measured = { desk: seconds(deskPane), phone: seconds(phonePane) };
console.log(
  `panes: desktop ${measured.desk.toFixed(2)}s, phone ${measured.phone.toFixed(2)}s, ` +
    `captions ${plan.total.toFixed(2)}s`,
);
if (Math.abs(measured.desk - measured.phone) > 0.2) {
  throw new Error(`the two panes are ${Math.abs(measured.desk - measured.phone).toFixed(2)}s apart`);
}
if (Math.abs(measured.desk - plan.total) > 0.5) {
  throw new Error(
    `the picture is ${measured.desk.toFixed(2)}s but the captions are laid out over ${plan.total.toFixed(2)}s`,
  );
}

const stacked = `${WORK}/ux-stacked.mp4`;
ff([
  "-i", deskPane, "-i", phonePane,
  "-filter_complex", "[0:v][1:v]hstack=inputs=2[v]",
  "-map", "[v]",
  "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p", "-an",
  stacked,
]);

const WIDTH = DESK.pane + PHONE.pane;
const TOP = 66;
const BOTTOM = 52;

const label = (text, centre) => {
  const size = fitFontSize(text, 16, PHONE.pane - 16);
  return (
    `drawtext=fontfile=${FONT}:expansion=none:text='${text}':fontcolor=#B0B0B0:fontsize=${size}:` +
    `x=${centre}-text_w/2:y=44`
  );
};

// The mocked tap, called what it is, in yellow, across the top, for its whole length. The
// caption band already says it; this is the second statement, because the one sentence that
// must never travel alone is „this tap did not happen".
const MOCK_LABEL = "NFC-TAP SIMULIERT \u2014 kein Funk, kein Ger\u00e4t";
const mockBanner =
  `drawtext=fontfile=${FONT}:expansion=none:text='${MOCK_LABEL}':fontcolor=yellow:` +
  `fontsize=${fitFontSize(MOCK_LABEL, 20, WIDTH - 16)}:x=(w-text_w)/2:y=${TOP + 6}:` +
  `box=1:boxcolor=black@0.85:boxborderw=6:` +
  `enable='gte(t,${plan.tap.from.toFixed(3)})*lt(t,${plan.tap.until.toFixed(3)})'`;

const mp4 = DRAFT ? `${WORK}/admin-ux-draft.mp4` : `${OUT}admin-ux-walkthrough.mp4`;
ff([
  "-i", stacked,
  "-vf", [
    ...captionFilter(plan.captions, plan.total, {
      width: WIDTH,
      fps: 10,
      fontSize: 21,
      top: TOP,
      bottom: BOTTOM,
      banner: "DEMO \u2014 lokale Datenbank, erfundene Daten, kein Live-Server",
    }),
    label("Admin-Panel \u2014 1680 px", DESK.pane / 2),
    label("Dasselbe Panel \u2014 390 px", DESK.pane + PHONE.pane / 2),
    mockBanner,
  ].join(","),
  "-c:v", "libx264", "-preset", "veryslow", "-crf", "32",
  "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-an",
  mp4,
]);
console.log(`wrote ${mp4} (${plan.total.toFixed(1)}s, ${plan.captions.length} captions)`);

// ---------------------------------------------------------------------------
// The contact sheet: one frame from the MIDDLE of every caption, tiled.
//
// Everything above this line is a machine checking a machine. This is the part a person has
// to do, and it is the only check that has ever caught a caption pointing at the wrong
// screen — an assertion that a string is in the DOM passes happily while the picture shows
// something else entirely, which is exactly how the „folded-away form“ beat first came out
// as a shot of the middle of the shift table. So the sheet is written every run, and the
// instruction to LOOK at it is printed rather than left in a document.
// ---------------------------------------------------------------------------
const sheetDir = `${WORK}/ux-sheet`;
rmSync(sheetDir, { recursive: true, force: true });
mkdirSync(sheetDir, { recursive: true });
plan.captions.forEach((c, i) => {
  const until = plan.captions[i + 1]?.at ?? plan.total;
  const mid = (c.at + until) / 2;
  ff([
    "-ss", mid.toFixed(3), "-i", mp4, "-frames:v", "1",
    `${sheetDir}/c${String(i).padStart(2, "0")}.png`,
  ]);
});
const rows = Math.ceil(plan.captions.length / 4);
const sheet = `${WORK}/admin-ux-contact-sheet.png`;
ff([
  "-pattern_type", "glob", "-i", `${sheetDir}/c*.png`,
  "-filter_complex", `scale=370:-1,tile=4x${rows}`,
  "-frames:v", "1", sheet,
]);
console.log(`\nNOW LOOK AT ${sheet}`);
console.log(
  `  ${plan.captions.length} frames, one from the middle of each caption. Read every caption` +
    " against the two panes beside it. No script can do this part.",
);
