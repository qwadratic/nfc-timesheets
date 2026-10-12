// ops/ios-rig/front.mjs - HTTPS in front of the rig's API, for the simulator. A rig prop, NOT
// part of the product (the shipped server has no TLS in it and must not grow any: decision-16).
//
// It is demo/tls-front.mjs plus the two things a driven walk needs and a bare front cannot give:
//
//   1. A WIRE LOG. One JSON line per request the app made - method, path, the JSON body, the
//      status the server answered - so a criterion like "POST /shifts/open carried the ZONE
//      uuid with manual:true" or "no POST ever carried a building uuid" is read off what really
//      went over the wire, not inferred from the server's row. Only a worker's enrolment CODE is
//      redacted; there is no secret in a loopback rig, but a code is a bearer credential and
//      habits matter.
//   2. FAULT INJECTION, from a file re-read on every request, so a state flip needs no restart:
//        [{"path":"/roster","status":503}]                     answer 503 without asking the API
//        [{"path":"/me/schedule","method":"GET","status":404,"body":{"error":"not_found"}}]
//        [{"path":"/me/schedule","delay_ms":6000}]              forward, but only after 6 s
//      A rule matches when the request path STARTS with `path` (and `method` equals, if given).
//      `rig.sh fault ...` writes this file; an absent or empty file is a plain pass-through.
//
// "The server is down" has two honest shapes and the rig offers both: `rig.sh server-stop` kills
// the API and this front answers 502 (the app sees a 5xx), `rig.sh net-down` kills THIS process
// and the phone's connection is refused (the app sees status 0).
//
// Loopback only, listen side and upstream side, and it refuses to start otherwise.
import { appendFileSync, existsSync, readFileSync } from "node:fs";
import { request } from "node:http";
import { createServer } from "node:https";

const arg = (name, fallback) => {
  const i = process.argv.indexOf(`--${name}`);
  return i === -1 ? fallback : process.argv[i + 1];
};

const certDir = arg("cert");
const port = Number(arg("port", "8444"));
const host = arg("host", "127.0.0.1");
const [upHost, upPort] = arg("upstream", "127.0.0.1:8082").split(":");
const logFile = arg("log");
const faultsFile = arg("faults");

const LOOPBACK = ["127.0.0.1", "localhost", "::1"];
if (!certDir || !logFile || !faultsFile) {
  console.error("rig front: --cert DIR --log FILE --faults FILE are required");
  process.exit(64);
}
if (!LOOPBACK.includes(upHost)) {
  console.error(`rig front: refusing to proxy to "${upHost}" - loopback only.`);
  process.exit(1);
}
if (!LOOPBACK.includes(host)) {
  console.error(`rig front: refusing to listen on "${host}" - loopback only.`);
  process.exit(1);
}

function faults() {
  if (!existsSync(faultsFile)) return [];
  try {
    const parsed = JSON.parse(readFileSync(faultsFile, "utf8"));
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function describeBody(buffer) {
  if (buffer.length === 0) return undefined;
  const text = buffer.toString("utf8");
  try {
    const json = JSON.parse(text);
    if (json && typeof json === "object" && "code" in json) json.code = "[redacted]";
    return json;
  } catch {
    return text.slice(0, 512);
  }
}

const server = createServer(
  { key: readFileSync(`${certDir}/server.key`), cert: readFileSync(`${certDir}/server.pem`) },
  (req, res) => {
    const startedAt = Date.now();
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", async () => {
      const body = Buffer.concat(chunks);
      const entry = { ts: new Date(startedAt).toISOString(), method: req.method, path: req.url };
      const parsedBody = describeBody(body);
      if (parsedBody !== undefined) entry.body = parsedBody;
      const finish = (status, extra = {}) => {
        entry.status = status;
        entry.ms = Date.now() - startedAt;
        Object.assign(entry, extra);
        appendFileSync(logFile, `${JSON.stringify(entry)}\n`);
      };

      if (req.url === "/__rig/ping") {
        res.writeHead(200, { "content-type": "text/plain" });
        res.end("ok\n");
        return;
      }

      const rule = faults().find(
        (r) => typeof r.path === "string" && req.url.startsWith(r.path) && (!r.method || r.method === req.method),
      );
      if (rule?.delay_ms) await new Promise((r) => setTimeout(r, Number(rule.delay_ms)));
      if (rule?.status) {
        const payload = JSON.stringify(rule.body ?? { error: "rig_fault" });
        res.writeHead(Number(rule.status), { "content-type": "application/json", "content-length": Buffer.byteLength(payload) });
        res.end(payload);
        finish(Number(rule.status), { fault: true });
        return;
      }

      const up = request(
        { host: upHost, port: Number(upPort), method: req.method, path: req.url, headers: req.headers },
        (upRes) => {
          res.writeHead(upRes.statusCode, upRes.headers);
          upRes.pipe(res);
          upRes.on("end", () => finish(upRes.statusCode, rule?.delay_ms ? { delayed_ms: rule.delay_ms } : {}));
        },
      );
      up.on("error", (err) => {
        if (!res.headersSent) res.writeHead(502, { "content-type": "text/plain" });
        res.end("upstream unavailable\n");
        finish(502, { upstream_error: err.message });
      });
      up.end(body);
    });
  },
);

server.listen(port, host, () => {
  console.log(`rig front: https on ${host}:${port} -> http://${upHost}:${upPort}`);
});
for (const signal of ["SIGTERM", "SIGINT"]) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
