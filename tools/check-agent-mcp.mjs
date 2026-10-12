import assert from "node:assert/strict";
import { createServer } from "node:http";
import { Readable, Writable } from "node:stream";
import { createBridge, runStdio, MAX_INPUT_BYTES, MAX_OUTPUT_BYTES } from "./agent-mcp.mjs";

const token = `nfc_agent_${"a".repeat(64)}`; // Fixture only; never a real credential.
const calls = [];
let mode = "ok";
const server = createServer(async (req, res) => {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const body = chunks.length ? JSON.parse(Buffer.concat(chunks)) : undefined;
  calls.push({ path: req.url, body, authorization: req.headers.authorization });
  if (mode === "redirect") { res.writeHead(302, { location: "/stolen" }); res.end(); return; }
  if (mode === "timeout") return;
  if (mode === "large") { res.writeHead(200, { "content-length": MAX_OUTPUT_BYTES }); res.end(); return; }
  res.setHeader("content-type", "application/json");
  if (mode === "unauthorized") { res.writeHead(401); res.end(JSON.stringify({ error: "unauthorized" })); return; }
  if (req.url === "/agent/context") res.end(JSON.stringify({ company: { id: 7, name: "Fixture" }, timezone: "Europe/Vienna" }));
  else if (req.url === "/agent/tools") res.end(JSON.stringify({ tools: [{ name: "create_worker", inputSchema: { type: "object", required: ["request_id"] } }] }));
  else res.end(JSON.stringify({ status: 201, result: { worker: { id: 9 } }, request_id: body.request_id }));
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const url = `http://127.0.0.1:${server.address().port}`;
const request = (method, params = {}, id = 1) => ({ jsonrpc: "2.0", id, method, params });
const init = request("initialize", { protocolVersion: "2025-11-25", capabilities: {}, clientInfo: { name: "fixture", version: "1" } });
try {
  for (const bad of ["http://example.com", "https://user:pass@example.com", `${url}/path`, `${url}?token=x`, "file:///tmp/x"]) {
    assert.throws(() => createBridge({ url: bad, token }));
  }
  assert.throws(() => createBridge({ url, token: "wrong" }));
  const handle = createBridge({ url, token, timeoutMs: 2000 });
  assert.equal((await handle(request("tools/list"))).error.code, -32000);
  assert.deepEqual((await handle(request("ping"))).result, {});
  const initialized = await handle(init);
  assert.equal(initialized.result.protocolVersion, "2025-11-25");
  assert.match(initialized.result.instructions, /Fixture/);
  assert.equal((await handle(request("tools/list"))).error.code, -32000);
  assert.equal(await handle({ jsonrpc: "2.0", method: "notifications/initialized" }), null);
  assert.equal((await handle(request("tools/list"))).result.tools[0].name, "create_worker");
  const id = "01010101-0101-4101-8101-010101010101";
  const result = await handle(request("tools/call", { name: "create_worker", arguments: { name: "Anna", request_id: id } }));
  assert.equal(result.result.isError, false);
  assert.equal(JSON.parse(result.result.content[0].text).request_id, id);
  assert.deepEqual(calls.at(-1).body, { arguments: { name: "Anna" }, request_id: id });
  assert.equal(calls.at(-1).authorization, `Bearer ${token}`);
  assert.equal((await handle(request("tools/call", { name: "../platform", arguments: {} }))).error.code, -32602);
  assert.equal((await handle(request("tools/call", { name: "get_workspace", arguments: [] }))).error.code, -32602);
  assert.equal((await handle(request("other"))).error.code, -32601);
  assert.equal((await handle([])).error.code, -32600);
  mode = "unauthorized";
  assert.equal((await handle(request("tools/call", { name: "get_workspace" }))).result.isError, true);
  for (const failure of ["redirect", "timeout", "large"]) {
    mode = failure;
    const before = calls.length;
    const reply = await handle(request("tools/call", { name: "create_worker", arguments: { request_id: id } }));
    assert.equal(reply.result.isError, true, failure);
    assert.equal(calls.length, before + 1, `${failure} must not redirect or retry`);
    assert.ok(!JSON.stringify(reply).includes(token));
  }
  mode = "ok";
  for (const version of ["2025-06-18", "2025-03-26", "unknown"]) {
    const bridge = createBridge({ url, token });
    const result = await bridge({ ...init, params: { ...init.params, protocolVersion: version } });
    assert.equal(result.result.protocolVersion, version === "unknown" ? "2025-11-25" : version);
  }
  let output = "";
  const sink = new Writable({ write(chunk, encoding, done) { output += chunk.toString(); done(); } });
  await runStdio(handle, Readable.from(["{bad}\n", JSON.stringify(request("ping")) + "\n", JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n"]), sink);
  const replies = output.trim().split("\n").map(JSON.parse);
  assert.equal(replies.length, 2);
  assert.equal(replies[0].error.code, -32700);
  assert.deepEqual(replies[1].result, {});
  await assert.rejects(runStdio(handle, Readable.from(["x".repeat(MAX_INPUT_BYTES + 1)]), sink), /line limit/);
  output = "";
  await runStdio(async () => ({ jsonrpc: "2.0", id: 1, result: "x".repeat(MAX_OUTPUT_BYTES) }), Readable.from([JSON.stringify(request("ping")) + "\n"]), sink);
  assert.equal(JSON.parse(output).error.code, -32000);
  console.log("check-agent-mcp: PASS (protocol lifecycle, discovery, envelope, URL/credential validation, no redirects/retries, timeout, bounded streams)");
} finally {
  server.closeAllConnections();
  await new Promise((resolve) => server.close(resolve));
}

