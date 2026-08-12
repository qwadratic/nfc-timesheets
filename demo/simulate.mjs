// Grow a cleaning company for twelve months against nfc_demo, then measure what the
// director actually sees.
//
//   DATABASE_URL=postgres:///nfc_demo node demo/simulate.mjs
//   DATABASE_URL=postgres:///nfc_demo node demo/simulate.mjs --months 18 --seed 7
//   DATABASE_URL=postgres:///nfc_demo node demo/simulate.mjs --self-check
//   DATABASE_URL=postgres:///nfc_demo node demo/simulate.mjs --json /tmp/sim.json
//
// This is TWO things at once and neither works without the other:
//
//   1. A LOAD TEST. It writes thousands of shifts and then times the REAL route handlers —
//      not a re-implementation of their SQL. `adminData`, `plReport` and `analyticsReport`
//      are imported out of server/routes/admin.js and called directly, so a query that
//      regresses in the server regresses here too. A load test that runs its own copy of
//      the query measures the copy.
//
//   2. An OPERATIONAL AUDIT. Every unexpected event a cleaning company actually has —
//      a forgotten tap-out, a tap at the wrong building, a dead phone, a worker who never
//      enrols, a tag that stops working, a firing mid-month — is INJECTED with a label,
//      counted, and then compared against what the panel would derive from the payload it
//      is really given. The gap between the two is the finding.
//
// The second point is why the dashboard's arithmetic is REPRODUCED here (see
// `dashboardDerived`) instead of asserted about. web/app/page.tsx computes "how many
// shifts need confirming" and "which buildings have a dead tag" by filtering
// `snapshot.shifts` — a list the server caps at 2000 rows, newest first. Past 2000 total
// shifts those two numbers stop being answers about the company and become answers about
// the most recent 2000 rows, silently. Reproducing the filter and diffing it against SQL
// over the whole table is the only way to put a number on that.
//
// It TRUNCATEs, so it carries the same guards demo/seed.sql and demo/make-admin.mjs
// carry, for the same reason and in the same order. demo/check-guards.sh exercises them.
import { randomUUID } from "node:crypto";

import { all, one, pool, query } from "../server/lib/db.js";
import { adminRoutes } from "../server/routes/admin.js";
import { assertDemoDatabase } from "./db-guard.mjs";

// ---------------------------------------------------------------------------------
// GUARDS. Before anything else in this file runs.
//
// Order matters and is the same order demo/make-admin.mjs uses:
//   1. assertDemoDatabase reads every input that can become the driver's connection
//      target (URL host, ?host=, ?hostaddr=, $PGHOST, $PGHOSTADDR) and the database name.
//      It runs with NO network access, so a refusal is instant — which is what lets
//      check-guards.sh treat "still alive after 5 s" as a failure.
//   2. assertLocalServer asks the SERVER what it is, after connecting. The URL can lie
//      about the name (a socket can front any database); inet_server_addr() cannot.
// Neither is redundant: one reads the request, the other reads the answer.
// ---------------------------------------------------------------------------------
const DEMO_DATABASE = "nfc_demo";

const refuse = (why) => {
  console.error(`simulate: ${why}`);
  process.exit(1);
};

assertDemoDatabase(process.env.DATABASE_URL ?? "", refuse);

/**
 * The post-connect half of the guard, mirroring the DO block at the top of demo/seed.sql.
 *
 * `current_database()` and `inet_server_addr()` are answered BY THE SERVER, so no
 * connection-string trick reaches them. NULL from inet_server_addr() means a unix socket,
 * which is necessarily this machine.
 */
async function assertLocalServer() {
  // The loopback test is done BY POSTGRES with inet operators, character for character the
  // same expression as demo/seed.sql. Doing it in JS means parsing `inet_server_addr()::text`,
  // which is "::1/128" and not "::1" — a string comparison that looked right and refused the
  // loopback it was written to allow. Let the type system that owns the type answer.
  const row = await one(
    `SELECT current_database() AS name,
            inet_server_addr()::text AS addr,
            (inet_server_addr() IS NULL
             OR inet_server_addr() <<= inet '127.0.0.0/8'
             OR inet_server_addr() = inet '::1') AS is_local`,
  );
  if (row.name !== DEMO_DATABASE) {
    refuse(`refusing to touch "${row.name}" — expected "${DEMO_DATABASE}". It TRUNCATEs.`);
  }
  if (!row.is_local) {
    refuse(`refusing a REMOTE server ${row.addr} — loopback only. It TRUNCATEs.`);
  }
}

// ---------------------------------------------------------------------------------
// Arguments
// ---------------------------------------------------------------------------------
const argv = process.argv.slice(2);
const flag = (name) => argv.includes(name);
const opt = (name, fallback) => {
  const i = argv.indexOf(name);
  return i === -1 ? fallback : argv[i + 1];
};

const MONTHS = Number(opt("--months", "12"));
const SEED = Number(opt("--seed", "20260815"));
const JSON_OUT = opt("--json", null);

if (!Number.isInteger(MONTHS) || MONTHS < 1 || MONTHS > 60) refuse("--months must be 1..60");
if (!Number.isInteger(SEED)) refuse("--seed must be an integer");

// ---------------------------------------------------------------------------------
// Determinism. mulberry32 — 12 lines, no dependency (decision-16/23 budget), and the same
// seed gives the same company, which is the only way a number in the report can be checked.
// ---------------------------------------------------------------------------------
function mulberry32(a) {
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rnd = mulberry32(SEED);
const rint = (lo, hi) => lo + Math.floor(rnd() * (hi - lo + 1)); // inclusive
const pick = (xs) => xs[Math.floor(rnd() * xs.length)];
const chance = (p) => rnd() < p;

// ---------------------------------------------------------------------------------
// Vienna wall time -> UTC instant.
//
// Every date in this file is a Vienna CALENDAR fact ("the 3rd, 06:30") because that is
// what a cleaner's day is and what a payroll month is. Postgres stores instants. Getting
// this wrong moves shifts across month boundaries twice a year, which is exactly the class
// of bug the simulation is supposed to find rather than create.
//
// No dependency: Intl knows the zone, so the offset is MEASURED at the instant rather than
// assumed to be +01:00. Two passes because the first guess can land on the other side of a
// DST transition; the second settles it (the third would never differ — asserted in
// --self-check).
// ---------------------------------------------------------------------------------
const VIENNA = "Europe/Vienna";
const PARTS = new Intl.DateTimeFormat("en-US", {
  timeZone: VIENNA,
  hour12: false,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
});

function viennaOffsetMs(date) {
  const p = Object.fromEntries(PARTS.formatToParts(date).map((x) => [x.type, x.value]));
  const asIfUtc = Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour % 24, +p.minute, +p.second);
  return asIfUtc - date.getTime();
}

/** Vienna wall clock -> the UTC instant it names. Month is 1-based. */
function viennaToUtc(y, mo, d, hh = 0, mi = 0) {
  const naive = Date.UTC(y, mo - 1, d, hh, mi);
  let t = naive - viennaOffsetMs(new Date(naive));
  t = naive - viennaOffsetMs(new Date(t));
  return new Date(t);
}

/** The Vienna calendar month an instant falls in, as {y, mo}. */
function viennaMonthOf(date) {
  const p = Object.fromEntries(PARTS.formatToParts(date).map((x) => [x.type, x.value]));
  return { y: +p.year, mo: +p.month };
}

const monthKey = ({ y, mo }) => `${y}-${String(mo).padStart(2, "0")}`;
/** `YYYY-MM-01` — a contract starts on a CALENDAR DAY, so it never becomes an instant. */
const firstOfMonthDate = (mk) => `${monthKey(mk)}-01`;
/** `YYYY-MM-DD` for the last day of the month BEFORE `mk`. Day 0 of a month is that day. */
const dayBeforeMonthDate = (mk) => {
  const d = new Date(Date.UTC(mk.y, mk.mo - 1, 0));
  return d.toISOString().slice(0, 10);
};
const addMonths = ({ y, mo }, n) => {
  const z = (y * 12 + (mo - 1)) + n;
  return { y: Math.floor(z / 12), mo: (z % 12) + 1 };
};
const monthStart = ({ y, mo }) => viennaToUtc(y, mo, 1);
/** Vienna weekday, 0 = Sunday. */
const viennaDow = (date) => {
  const p = Object.fromEntries(PARTS.formatToParts(date).map((x) => [x.type, x.value]));
  return new Date(Date.UTC(+p.year, +p.month - 1, +p.day)).getUTCDay();
};

// ---------------------------------------------------------------------------------
// Invented company. Nothing below comes from the live system.
// ---------------------------------------------------------------------------------
const FIRST = "Ana Bojan Dragica Elif Fatima Goran Hana Ivan Jelena Kemal Lidia Marek Nadia Omar Petra Quim Radu Sanja Tomasz Urszula Vlad Wanda Xenia Yusuf Zora Bogdan Camelia Dorin Emine Florin".split(" ");
const LAST = "Petrovic Horvat Nagy Kovac Ionescu Popa Yilmaz Demir Nowak Kowalski Varga Toth Ilic Jovanovic Marku Dobre Stanek Novak Fischer Weber".split(" ");
const STREETS = [
  ["Donaufelder Strasse", 1210], ["Wagramer Strasse", 1220], ["Gumpendorfer Strasse", 1060],
  ["Ottakringer Strasse", 1160], ["Landstrasser Hauptstrasse", 1030], ["Simmeringer Hauptstrasse", 1110],
  ["Favoritenstrasse", 1100], ["Meidlinger Hauptstrasse", 1120], ["Thaliastrasse", 1160],
  ["Hernalser Hauptstrasse", 1170], ["Brünner Strasse", 1210], ["Quellenstrasse", 1100],
  ["Reindorfgasse", 1150], ["Praterstrasse", 1020], ["Hütteldorfer Strasse", 1140],
  ["Erdbergstrasse", 1030], ["Laxenburger Strasse", 1100], ["Wienerbergstrasse", 1120],
  ["Grinzinger Allee", 1190], ["Sechshauser Strasse", 1150],
];
const CLIENT_KIND = ["Hausverwaltung", "Immobilien", "Facility", "Wohnbau", "Objektbetreuung"];
const BUILDING_KIND = ["Wohnhausanlage", "Wohnhaus", "Bürohaus", "Ordination", "Stiegenhaus"];

const INVENTORY = [
  ["Allzweckreiniger 5 l", "product", 1290],
  ["Müllsäcke 120 l (Rolle)", "product", 640],
  ["Mikrofasertücher (10er)", "product", 890],
  ["Wischmopp-Bezug", "product", 1150],
  ["Handschuhe Nitril (100er)", "product", 1490],
  ["Reinigungswagen", "equipment", 24900],
  ["Nasssauger", "equipment", 38900],
];

// ---------------------------------------------------------------------------------
// The event catalogue. Every messy thing the simulation injects has an id here, and every
// id must appear in backlog/docs/SIMULATION-REPORT.md with the procedure the app offers.
// `detectable` is the honest half: whether the panel can KNOW it happened at all.
// ---------------------------------------------------------------------------------
const EVENTS = {
  forgot_tapout: "worker forgot to tap out; the 8h timer closed the shift",
  wrong_building: "worker tapped the tag of a building they were not cleaning",
  manual_entry: "phone was dead, the director typed the shift in by hand",
  never_enrolled: "worker was created and issued a code, and never enrolled",
  dead_tag: "a tag that worked stopped working; the building went silent",
  tag_never_written: "a building was taken on and its tag was never written",
  quit: "worker resigned",
  fired: "worker was dismissed mid-month",
  contract_lost: "client cancelled; the building was deactivated",
  contract_won: "new building started mid-month",
  rate_change: "worker's hourly rate changed",
  midnight_cross: "shift started before midnight and ended after it",
  month_cross: "shift started in one payroll month and ended in the next",
  left_open: "worker is still clocked in right now",
  unpriced_material: "material was ordered and nobody ever typed its cost",
};

// ---------------------------------------------------------------------------------
// The world
// ---------------------------------------------------------------------------------
const now = new Date();
const thisMonth = viennaMonthOf(now);
// MONTHS full months, then the current partial one. The first bucket therefore starts on
// the 1st, which is what makes a per-month table comparable row to row.
const firstMonth = addMonths(thisMonth, -MONTHS);
/** Which simulated month a {y, mo} is, counting from `firstMonth`. */
const monthIndexOf = (mk) => (mk.y * 12 + mk.mo) - (firstMonth.y * 12 + firstMonth.mo);

const world = {
  clients: [],       // {id?, name, activeFrom, activeTo}
  contacts: [],
  buildings: [],     // {id, slug, name, address, clientIdx, contactIdx, wonAt, lostAt, visitDays, minutes, twice, priceCents, targetMin, deadFrom}
  workers: [],       // {id?, name, email, phone, hiredAt, leftAt, leftReason, rates:[{from, cents}], enrolled}
  shifts: [],        // {workerIdx, buildingIdx, start, end, autoClosed, correctedAt, clientUuid, tags:[]}
  contracts: [],     // {buildingIdx, from, to, cents, targetMin, note}
  materials: [],
  events: Object.fromEntries(Object.keys(EVENTS).map((k) => [k, 0])),
};

const bump = (k, n = 1) => {
  world.events[k] += n;
};

/** The rate in force for a worker at an instant — the history the DATABASE does not keep. */
function rateAt(worker, at) {
  let cents = worker.rates[0].cents;
  for (const r of worker.rates) if (r.from.getTime() <= at.getTime()) cents = r.cents;
  return cents;
}

let slugSeq = 0;
function newBuilding(monthIdx) {
  const [street, plz] = STREETS[slugSeq % STREETS.length];
  const num = rint(2, 180);
  slugSeq += 1;
  const clientIdx = world.clients.length === 0 ? 0 : rint(0, world.clients.length - 1);
  const contacts = world.contacts.map((c, i) => [c, i]).filter(([c]) => c.clientIdx === clientIdx);
  const b = {
    slug: `${street.toLowerCase().replace(/[^a-z]+/g, "-")}-${num}-${slugSeq}`,
    name: `${pick(BUILDING_KIND)} ${street.split(" ")[0]} ${num}`,
    address: `${street} ${num}, ${plz} Wien`,
    clientIdx,
    contactIdx: contacts.length === 0 ? null : pick(contacts)[1],
    wonAt: monthIdx,
    lostAt: null,
    // 5 = Mon-Fri, 3 = Mon/Wed/Fri, 2 = Tue/Thu. A third of buildings get a second
    // (evening) round, which is what makes a mid-size portfolio busier than
    // buildings x 5 and is why the 2000-row cap arrives sooner than anybody expects.
    visitDays: pick([[1, 2, 3, 4, 5], [1, 3, 5], [2, 4], [1, 2, 3, 4, 5]]),
    twice: chance(0.3),
    minutes: rint(45, 165),
    priceCents: rint(38, 340) * 10_000,
    targetMin: rint(600, 4200),
    deadFrom: null,
  };
  world.buildings.push(b);
  return world.buildings.length - 1;
}

function newWorker(monthIdx, { enrolled = true, noEmail = false } = {}) {
  const name = `${pick(FIRST)} ${pick(LAST)}`;
  const n = world.workers.length + 1;
  world.workers.push({
    name,
    // @example.test can never be claimed by a real Apple ID / mailbox — same rule as seed.sql.
    email: noEmail ? null : `worker${n}@example.test`,
    phone: null, // never invent an Austrian mobile number; it could reach a real person
    hiredAt: monthIdx,
    leftAt: null,
    leftReason: null,
    rates: [{ from: monthStart(addMonths(firstMonth, monthIdx)), cents: rint(1180, 1720) }],
    enrolled,
  });
  return world.workers.length - 1;
}

// ---------------------------------------------------------------------------------
// Twelve months of growth
// ---------------------------------------------------------------------------------
function buildCompany() {
  // Month 0: two clients, three buildings, three cleaners. A one-van operation.
  for (let i = 0; i < 2; i++) {
    world.clients.push({ name: `${pick(CLIENT_KIND)} ${pick(LAST)}`, activeFrom: 0, activeTo: null });
    world.contacts.push({ clientIdx: i, name: `${pick(FIRST)} ${pick(LAST)}`, active: true });
  }
  for (let i = 0; i < 3; i++) newBuilding(0);
  for (let i = 0; i < 3; i++) newWorker(0);

  for (let m = 0; m < MONTHS; m++) {
    // --- contracts won. Growth accelerates, the way a referral-driven business does.
    const wins = m < 3 ? 1 : m < 7 ? 2 : 3;
    for (let i = 0; i < wins; i++) {
      // A new client every third building, otherwise the existing portfolio grows.
      if (world.buildings.length % 3 === 0) {
        world.clients.push({ name: `${pick(CLIENT_KIND)} ${pick(LAST)}`, activeFrom: m, activeTo: null });
        world.contacts.push({ clientIdx: world.clients.length - 1, name: `${pick(FIRST)} ${pick(LAST)}`, active: true });
      }
      newBuilding(m);
      if (m > 0) bump("contract_won");
    }

    // --- a tag that stops working. It worked for months; then it is gone and the
    //     building goes silent WHILE THE CONTRACT KEEPS BILLING. That last clause is the
    //     whole scenario, so this runs BEFORE the contract-loss block and the loss pool
    //     excludes it: on the first run both fired in month 8, picked the same building,
    //     and deactivating it turned "silent but billing" into "closed", which is not a
    //     problem at all. An injected event that quietly cancels itself is worse than no
    //     event — the report would have shown a clean bill of health.
    if (m === 8 && world.buildings.length > 6) {
      const live = world.buildings.map((b, i) => [b, i]).filter(([b]) => b.lostAt === null && b.wonAt <= 2);
      if (live.length > 0) {
        const [, idx] = pick(live);
        world.buildings[idx].deadFrom = m;
        bump("dead_tag");
      }
    }

    // --- contracts lost. Three over the year, one of them a whole small client.
    if (m === 4 || m === 8 || m === MONTHS - 1) {
      const live = world.buildings
        .map((b, i) => [b, i])
        .filter(([b]) => b.lostAt === null && b.deadFrom === null && b.wonAt < m);
      if (live.length > 2) {
        const [, idx] = pick(live);
        world.buildings[idx].lostAt = m;
        bump("contract_lost");
      }
    }

    // --- a building whose tag was NEVER written. Deliberately distinct from the one above:
    //     the dashboard's dead-tag check is "has no shift AT ALL", so it catches this one
    //     and misses the one that worked and then stopped. Both must exist or the report
    //     cannot show that the check answers a different question than its label claims.
    if (m === 9) {
      const idx = newBuilding(m);
      world.buildings[idx].deadFrom = m;
      bump("tag_never_written");
    }

    // --- hiring, sized to the round. A cleaner runs three or four buildings a day.
    const activeBuildings = () => world.buildings.filter((b) => b.wonAt <= m && (b.lostAt === null || b.lostAt > m));
    const dailyVisits = activeBuildings().reduce((n, b) => n + (b.visitDays.length / 5) * (b.twice ? 2 : 1), 0);
    // ~2.8 stops a day per cleaner. Part-time is the norm in the trade, so headcount grows
    // faster than a full-time-equivalent calculation suggests — which is the point: the
    // worker table grows, and every one of them is a person who can forget to tap out.
    const wanted = Math.max(3, Math.ceil(dailyVisits / 2.8));
    let staff = world.workers.filter((w) => w.hiredAt <= m && (w.leftAt === null || w.leftAt > m)).length;
    while (staff < wanted) {
      newWorker(m);
      staff += 1;
    }

    // --- two people who are created and never enrol. One has no email at all (the
    //     dashboard notices that); one has an email and simply never redeemed the code
    //     (the dashboard does not notice that at all).
    if (m === 2) {
      newWorker(m, { enrolled: false, noEmail: true });
      newWorker(m, { enrolled: false });
      bump("never_enrolled", 2);
    }

    // --- leavers. Resignations at the month boundary, one dismissal mid-month.
    const staffed = () =>
      world.workers.map((w, i) => [w, i]).filter(([w]) => w.enrolled && w.leftAt === null && w.hiredAt < m);
    if ((m === 3 || m === 7 || m === 10) && staffed().length >= 3) {
      const [, idx] = pick(staffed());
      world.workers[idx].leftAt = m;
      world.workers[idx].leftReason = "quit";
      bump("quit");
    }
    if (m === 6) {
      // Hire up to a crew that can survive losing one, THEN dismiss. Guarding this with
      // `if (staffed >= 3)` is what made the 24-month run produce zero dismissals: the
      // headcount curve is driven by building count, and one extra resignation upstream
      // dropped it below the guard. A required event behind a condition that depends on
      // the dice is a required event that sometimes does not happen.
      // `newWorker(m - 1)`, not `newWorker(m)`: staffed() only counts people hired in an
      // EARLIER month, so hiring into the current month never satisfies the loop and it
      // spins forever. It did — for thirty minutes, at --months 24, looking like a slow
      // simulation rather than a hang. A loop whose condition its own body cannot change.
      while (staffed().length < 3) newWorker(Math.max(0, m - 1));
      const [, idx] = pick(staffed());
      world.workers[idx].leftAt = m;
      world.workers[idx].leftReason = "fired";
      world.workers[idx].firedOnDay = 14; // mid-month, which is the awkward part
      bump("fired");
    }

    // --- rate changes. A collective-agreement uplift in month 5 for everyone on the
    //     books, plus individual raises. This is the money the report is about.
    for (const w of world.workers) {
      if (w.hiredAt > m || (w.leftAt !== null && w.leftAt <= m)) continue;
      const uplift = m === 5;
      if (uplift || (m > 0 && chance(0.06))) {
        const from = viennaToUtc(addMonths(firstMonth, m).y, addMonths(firstMonth, m).mo, 1);
        const last = w.rates[w.rates.length - 1].cents;
        const next = uplift ? Math.round(last * 1.05) : last + rint(30, 120);
        if (next !== last) {
          w.rates.push({ from, cents: next });
          bump("rate_change");
        }
      }
    }

    // --- contract price rows. Period-correct revenue (decision-28/30): a price change is
    //     a new row with valid_from, not an UPDATE.
    for (let bi = 0; bi < world.buildings.length; bi++) {
      const b = world.buildings[bi];
      if (b.wonAt !== m) continue;
      world.contracts.push({
        buildingIdx: bi,
        from: addMonths(firstMonth, m),
        to: null,
        cents: b.priceCents,
        targetMin: b.targetMin,
        note: "Erstvertrag",
      });
    }
    if (m === 7) {
      // Annual indexation. Close the current row the day before and open a new one.
      // ONLY rows that already started: a building won THIS month has valid_from = this
      // month's 1st, and closing it "the day before" makes valid_to < valid_from, which
      // the `location_contracts_period` check constraint rejects. It did, on the first run.
      const openRows = world.contracts.filter((c) => c.to === null && monthIndexOf(c.from) < m);
      for (const c of openRows) {
        c.to = addMonths(firstMonth, m);
        const next = Math.round(c.cents * 1.04);
        world.contracts.push({
          buildingIdx: c.buildingIdx,
          from: addMonths(firstMonth, m),
          to: null,
          cents: next,
          targetMin: c.targetMin,
          note: "Indexanpassung",
        });
        world.buildings[c.buildingIdx].priceCents = next;
      }
    }

    generateMonth(m);
  }
}

// ---------------------------------------------------------------------------------
// A month of shifts, worker by worker, day by day.
//
// Worker-centric on purpose: `shifts_one_open_per_worker_idx` forbids two concurrent open
// shifts, and a person cannot be in two stairwells at once, so a route is built as a
// sequence with travel time between stops. A building-centric loop produces overlapping
// shifts for one person, which no real day contains and which would make every hours
// figure in the report meaningless.
// ---------------------------------------------------------------------------------
function generateMonth(m) {
  const mk = addMonths(firstMonth, m);
  const start = monthStart(mk);
  const end = monthStart(addMonths(mk, 1));
  const daysInMonth = Math.round((end - start) / 86_400_000); // DST-safe: 30.958 -> 31

  for (let day = 1; day <= daysInMonth; day++) {
    const dayStart = viennaToUtc(mk.y, mk.mo, day, 0, 0);
    if (dayStart >= now) break;
    const dow = viennaDow(dayStart);

    // Which buildings are cleaned today.
    const todays = [];
    for (let bi = 0; bi < world.buildings.length; bi++) {
      const b = world.buildings[bi];
      if (b.wonAt > m || (b.lostAt !== null && b.lostAt <= m)) continue;
      if (b.deadFrom !== null && b.deadFrom <= m) continue; // the tag is gone: no taps
      if (!b.visitDays.includes(dow)) continue;
      todays.push(bi);
      if (b.twice) todays.push(bi); // second round in the evening
    }
    if (todays.length === 0) continue;

    // Who is on the books today.
    const crew = [];
    for (let wi = 0; wi < world.workers.length; wi++) {
      const w = world.workers[wi];
      if (!w.enrolled || w.hiredAt > m) continue;
      if (w.leftAt !== null && w.leftAt < m) continue;
      if (w.leftAt === m) {
        // Resignations take effect at the month boundary; the dismissal is mid-month.
        if (w.leftReason === "fired" && day > (w.firedOnDay ?? 14)) continue;
        if (w.leftReason === "quit") continue;
      }
      crew.push(wi);
    }
    if (crew.length === 0) continue;

    // Deal the stops round-robin. Deterministic, and it keeps each round about the size
    // of a real morning.
    const routes = crew.map(() => []);
    todays.forEach((bi, i) => routes[i % crew.length].push(bi));

    routes.forEach((stops, ri) => {
      if (stops.length === 0) return;
      const wi = crew[ri];
      // Morning rounds start 05:45-07:30; the evening half of a "twice" building is a
      // second pass on the same route, which is why the day can run long.
      let cursor = viennaToUtc(mk.y, mk.mo, day, 5, 45 + rint(0, 105));
      for (const bi of stops) {
        const b = world.buildings[bi];
        const mins = Math.max(20, b.minutes + rint(-15, 20));
        const s = { workerIdx: wi, buildingIdx: bi, start: cursor, tags: [] };

        // --- messy: the tap lands on the wrong building's tag. Nothing in the system can
        //     tell: the tag is valid, the worker is eligible, the shift is well-formed.
        let recordedBi = bi;
        if (chance(0.008)) {
          const others = world.buildings
            .map((x, i) => [x, i])
            .filter(([x, i]) => i !== bi && x.wonAt <= m && (x.lostAt === null || x.lostAt > m) && x.deadFrom === null);
          if (others.length > 0) {
            recordedBi = pick(others)[1];
            s.tags.push("wrong_building");
            bump("wrong_building");
          }
        }
        // Keep BOTH: the building that was actually cleaned and the tag that was actually
        // tapped. Only the second reaches the database (nothing in the system knows the
        // first), so this pair is the only place the cost of the mistake can be priced.
        s.trueBuildingIdx = bi;
        s.buildingIdx = recordedBi;

        if (chance(0.021)) {
          // --- messy: no tap-out. The 8h timer closes it at start+8h. Roughly three in
          //     five are eventually confirmed by a human; the rest sit there unpaid.
          s.end = new Date(cursor.getTime() + 8 * 3_600_000);
          s.autoClosed = true;
          s.correctedAt = chance(0.62) ? new Date(s.end.getTime() + rint(1, 96) * 3_600_000) : null;
          s.clientUuid = randomUUID();
          s.tags.push("forgot_tapout");
          bump("forgot_tapout");
        } else if (chance(0.014)) {
          // --- messy: dead phone. The director types it in. client_uuid NULL is the ONLY
          //     mark of that (web/lib/shifts.ts `isManualEntry`).
          s.end = new Date(cursor.getTime() + mins * 60_000);
          s.autoClosed = false;
          s.correctedAt = null;
          s.clientUuid = null;
          s.tags.push("manual_entry");
          bump("manual_entry");
        } else {
          s.end = new Date(cursor.getTime() + mins * 60_000);
          s.autoClosed = false;
          s.correctedAt = null;
          s.clientUuid = randomUUID();
        }

        // Late round crossing midnight, and sometimes the month boundary with it.
        const startMonth = monthKey(viennaMonthOf(s.start));
        const endMonth = monthKey(viennaMonthOf(s.end));
        if (viennaMonthOf(s.start).y !== viennaMonthOf(s.end).y || startMonth !== endMonth) {
          s.tags.push("month_cross");
          bump("month_cross");
        }
        if (s.start.toISOString().slice(0, 10) !== s.end.toISOString().slice(0, 10)) {
          const sd = Object.fromEntries(PARTS.formatToParts(s.start).map((x) => [x.type, x.value])).day;
          const ed = Object.fromEntries(PARTS.formatToParts(s.end).map((x) => [x.type, x.value])).day;
          if (sd !== ed) {
            s.tags.push("midnight_cross");
            bump("midnight_cross");
          }
        }

        if (s.end < now) world.shifts.push(s);
        cursor = new Date(s.end.getTime() + rint(10, 35) * 60_000); // travel
      }
    });
  }

  // --- the last round of the month, deliberately started at 22:30. It crosses midnight
  //     AND the payroll month boundary, which are two different problems: the first is a
  //     display question, the second decides which month somebody is paid in.
  //     Not left to chance — an event the catalogue names must actually occur, or the
  //     report has a row nobody tested. 22:30 is after every daytime round has finished,
  //     so it cannot overlap the worker's own day.
  {
    const lastDay = viennaToUtc(mk.y, mk.mo, daysInMonth, 22, 30);
    const crew = world.workers
      .map((w, i) => [w, i])
      .filter(([w]) => w.enrolled && w.hiredAt <= m && (w.leftAt === null || w.leftAt > m));
    const bldg = world.buildings
      .map((b, i) => [b, i])
      .filter(([b]) => b.wonAt <= m && (b.lostAt === null || b.lostAt > m) && b.deadFrom === null);
    const endsAt = new Date(lastDay.getTime() + rint(100, 170) * 60_000);
    if (crew.length > 0 && bldg.length > 0 && endsAt < now) {
      const s = {
        workerIdx: pick(crew)[1],
        buildingIdx: pick(bldg)[1],
        start: lastDay,
        end: endsAt,
        autoClosed: false,
        correctedAt: null,
        clientUuid: randomUUID(),
        tags: ["midnight_cross", "month_cross"],
      };
      world.shifts.push(s);
      bump("midnight_cross");
      bump("month_cross");
    }
  }

  // --- material requests. A handful a month; some ordered and never priced, which is the
  //     hole the P&L reports as `unpriced_requests`.
  const liveB = world.buildings.map((b, i) => [b, i]).filter(([b]) => b.wonAt <= m && (b.lostAt === null || b.lostAt > m));
  const liveW = world.workers.map((w, i) => [w, i]).filter(([w]) => w.enrolled && w.hiredAt <= m && (w.leftAt === null || w.leftAt > m));
  if (liveB.length > 0 && liveW.length > 0) {
    for (let i = 0; i < rint(1, 4); i++) {
      const created = viennaToUtc(mk.y, mk.mo, rint(1, 26), rint(8, 17), rint(0, 59));
      if (created >= now) continue;
      const item = rint(0, INVENTORY.length - 1);
      const status = pick(["submitted", "approved", "ordered", "arrived", "arrived", "rejected"]);
      const priced = status === "ordered" || status === "arrived" ? !chance(0.28) : false;
      if ((status === "ordered" || status === "arrived") && !priced) bump("unpriced_material");
      world.materials.push({
        workerIdx: pick(liveW)[1],
        buildingIdx: pick(liveB)[1],
        item,
        quantity: rint(1, 6),
        status,
        priced,
        created,
      });
    }
  }
}

/**
 * Every event the catalogue names must actually have happened.
 *
 * Not decoration. The report has one row per event and states the procedure the app offers
 * for it; a zero here means that row was written about something the run never produced,
 * and nobody would notice from the report itself. It has already happened once (`fired`
 * silently stopped firing at --months 24 when an unrelated resignation moved the headcount
 * under a guard), which is why this throws instead of warning.
 */
function assertEventsFired() {
  const missing = Object.keys(EVENTS).filter((k) => world.events[k] === 0);
  if (missing.length > 0) {
    throw new Error(
      `the catalogue names ${missing.length} event(s) this run never produced: ${missing.join(", ")}. ` +
        "Either the injector is broken or the catalogue is stale — the report must not claim either happened.",
    );
  }
}

/** One worker is clocked in right now, because at any moment somebody is. */
function leaveOneOpen() {
  const wi = world.workers.findIndex((w) => w.enrolled && w.leftAt === null);
  const bi = world.buildings.findIndex((b) => b.lostAt === null && b.deadFrom === null);
  if (wi === -1 || bi === -1) return;
  world.shifts.push({
    workerIdx: wi,
    buildingIdx: bi,
    start: new Date(now.getTime() - rint(35, 150) * 60_000),
    end: null,
    autoClosed: false,
    correctedAt: null,
    clientUuid: randomUUID(),
    tags: ["left_open"],
  });
  bump("left_open");
}

// ---------------------------------------------------------------------------------
// Write it
// ---------------------------------------------------------------------------------
async function persist() {
  // Same table list demo/seed.sql truncates, and deliberately NOT `admins`: the demo login
  // made by demo/make-admin.mjs has to survive a re-run or every recording needs a reset.
  await query(
    `TRUNCATE material_requests, location_contracts, portal_grants, shifts,
              locations, contacts, clients, inventory_items, worker_sessions,
              workers, app_settings
       RESTART IDENTITY CASCADE`,
  );

  for (const c of world.clients) {
    const row = await one("INSERT INTO clients (name, active) VALUES ($1, $2) RETURNING id", [c.name, c.activeTo === null]);
    c.id = row.id;
  }
  for (const ct of world.contacts) {
    const row = await one(
      "INSERT INTO contacts (client_id, name, email, active) VALUES ($1, $2, $3, true) RETURNING id",
      [world.clients[ct.clientIdx].id, ct.name, `kontakt${world.contacts.indexOf(ct) + 1}@example.test`],
    );
    ct.id = row.id;
  }
  for (const it of INVENTORY) {
    await query("INSERT INTO inventory_items (name, kind, unit_cost_cents) VALUES ($1, $2, $3)", it);
  }
  const inventoryIds = (await all("SELECT id FROM inventory_items ORDER BY id")).map((r) => r.id);

  for (const b of world.buildings) {
    const createdAt = monthStart(addMonths(firstMonth, b.wonAt));
    const row = await one(
      `INSERT INTO locations
         (slug, name, address, client_id, contact_id, monthly_contract_cents,
          target_minutes_per_month, geocoded_at, geocode_status, active, created_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,'OK',$9,$8) RETURNING id`,
      [
        b.slug, b.name, b.address,
        world.clients[b.clientIdx].id,
        b.contactIdx === null ? null : world.contacts[b.contactIdx].id,
        b.priceCents, b.targetMin, createdAt, b.lostAt === null,
      ],
    );
    b.id = row.id;
  }

  for (const w of world.workers) {
    const createdAt = monthStart(addMonths(firstMonth, w.hiredAt));
    const row = await one(
      `INSERT INTO workers
         (name, email, phone, hourly_rate_cents, active, created_at,
          enrolment_code_hash, enrolment_code_expires_at, enrolment_code_issued_at,
          enrolment_code_redeemed_at, apple_sub)
       VALUES ($1,$2,NULL,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING id`,
      [
        w.name, w.email,
        w.rates[w.rates.length - 1].cents, // THE GAP: one column, the LATEST rate, all history
        w.leftAt === null,
        createdAt,
        // An issued-but-never-redeemed code is a real state and must look like one. The
        // "hash" is a fixed-length hex string of no cryptographic meaning: nothing can
        // redeem it, and demo/db-guard.mjs keeps this whole file off any real database.
        w.enrolled ? null : `demo${String(world.workers.indexOf(w)).padStart(60, "0")}`,
        w.enrolled ? null : new Date(createdAt.getTime() + 30 * 86_400_000),
        w.enrolled ? null : createdAt,
        w.enrolled ? createdAt : null,
        w.enrolled ? `demo.sub.${world.workers.indexOf(w)}` : null,
      ],
    );
    w.id = row.id;
  }

  for (const c of world.contracts) {
    const b = world.buildings[c.buildingIdx];
    // Both bounds are DATE strings, never Dates. server/lib/db.js keeps `date` a string
    // precisely so a contract period cannot drift a day across a timezone; building one
    // out of a Date here would put that bug back in through the seeding door.
    const from = firstOfMonthDate(c.from);
    const toDate = c.to === null ? null : dayBeforeMonthDate(c.to);
    await query(
      `INSERT INTO location_contracts
         (location_id, client_id, monthly_contract_cents, target_minutes_per_month,
          valid_from, valid_to, note)
       VALUES ($1,$2,$3,$4,$5,$6,$7)`,
      [b.id, world.clients[b.clientIdx].id, c.cents, c.targetMin, from, toDate, c.note],
    );
  }

  // Shifts in one multi-row INSERT per 1000. `unnest` would need six parallel arrays and
  // a cast per column; a chunked VALUES list is shorter and measurably fast enough
  // (~5000 rows in well under a second) — see the write timing in the report.
  const CHUNK = 1000;
  for (let i = 0; i < world.shifts.length; i += CHUNK) {
    const slice = world.shifts.slice(i, i + CHUNK);
    const values = [];
    const params = [];
    slice.forEach((s, j) => {
      const b = j * 7;
      values.push(`($${b + 1},$${b + 2},$${b + 3},$${b + 4},$${b + 5},$${b + 6},$${b + 7})`);
      params.push(
        world.workers[s.workerIdx].id,
        world.buildings[s.buildingIdx].id,
        s.start,
        s.end ?? null,
        s.autoClosed ?? false,
        s.correctedAt ?? null,
        s.clientUuid ?? null,
      );
    });
    await query(
      `INSERT INTO shifts (worker_id, location_id, start_time, end_time, auto_closed, corrected_at, client_uuid)
       VALUES ${values.join(",")}`,
      params,
    );
  }

  for (const mr of world.materials) {
    const decided = ["approved", "ordered", "arrived", "rejected"].includes(mr.status);
    const ordered = ["ordered", "arrived"].includes(mr.status);
    await query(
      `INSERT INTO material_requests
         (worker_id, location_id, body, status, inventory_item_id, quantity, cost_cents,
          decided_at, ordered_at, arrived_at, created_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
      [
        world.workers[mr.workerIdx].id,
        world.buildings[mr.buildingIdx].id,
        `${INVENTORY[mr.item][0]} nachbestellen`,
        mr.status,
        inventoryIds[mr.item],
        mr.quantity,
        mr.priced ? INVENTORY[mr.item][2] * mr.quantity : null,
        decided ? new Date(mr.created.getTime() + 86_400_000) : null,
        ordered ? new Date(mr.created.getTime() + 2 * 86_400_000) : null,
        mr.status === "arrived" ? new Date(mr.created.getTime() + 6 * 86_400_000) : null,
        mr.created,
      ],
    );
  }

  // The margin floor, so the P&L flags something rather than reporting "not configured".
  await query("INSERT INTO app_settings (key, value) VALUES ('pl_margin_baseline_bp', '1500')");

  await query("ANALYZE"); // measure a planner that has seen the data, not a cold one
}

// ---------------------------------------------------------------------------------
// Measure. The REAL handlers, not a copy of their SQL.
// ---------------------------------------------------------------------------------
const handler = (method, path) => {
  const r = adminRoutes.find((x) => x.method === method && x.path === path);
  if (!r) throw new Error(`route ${method} ${path} is gone — the simulation measures a route that no longer exists`);
  return r.handler;
};

const median = (xs) => [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)];

/** Runs `fn` three times, returns {ms (median), bytes, body}. */
async function timed(fn) {
  let body = null;
  const runs = [];
  for (let i = 0; i < 3; i++) {
    const t0 = performance.now();
    const res = await fn();
    runs.push(performance.now() - t0);
    body = res.body;
  }
  return { ms: Math.round(median(runs) * 10) / 10, bytes: Buffer.byteLength(JSON.stringify(body)), body };
}

/**
 * The dashboard's OWN arithmetic, reproduced from web/app/page.tsx lines 116-140.
 *
 * Not a paraphrase: `unresolvedCount` filters `snapshot.shifts`, and
 * `locationsWithoutShifts` filters `snapshot.locations` against the set of location_ids
 * present in `snapshot.shifts`. Both read the LIMITed list. That is the whole point.
 */
function dashboardDerived(body) {
  const seen = new Set(body.shifts.map((s) => s.location_id));
  return {
    unresolved: body.shifts.filter((s) => s.end_time !== null && s.auto_closed && s.corrected_at === null).length,
    open: body.shifts.filter((s) => s.end_time === null).length,
    deadTagBuildings: body.locations.filter((l) => l.active && !seen.has(l.id)).length,
  };
}

async function measure() {
  const report = { seed: SEED, months: MONTHS, generatedAt: now.toISOString() };

  report.rows = await one(
    `SELECT (SELECT count(*) FROM shifts)::int              AS shifts,
            (SELECT count(*) FROM workers)::int             AS workers,
            (SELECT count(*) FROM workers WHERE active)::int AS workers_active,
            (SELECT count(*) FROM locations)::int           AS locations,
            (SELECT count(*) FROM locations WHERE active)::int AS locations_active,
            (SELECT count(*) FROM clients)::int             AS clients,
            (SELECT count(*) FROM location_contracts)::int  AS contracts,
            (SELECT count(*) FROM material_requests)::int   AS material_requests,
            pg_size_pretty(pg_total_relation_size('shifts')) AS shifts_bytes`,
  );

  // --- what the DATABASE knows, over the whole table. The truth column of the report.
  report.truth = await one(
    `SELECT count(*) FILTER (WHERE end_time IS NOT NULL AND auto_closed AND corrected_at IS NULL)::int AS unresolved,
            count(*) FILTER (WHERE end_time IS NULL)::int      AS open,
            count(*) FILTER (WHERE client_uuid IS NULL)::int   AS manual
       FROM shifts`,
  );
  report.truth.deadTagBuildings = (
    await one(
      `SELECT count(*)::int AS n FROM locations l
        WHERE l.active AND NOT EXISTS (SELECT 1 FROM shifts s WHERE s.location_id = l.id)`,
    )
  ).n;
  // The building that went silent: active, billing, and last cleaned months ago. Nothing
  // in the panel asks this question — the query exists only in this file.
  report.truth.silentBuildings = await all(
    `SELECT l.name, max(s.start_time) AS last_shift
       FROM locations l JOIN shifts s ON s.location_id = l.id
      WHERE l.active
      GROUP BY l.id, l.name
     HAVING max(s.start_time) < now() - interval '21 days'
      ORDER BY 2`,
  );

  // --- the UNBOUNDED fetch: what /, /shifts/ and /locations/ all do (web/lib/api.ts:452,
  //     563, 645 — `?limit=2000`, no from/to).
  const unbounded = await timed(() => handler("GET", "/admin/data")({ query: new URLSearchParams({ limit: "2000" }) }));
  const oldestLoaded = unbounded.body.shifts.length === 0 ? null : unbounded.body.shifts.at(-1).start_time;
  report.unbounded = {
    ms: unbounded.ms,
    bytes: unbounded.bytes,
    shiftRows: unbounded.body.shifts.length,
    limit: unbounded.body.shift_limit,
    truncated: unbounded.body.shifts.length >= unbounded.body.shift_limit,
    oldestLoaded,
    ledgerEarliest: unbounded.body.shift_bounds.earliest,
    coverageDays:
      oldestLoaded === null ? null : Math.round((now - new Date(oldestLoaded)) / 86_400_000),
    ledgerDays:
      unbounded.body.shift_bounds.earliest === null
        ? null
        : Math.round((now - new Date(unbounded.body.shift_bounds.earliest)) / 86_400_000),
    derived: dashboardDerived(unbounded.body),
  };

  // What the SHIFT LOG can and cannot show. It fetches unbounded and filters in the
  // BROWSER (web/lib/api.ts:438-452), so a month older than the loaded window renders as
  // an empty table plus a truncation notice — indistinguishable, to a reader, from "nobody
  // worked". Counting those months is the concrete form of that sentence.
  const loadedFrom = oldestLoaded === null ? null : new Date(oldestLoaded);
  report.unbounded.monthsInvisibleToShiftLog =
    loadedFrom === null
      ? 0
      : (
          await one(
            `SELECT count(*)::int AS n FROM (
               SELECT date_trunc('month', start_time AT TIME ZONE 'Europe/Vienna') AS m
                 FROM shifts GROUP BY 1
               HAVING max(start_time) < $1) t`,
            [loadedFrom.toISOString()],
          )
        ).n;

  // The MONEY behind the gap between the dashboard's count and the truth. An unresolved
  // auto-closed shift is hours a worker is not being paid for until somebody confirms it
  // (decision-10). The ones outside the loaded window are invisible on every screen that
  // offers to fix them, so this is the amount that quietly stops being chased.
  // Valued at start+8h and the worker's current rate — the same basis payroll would use
  // the moment it is confirmed, so it is what the confirmation is worth, not a guess.
  report.truth.unresolvedHiddenCents =
    loadedFrom === null
      ? 0
      : (
          await one(
            `SELECT COALESCE(SUM(ROUND(EXTRACT(EPOCH FROM (s.end_time - s.start_time)) * w.hourly_rate_cents / 3600.0)), 0)::bigint AS cents,
                    count(*)::int AS n
               FROM shifts s JOIN workers w ON w.id = s.worker_id
              WHERE s.end_time IS NOT NULL AND s.auto_closed AND s.corrected_at IS NULL
                AND s.start_time < $1`,
            [loadedFrom.toISOString()],
          )
        );

  // The buildings screen derives "last cleaned" from the same truncated list. An active
  // building whose most recent real shift is older than the window shows a wrong date or
  // none at all — and it is sorted by that date.
  report.unbounded.buildingsWithStaleLastCleaned =
    loadedFrom === null
      ? 0
      : (
          await one(
            `SELECT count(*)::int AS n FROM locations l
              WHERE l.active
                AND EXISTS (SELECT 1 FROM shifts s WHERE s.location_id = l.id)
                AND NOT EXISTS (SELECT 1 FROM shifts s WHERE s.location_id = l.id AND s.start_time >= $1)`,
            [loadedFrom.toISOString()],
          )
        ).n;

  // --- per Vienna month
  report.months = [];
  let cumulative = 0;
  let firstMonthOver2000 = null;
  let firstMonthOver500 = null;
  let firstCumulativeOver2000 = null;

  for (let m = 0; m < MONTHS; m++) {
    const mk = addMonths(firstMonth, m);
    const from = monthStart(mk).toISOString();
    const to = monthStart(addMonths(mk, 1)).toISOString();

    const data = await timed(() =>
      handler("GET", "/admin/data")({ query: new URLSearchParams({ limit: "2000", from, to }) }),
    );
    const pl = await timed(() => handler("GET", "/admin/pl")({ query: new URLSearchParams({ from, to }) }));

    const counted = await one(
      "SELECT count(*)::int AS n FROM shifts WHERE start_time >= $1 AND start_time < $2",
      [from, to],
    );
    cumulative += counted.n;

    // What the server's own payroll aggregate says (current rate, all history).
    const appCents = data.body.hours.reduce((sum, h) => sum + Number(h.pay_cents), 0);

    // What it SHOULD say: every shift valued at the rate in force when it was worked.
    // Same exclusions as the server (decision-10): no open shifts, no unresolved auto-closes.
    let truthCents = 0;
    for (const s of world.shifts) {
      if (s.end === null || s.end === undefined) continue;
      if (s.autoClosed && s.correctedAt === null) continue;
      if (s.start < new Date(from) || s.start >= new Date(to)) continue;
      const w = world.workers[s.workerIdx];
      truthCents += Math.round(((s.end - s.start) / 1000) * (rateAt(w, s.start) / 3600));
    }

    const row = {
      month: monthKey(mk),
      shifts: counted.n,
      cumulative,
      workersActive: world.workers.filter((w) => w.enrolled && w.hiredAt <= m && (w.leftAt === null || w.leftAt > m)).length,
      buildingsActive: world.buildings.filter((b) => b.wonAt <= m && (b.lostAt === null || b.lostAt > m) ).length,
      dataMs: data.ms,
      dataBytes: data.bytes,
      dataRows: data.body.shifts.length,
      truncatedAt2000: data.body.shifts.length >= 2000,
      truncatedAt500: counted.n > 500,
      plMs: pl.ms,
      plBytes: pl.bytes,
      appCents,
      truthCents,
      driftCents: appCents - truthCents,
    };
    report.months.push(row);

    if (firstMonthOver500 === null && counted.n > 500) firstMonthOver500 = row.month;
    if (firstMonthOver2000 === null && counted.n > 2000) firstMonthOver2000 = row.month;
    if (firstCumulativeOver2000 === null && cumulative > 2000) firstCumulativeOver2000 = row.month;
  }

  report.thresholds = {
    firstMonthOver500Default: firstMonthOver500,
    firstMonthOver2000Max: firstMonthOver2000,
    firstCumulativeOver2000: firstCumulativeOver2000,
    monthIndexOfCumulative2000:
      firstCumulativeOver2000 === null ? null : report.months.findIndex((r) => r.month === firstCumulativeOver2000) + 1,
  };
  const crossing = report.months.find((r) => r.month === firstCumulativeOver2000);
  if (crossing) {
    report.thresholds.atWorkers = crossing.workersActive;
    report.thresholds.atBuildings = crossing.buildingsActive;
  }
  // How much HISTORY 2000 rows buys at the run rate the company finished on. This is the
  // number that keeps shrinking as the company grows, and it is the one a director would
  // actually want on the screen: "this page can see N months back".
  const runRate = report.months[report.months.length - 1].shifts;
  report.thresholds.runRatePerMonth = runRate;
  report.thresholds.coverageMonthsAtRunRate = Math.round((2000 / runRate) * 10) / 10;
  report.thresholds.coverageMonthsAtDouble = Math.round((2000 / (runRate * 2)) * 10) / 10;

  // --- the reports the director opens at year end
  const yFrom = monthStart(firstMonth).toISOString();
  const yTo = monthStart(addMonths(firstMonth, MONTHS)).toISOString();
  const plYear = await timed(() => handler("GET", "/admin/pl")({ query: new URLSearchParams({ from: yFrom, to: yTo }) }));
  const analytics = await timed(() =>
    handler("GET", "/admin/analytics")({ query: new URLSearchParams({ from: yFrom, to: yTo, months: "24" }) }),
  );
  report.yearly = {
    plMs: plYear.ms,
    plBytes: plYear.bytes,
    plRateBasis: plYear.body.labour?.rate_basis ?? null,
    analyticsMs: analytics.ms,
    analyticsBytes: analytics.bytes,
  };

  report.drift = {
    totalAppCents: report.months.reduce((s, r) => s + r.appCents, 0),
    totalTruthCents: report.months.reduce((s, r) => s + r.truthCents, 0),
  };
  report.drift.totalDriftCents = report.drift.totalAppCents - report.drift.totalTruthCents;
  report.drift.worstMonth = [...report.months].sort((a, b) => Math.abs(b.driftCents) - Math.abs(a.driftCents))[0];

  // What a tap on the wrong tag costs the per-building P&L. The shift is well-formed, the
  // worker is eligible, the tag is valid: no validation can catch it, and no screen shows
  // it. The only number available is this one, and it exists only because the simulation
  // kept the truth alongside the record.
  let misattributedCents = 0;
  let misattributedMinutes = 0;
  for (const s of world.shifts) {
    if (!s.tags.includes("wrong_building")) continue;
    if (s.end === null || s.end === undefined) continue;
    if (s.autoClosed && s.correctedAt === null) continue;
    const secs = (s.end - s.start) / 1000;
    misattributedMinutes += Math.round(secs / 60);
    misattributedCents += Math.round(secs * (rateAt(world.workers[s.workerIdx], s.start) / 3600));
  }
  report.misattribution = {
    shifts: world.events.wrong_building,
    minutes: misattributedMinutes,
    cents: misattributedCents,
    // decision-6: the material pot is split PRO RATA BY LABOUR HOURS per building, so a
    // misattributed hour drags a share of the material cost to the wrong building too.
    materialPotCents: Number(
      (await one(
        `SELECT COALESCE(SUM(cost_cents), 0)::bigint AS c FROM material_requests
          WHERE status IN ('ordered','arrived')`,
      )).c,
    ),
  };

  report.events = world.events;
  report.eventCatalogue = EVENTS;
  return report;
}

// ---------------------------------------------------------------------------------
// --self-check: the arithmetic that everything above stands on, proven on known answers.
//
// Each assertion is written so the WRONG implementation fails it. The DST cases are the
// ones that matter: `new Date(y, m, d)` in a UTC-running process and a naive +01:00 both
// pass a summer test and fail these.
// ---------------------------------------------------------------------------------
function selfCheck() {
  const eq = (got, want, what) => {
    if (got !== want) throw new Error(`self-check: ${what}\n  got  ${got}\n  want ${want}`);
    console.log(`  ok   ${what}`);
  };

  // Vienna is +01:00 in winter, +02:00 in summer.
  eq(viennaToUtc(2026, 1, 15, 6, 0).toISOString(), "2026-01-15T05:00:00.000Z", "winter 06:00 Vienna -> 05:00Z");
  eq(viennaToUtc(2026, 7, 15, 6, 0).toISOString(), "2026-07-15T04:00:00.000Z", "summer 06:00 Vienna -> 04:00Z");
  // Spring forward 2026-03-29 02:00 -> 03:00. 01:30 exists, 03:30 exists.
  eq(viennaToUtc(2026, 3, 29, 1, 30).toISOString(), "2026-03-29T00:30:00.000Z", "before the spring gap");
  eq(viennaToUtc(2026, 3, 29, 3, 30).toISOString(), "2026-03-29T01:30:00.000Z", "after the spring gap");
  // Month boundary in local time, which is what a payroll month is.
  eq(viennaToUtc(2026, 4, 1, 0, 0).toISOString(), "2026-03-31T22:00:00.000Z", "1 April 00:00 Vienna is 31 March 22:00Z");
  // A UTC instant just before Vienna midnight belongs to the PREVIOUS Vienna month.
  eq(monthKey(viennaMonthOf(new Date("2026-03-31T22:30:00Z"))), "2026-04", "22:30Z on 31 March is April in Vienna");
  eq(monthKey(viennaMonthOf(new Date("2026-03-31T21:30:00Z"))), "2026-03", "21:30Z on 31 March is still March in Vienna");
  // A DST month has 30.958 or 31.04 days; the day count must still be an integer.
  eq(Math.round((monthStart({ y: 2026, mo: 4 }) - monthStart({ y: 2026, mo: 3 })) / 86_400_000), 31, "March has 31 days across the DST change");
  eq(Math.round((monthStart({ y: 2026, mo: 11 }) - monthStart({ y: 2026, mo: 10 })) / 86_400_000), 31, "October has 31 days across the DST change");

  // rateAt: the whole point of the drift number.
  const w = {
    rates: [
      { from: new Date("2026-01-01T00:00:00Z"), cents: 1200 },
      { from: new Date("2026-06-01T00:00:00Z"), cents: 1400 },
    ],
  };
  eq(rateAt(w, new Date("2026-03-15T08:00:00Z")), 1200, "rateAt before the raise is the old rate");
  eq(rateAt(w, new Date("2026-06-01T00:00:00Z")), 1400, "rateAt on the day of the raise is the new rate");
  eq(rateAt(w, new Date("2025-12-31T00:00:00Z")), 1200, "rateAt before any row falls back to the first");

  // addMonths across a year boundary, both ways.
  eq(monthKey(addMonths({ y: 2026, mo: 2 }, -3)), "2025-11", "addMonths backwards over new year");
  eq(monthKey(addMonths({ y: 2026, mo: 11 }, 3)), "2027-02", "addMonths forwards over new year");

  // Contract bounds are calendar DATE strings. `valid_to` must be the day BEFORE the
  // successor's `valid_from`, or the two rows overlap and the P&L bills a month twice.
  eq(firstOfMonthDate({ y: 2026, mo: 8 }), "2026-08-01", "contract valid_from is the 1st");
  eq(dayBeforeMonthDate({ y: 2026, mo: 8 }), "2026-07-31", "contract valid_to is the day before");
  eq(dayBeforeMonthDate({ y: 2026, mo: 3 }), "2026-02-28", "day before 1 March in a common year");
  eq(dayBeforeMonthDate({ y: 2024, mo: 3 }), "2024-02-29", "day before 1 March in a leap year");
  eq(dayBeforeMonthDate({ y: 2026, mo: 1 }), "2025-12-31", "day before 1 January is 31 December");

  // The handlers this file measures must still exist. A renamed route would otherwise be
  // discovered only as a mysteriously fast measurement.
  for (const [m, p] of [["GET", "/admin/data"], ["GET", "/admin/pl"], ["GET", "/admin/analytics"]]) {
    handler(m, p);
    console.log(`  ok   route ${m} ${p} exists`);
  }
  console.log("self-check: OK");
}

// ---------------------------------------------------------------------------------
const fmtEur = (cents) => `${(cents / 100).toLocaleString("de-AT", { minimumFractionDigits: 2 })} EUR`;
const kb = (b) => `${(b / 1024).toFixed(0)} kB`;

function printReport(r) {
  const L = console.log;
  L("");
  L(`nfc_demo simulation — seed ${r.seed}, ${r.months.length} months to ${r.generatedAt.slice(0, 10)}`);
  L("");
  L(`rows: ${r.rows.shifts} shifts, ${r.rows.workers} workers (${r.rows.workers_active} active), ` +
    `${r.rows.locations} buildings (${r.rows.locations_active} active), ${r.rows.clients} clients, ` +
    `${r.rows.contracts} contract rows, ${r.rows.material_requests} material requests`);
  L(`shifts table on disk: ${r.rows.shifts_bytes}`);
  L("");
  L("month     shifts  cum    wk  bld   /admin/data      /admin/pl   payroll drift");
  for (const m of r.months) {
    L(
      `${m.month}  ${String(m.shifts).padStart(6)}  ${String(m.cumulative).padStart(5)}  ` +
        `${String(m.workersActive).padStart(2)}  ${String(m.buildingsActive).padStart(3)}   ` +
        `${String(m.dataMs).padStart(6)} ms ${kb(m.dataBytes).padStart(7)}  ` +
        `${String(m.plMs).padStart(5)} ms   ${fmtEur(m.driftCents).padStart(14)}`,
    );
  }
  L("");
  L(`unbounded fetch (dashboard, shift log, buildings — web/lib/api.ts limit=2000):`);
  L(`  ${r.unbounded.ms} ms, ${kb(r.unbounded.bytes)}, ${r.unbounded.shiftRows}/${r.unbounded.limit} rows, ` +
    `truncated=${r.unbounded.truncated}`);
  L(`  it holds the last ${r.unbounded.coverageDays} days of a ${r.unbounded.ledgerDays}-day ledger`);
  L(`  dashboard would say: ${r.unbounded.derived.unresolved} unresolved, ` +
    `${r.unbounded.derived.deadTagBuildings} buildings with no shift`);
  L(`  the database says:   ${r.truth.unresolved} unresolved, ${r.truth.deadTagBuildings} buildings with no shift`);
  L(`  shift-log months that render EMPTY though they hold shifts: ${r.unbounded.monthsInvisibleToShiftLog}`);
  L(`  active buildings whose "last cleaned" is outside the window: ${r.unbounded.buildingsWithStaleLastCleaned}`);
  L(`  unresolved shifts hidden by the cap: ${r.truth.unresolvedHiddenCents.n}, worth ` +
    `${fmtEur(Number(r.truth.unresolvedHiddenCents.cents))} of unpaid hours nobody is chasing`);
  L("");
  L(`thresholds: cumulative passes 2000 in ${r.thresholds.firstCumulativeOver2000} ` +
    `(month ${r.thresholds.monthIndexOfCumulative2000} of ${r.months.length}, ` +
    `${r.thresholds.atWorkers} workers / ${r.thresholds.atBuildings} buildings)`);
  L(`            a single month passes the 500 default in ${r.thresholds.firstMonthOver500Default ?? "never"}`);
  L(`            a single month passes the 2000 max in ${r.thresholds.firstMonthOver2000Max ?? "never"}`);
  L(`            at the closing run rate of ${r.thresholds.runRatePerMonth} shifts/month, 2000 rows = ` +
    `${r.thresholds.coverageMonthsAtRunRate} months of history (${r.thresholds.coverageMonthsAtDouble} at twice the size)`);
  L("");
  L(`year P&L: ${r.yearly.plMs} ms, ${kb(r.yearly.plBytes)}, rate_basis=${r.yearly.plRateBasis}`);
  L(`year analytics (24 trend months): ${r.yearly.analyticsMs} ms, ${kb(r.yearly.analyticsBytes)}`);
  L("");
  L(`payroll drift from the single rate column: ${fmtEur(r.drift.totalDriftCents)} over ${r.months.length} months ` +
    `(app ${fmtEur(r.drift.totalAppCents)} vs rate-in-force ${fmtEur(r.drift.totalTruthCents)})`);
  L(`  worst month ${r.drift.worstMonth.month}: ${fmtEur(r.drift.worstMonth.driftCents)}`);
  L("");
  L(`labour booked to the wrong building by a wrong tag: ${r.misattribution.shifts} shifts, ` +
    `${r.misattribution.minutes} min, ${fmtEur(r.misattribution.cents)} — undetectable, and it also ` +
    `drags a pro-rata slice of the ${fmtEur(r.misattribution.materialPotCents)} material pot (decision-6)`);
  L("");
  L("injected events:");
  for (const [k, n] of Object.entries(r.events)) L(`  ${String(n).padStart(5)}  ${k} — ${r.eventCatalogue[k]}`);
  if (r.truth.silentBuildings.length > 0) {
    L("");
    L("active buildings with no shift in 21 days (no screen asks this question):");
    for (const b of r.truth.silentBuildings) L(`  ${b.name} — last shift ${b.last_shift.toISOString().slice(0, 10)}`);
  }
  L("");
}

async function main() {
  if (flag("--self-check")) {
    selfCheck();
    return 0;
  }
  await assertLocalServer();

  const t0 = performance.now();
  buildCompany();
  leaveOneOpen();
  assertEventsFired();
  console.log(`simulate: built ${world.shifts.length} shifts in memory (${Math.round(performance.now() - t0)} ms)`);

  const t1 = performance.now();
  await persist();
  console.log(`simulate: wrote them in ${Math.round(performance.now() - t1)} ms`);

  const report = await measure();
  printReport(report);
  if (JSON_OUT !== null) {
    const { writeFile } = await import("node:fs/promises");
    await writeFile(JSON_OUT, JSON.stringify(report, null, 2));
    console.log(`simulate: JSON written to ${JSON_OUT}`);
  }
  return 0;
}

main()
  .then((code) => pool.end().then(() => process.exit(code)))
  .catch((err) => {
    console.error("simulate:", err.stack ?? err.message);
    process.exit(1);
  });
