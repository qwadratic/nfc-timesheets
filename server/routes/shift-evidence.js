import { randomUUID } from "node:crypto";
import { all, one, transaction } from "../lib/db.js";
import { fail } from "../lib/http.js";
import { captureTime, decodePhoto, EVIDENCE_TTL_MS, MAX_PHOTO_BYTES, shiftPolicy, validateLocation, validatePolicy } from "../lib/shift-evidence.js";
import * as v from "../lib/validate.js";

async function getPolicy() {
  return { status: 200, body: { policy: await shiftPolicy() } };
}

async function setPolicy({ body }) {
  const policy = validatePolicy(body);
  return transaction(async () => {
    await one(`INSERT INTO shift_policies (location_interval_seconds,proof_of_work_required) VALUES ($1,$2)
      ON CONFLICT (tenant_id) DO UPDATE SET location_interval_seconds=$1,proof_of_work_required=$2,updated_at=now()
      RETURNING tenant_id`, [policy.location_interval_seconds, policy.proof_of_work_required]);
    return { status: 200, body: { policy } };
  });
}

async function ownShift(params, session) {
  const uuid = v.clientUuid(params.client_uuid);
  const shift = await one("SELECT * FROM shifts WHERE client_uuid=$1 AND worker_id=$2 FOR UPDATE", [uuid, session.workerId]);
  if (!shift) fail(404, "unknown_shift");
  return shift;
}

function canPhotograph(shift) {
  if (shift.end_time !== null && !(shift.auto_closed && shift.corrected_at === null)) fail(409, "shift_not_active");
  if (!shift.proof_of_work_required) fail(409, "proof_not_required");
}

async function location(ctx) {
  return transaction(async () => {
    const shift = await ownShift(ctx.params, ctx.session);
    if (shift.end_time !== null) fail(409, "shift_not_active");
    if (shift.location_interval_seconds === 0) fail(409, "location_tracking_disabled");
    const sample = v.uuid(ctx.body.sample_uuid, "sample_uuid");
    const existing = await one("SELECT shift_id FROM shift_locations WHERE sample_uuid=$1", [sample]);
    if (existing) {
      if (existing.shift_id !== shift.id) fail(409, "sample_conflict");
      return { status: 200, body: { accepted: true } };
    }
    validateLocation(ctx.body);
    const captured = captureTime(ctx.body.captured_at, shift.start_time);
    const latest = await one("SELECT captured_at FROM shift_locations WHERE shift_id=$1 ORDER BY captured_at DESC LIMIT 1", [shift.id]);
    if (latest && captured.getTime() - new Date(latest.captured_at).getTime() < shift.location_interval_seconds * 1000) {
      fail(429, "location_interval_not_elapsed", undefined, { "retry-after": String(shift.location_interval_seconds) });
    }
    await one(`INSERT INTO shift_locations (sample_uuid,shift_id,captured_at,latitude,longitude,accuracy_m)
      VALUES ($1,$2,$3,$4,$5,$6) RETURNING sample_uuid`, [sample, shift.id, captured, ctx.body.latitude, ctx.body.longitude, ctx.body.accuracy_m]);
    return { status: 201, body: { accepted: true } };
  });
}

async function challenge(ctx) {
  return transaction(async () => {
    const shift = await ownShift(ctx.params, ctx.session);
    canPhotograph(shift);
    const id = randomUUID();
    const now = new Date();
    await one("UPDATE shifts SET proof_challenge_id=$2,proof_challenged_at=$3 WHERE id=$1 RETURNING id", [shift.id, id, now]);
    return { status: 201, body: { challenge_id: id, expires_at: new Date(now.getTime() + EVIDENCE_TTL_MS).toISOString() } };
  });
}

async function upload(ctx) {
  return transaction(async () => {
    const shift = await ownShift(ctx.params, ctx.session);
    canPhotograph(shift);
    const challengeId = v.uuid(ctx.body.challenge_id, "challenge_id");
    const existing = await one("SELECT id,challenge_id FROM shift_proofs WHERE shift_id=$1", [shift.id]);
    if (existing?.challenge_id === challengeId) return { status: 200, body: { proof_id: existing.id } };
    if (shift.proof_challenge_id !== challengeId || !shift.proof_challenged_at || Date.now() - new Date(shift.proof_challenged_at).getTime() > EVIDENCE_TTL_MS) fail(422, "proof_challenge_expired");
    const captured = captureTime(ctx.body.captured_at, shift.proof_challenged_at);
    const bytes = decodePhoto(ctx.body.jpeg_base64);
    const id = randomUUID();
    await one(`INSERT INTO shift_proofs (id,shift_id,challenge_id,captured_at,jpeg) VALUES ($1,$2,$3,$4,$5)
      ON CONFLICT (shift_id) DO UPDATE SET id=$1,challenge_id=$3,captured_at=$4,jpeg=$5,received_at=now() RETURNING id`,
    [id, shift.id, challengeId, captured, bytes]);
    return { status: 201, body: { proof_id: id } };
  });
}

async function adminShift(params) {
  const shift = await one("SELECT id,client_uuid,location_interval_seconds,proof_of_work_required,proof_id FROM shifts WHERE client_uuid=$1", [v.clientUuid(params.client_uuid)]);
  if (!shift) fail(404, "unknown_shift");
  return shift;
}

async function evidence({ params }) {
  const shift = await adminShift(params);
  const samples = await all("SELECT sample_uuid,captured_at,latitude,longitude,accuracy_m FROM shift_locations WHERE shift_id=$1 ORDER BY captured_at LIMIT 1000", [shift.id]);
  const proof = await one("SELECT id,captured_at,received_at FROM shift_proofs WHERE shift_id=$1 AND id=$2", [shift.id, shift.proof_id]);
  return { status: 200, body: { shift, samples, proof } };
}

async function photo({ params }) {
  const shift = await adminShift(params);
  const proof = await one("SELECT jpeg FROM shift_proofs WHERE shift_id=$1 AND id=$2 AND id=$3", [shift.id, v.uuid(params.proof_id, "proof_id"), shift.proof_id]);
  if (!proof) fail(404, "unknown_proof");
  return { status: 200, binary: proof.jpeg, contentType: "image/jpeg" };
}

export const shiftEvidenceRoutes = [
  { method: "GET", path: "/shift-policy", auth: "worker", handler: getPolicy },
  { method: "GET", path: "/admin/shift-policy", auth: "admin", handler: getPolicy },
  { method: "PUT", path: "/admin/shift-policy", auth: "admin", handler: setPolicy },
  { method: "POST", path: "/shifts/:client_uuid/locations", auth: "worker", handler: location },
  { method: "POST", path: "/shifts/:client_uuid/proof-challenge", auth: "worker", handler: challenge },
  { method: "POST", path: "/shifts/:client_uuid/proof", auth: "worker", bodyLimit: Math.ceil(MAX_PHOTO_BYTES / 3) * 4 + 4096, handler: upload },
  { method: "GET", path: "/admin/shifts/:client_uuid/evidence", auth: "admin", handler: evidence },
  { method: "GET", path: "/admin/shifts/:client_uuid/proof/:proof_id", auth: "admin", handler: photo },
];
