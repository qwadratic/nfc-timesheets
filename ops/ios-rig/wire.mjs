// ops/ios-rig/wire.mjs - read the rig front's wire log (logs/front.jsonl).
//
//   node wire.mjs --log FILE count                       lines in the log (a "mark")
//   node wire.mjs --log FILE --since 12 list             requests after mark 12, one per line
//   node wire.mjs --log FILE --since 12 --method POST --path /shifts/open list
//   node wire.mjs --log FILE --since 12 --path /me/schedule n    how many matched
//   node wire.mjs --log FILE --since 12 --method POST --path /shifts/open field body.location_uuid
//
// `--path` is a PREFIX match, like the front's fault rules. `field` prints the dotted field of
// every matching entry, one per line (nothing when it is absent). Reads only; never writes.
import { existsSync, readFileSync } from "node:fs";

const arg = (name, fallback) => {
  const i = process.argv.indexOf(`--${name}`);
  return i === -1 ? fallback : process.argv[i + 1];
};
const log = arg("log");
const since = Number(arg("since", "0"));
const method = arg("method");
const pathPrefix = arg("path");
const positional = process.argv.slice(2).filter((a, i, all) => !a.startsWith("--") && (i === 0 || !all[i - 1].startsWith("--")));
const verb = positional[0] ?? "list";
// --marks FILE --from NAME --to NAME: only requests whose start time lies between two marks a
// test wrote (Rig.mark). Millisecond epoch on both sides: simulator and host share a clock.
const marksFile = arg("marks");
const markFrom = arg("from");
const markTo = arg("to");
let windowStart = -Infinity;
let windowEnd = Infinity;
if (marksFile && existsSync(marksFile)) {
  const marks = Object.fromEntries(readFileSync(marksFile, "utf8").split("\n").filter(Boolean)
    .map((l) => { const [n, t] = l.split(" "); return [n, Number(t)]; }));
  if (markFrom && marks[markFrom] !== undefined) windowStart = marks[markFrom];
  if (markTo && marks[markTo] !== undefined) windowEnd = marks[markTo];
}

const lines = existsSync(log) ? readFileSync(log, "utf8").split("\n").filter(Boolean) : [];
if (verb === "count") {
  console.log(lines.length);
  process.exit(0);
}
const entries = lines.slice(since).map((l) => JSON.parse(l))
  .filter((e) => (!method || e.method === method) && (!pathPrefix || e.path.startsWith(pathPrefix)))
  .filter((e) => { const t = Date.parse(e.ts); return t >= windowStart && t <= windowEnd; });

if (verb === "n") console.log(entries.length);
else if (verb === "field") {
  const dotted = positional[1];
  for (const e of entries) {
    const v = dotted.split(".").reduce((acc, k) => (acc == null ? acc : acc[k]), e);
    if (v !== undefined) console.log(typeof v === "object" ? JSON.stringify(v) : String(v));
  }
} else {
  for (const e of entries) console.log(`${e.method} ${e.path} -> ${e.status}${e.fault ? " (fault)" : ""}${e.body ? " " + JSON.stringify(e.body) : ""}`);
}
