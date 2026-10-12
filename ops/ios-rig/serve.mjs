// ops/ios-rig/serve.mjs - the product's API, bound to 127.0.0.1 only. ROUTE FOR ROUTE the real
// server/server.js: this file imports createServer() and calls listen() with a host, exactly as
// server/check-workspaces.js does. server.js's own `isMain` boot listens on every interface,
// which is right on the VM behind the exe.dev proxy and wrong on a laptop.
//
// It adds nothing to the product and changes nothing in it. What it REFUSES is the point:
//   - a DATABASE_URL that is not a loopback host,
//   - any telemetry or third-party credential in the environment (Sentry, Twilio, Resend,
//     Google, App Store Connect): they are DELETED from the child's environment and the process
//     says so, so a rig can never reach a real service by accident.
//
//   RIG_API_PORT=8082 DATABASE_URL=postgres://rig_api:...@127.0.0.1:5433/rig APP_KEY=... \
//     node ops/ios-rig/serve.mjs
import { mkdirSync } from "node:fs";

const LOOPBACK = new Set(["127.0.0.1", "localhost", "::1", "[::1]"]);

const dbUrl = process.env.DATABASE_URL;
if (!dbUrl || !LOOPBACK.has(new URL(dbUrl).hostname)) {
  console.error("rig serve: DATABASE_URL must be a loopback PostgreSQL URL");
  process.exit(1);
}

// By PREFIX, not by a list somebody has to keep complete: whatever a future server version
// reads for a third party, a variable that starts like one of these never reaches it.
const THIRD_PARTY = /^(SENTRY|TWILIO|RESEND|GOOGLE|APPSTORECONNECT|ASC|STRIPE|OPENAI|ANTHROPIC|AWS)_/;
const stripped = Object.keys(process.env).filter((k) => THIRD_PARTY.test(k));
for (const key of stripped) delete process.env[key];
if (stripped.length) console.log(`rig serve: removed from the environment: ${stripped.join(", ")}`);

process.env.SMS_ENABLED = "false";
// No static export in the rig: an empty directory, so a stray GET can only 404.
const publicDir = process.env.RIG_PUBLIC_DIR;
if (publicDir) {
  mkdirSync(publicDir, { recursive: true });
  process.env.PUBLIC_DIR = publicDir;
}

const port = Number(process.env.PORT ?? process.env.RIG_API_PORT ?? 8082);
process.env.PORT = String(port);

// Dynamic import: lib/db.js reads DATABASE_URL when it is first loaded, so the environment
// above has to be final before this line.
const { assertEnv, createServer } = await import("../../server/server.js");
assertEnv();
const server = createServer();
server.listen(port, "127.0.0.1", () => {
  console.log(`rig serve: timesheets api on 127.0.0.1:${port} (loopback only)`);
});
for (const signal of ["SIGTERM", "SIGINT"]) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
