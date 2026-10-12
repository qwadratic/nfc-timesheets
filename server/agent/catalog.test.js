import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { agentTools, excludedAgentRoutes, resolveToolCall } from "./catalog.js";

test("every admin, schedule and workspace route has an explicit capability or exclusion", () => {
  const covered = new Set(agentTools.map((tool) => `${tool.method} ${tool.path}`));
  const routes = new Set();
  for (const file of ["admin", "schedule", "workspaces"]) {
    const source = readFileSync(new URL(`../routes/${file}.js`, import.meta.url), "utf8");
    const table = source.slice(source.lastIndexOf("export const"));
    for (const match of table.matchAll(/method:\s*"([A-Z]+)",\s*path:\s*"([^"]+)"/g)) {
      const key = `${match[1]} ${match[2]}`;
      routes.add(key);
      assert.ok(covered.has(key) || Object.hasOwn(excludedAgentRoutes, key), `Unreviewed API route: ${key}`);
      assert.ok(!(covered.has(key) && Object.hasOwn(excludedAgentRoutes, key)), `Excluded route exposed: ${key}`);
    }
  }
  for (const route of covered) assert.ok(routes.has(route), `Tool refers to missing route ${route}`);
  assert.equal(new Set(agentTools.map((tool) => tool.name)).size, agentTools.length);
});

test("fixed dispatch splits route arguments, query filters and mutation body", () => {
  const cancelled = resolveToolCall("cancel_assignment", { id: "00000000-0000-4000-8000-000000000001", version: 2 });
  assert.equal(cancelled.path, "/admin/schedule/:id/cancel");
  assert.deepEqual(cancelled.params, { id: "00000000-0000-4000-8000-000000000001" });
  assert.deepEqual(cancelled.body, { version: 2 });
  const read = resolveToolCall("get_company_data", { worker: 12, limit: 25, offset: 0 });
  assert.equal(read.query.toString(), "worker=12&limit=25&offset=0");
  assert.deepEqual(read.body, {});
});

test("rejects routing, company and global-security overrides and malformed nested writes", () => {
  for (const args of [{ tenant_id: 2 }, { company_id: 2 }, { path: "/platform/workspaces" }, { limit: 2.5 }, { limit: 2001 }, []]) {
    assert.throws(() => resolveToolCall("get_company_data", args), { code: "invalid_tool_arguments" });
  }
  assert.throws(() => resolveToolCall("set_company_setting", { key: "sms_otp_requests_per_ip", value: 10 }), { code: "invalid_tool_arguments" });
  assert.throws(() => resolveToolCall("record_revenue_bulk", { entries: [{ month: "2026-10", amount_cents: 500, tenant_id: 2 }] }), { code: "invalid_tool_arguments" });
  assert.throws(() => resolveToolCall("save_worker", { name: "Test", hourly_rate_cents: 0 }), { code: "invalid_tool_arguments" });
  assert.throws(() => resolveToolCall("create_assignment", { id: "../../platform" }), { code: "invalid_tool_arguments" });
  assert.throws(() => resolveToolCall("arbitrary_http", {}), { code: "unknown_tool" });
});

test("read and consequential-operation annotations are explicit", () => {
  for (const tool of agentTools) {
    assert.equal(tool.annotations.readOnlyHint, tool.method === "GET");
    assert.equal(tool.inputSchema.additionalProperties, false);
    assert.ok(!Object.hasOwn(tool.inputSchema.properties, "request_id"), "Reserved transport argument");
  }
  assert.equal(agentTools.find((tool) => tool.name === "send_worker_enrolment_sms").annotations.openWorldHint, true);
  assert.equal(agentTools.find((tool) => tool.name === "create_portal_grant").annotations.destructiveHint, true);
});
