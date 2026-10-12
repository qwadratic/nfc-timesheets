import { one } from "./db.js";
import { fail } from "./http.js";

export const EVIDENCE_TTL_MS = 10 * 60 * 1000;
export const MAX_PHOTO_BYTES = 2 * 1024 * 1024;

export async function shiftPolicy() {
  return await one("SELECT location_interval_seconds, proof_of_work_required FROM shift_policies") ??
    { location_interval_seconds: 0, proof_of_work_required: false };
}

export function validatePolicy(body) {
  const interval = body.location_interval_seconds;
  if (!Number.isInteger(interval) || (interval !== 0 && (interval < 60 || interval > 86400))) fail(422, "invalid_location_interval");
  if (typeof body.proof_of_work_required !== "boolean") fail(422, "invalid_proof_policy");
  return { location_interval_seconds: interval, proof_of_work_required: body.proof_of_work_required };
}

export function captureTime(value, earliest, now = Date.now()) {
  const ms = typeof value === "string" ? Date.parse(value) : NaN;
  if (!Number.isFinite(ms) || ms > now + 5000 || ms < now - EVIDENCE_TTL_MS || ms < new Date(earliest).getTime()) {
    fail(422, "invalid_capture_time");
  }
  return new Date(ms);
}

export function validateLocation(body) {
  for (const [key, min, max] of [["latitude", -90, 90], ["longitude", -180, 180], ["accuracy_m", 0, 10000]]) {
    if (typeof body[key] !== "number" || !Number.isFinite(body[key]) || body[key] < min || body[key] > max) fail(422, "invalid_location");
  }
}

// Reject non-JPEG payloads, huge dimensions and malformed marker lengths without
// an image library. This does not attest camera origin; native camera-only UI does.
export function decodePhoto(base64) {
  if (typeof base64 !== "string" || base64.length > Math.ceil(MAX_PHOTO_BYTES / 3) * 4 ||
      base64.length % 4 !== 0 || /[^A-Za-z0-9+/=]/.test(base64)) fail(422, "invalid_photo");
  const bytes = Buffer.from(base64, "base64");
  if (bytes.toString("base64") !== base64) fail(422, "invalid_photo");
  if (bytes.length < 128 || bytes.length > MAX_PHOTO_BYTES || bytes[0] !== 0xff || bytes[1] !== 0xd8 ||
      bytes.at(-2) !== 0xff || bytes.at(-1) !== 0xd9) fail(422, "invalid_photo");
  let offset = 2;
  let dimensions = false;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset++] !== 0xff) fail(422, "invalid_photo");
    while (bytes[offset] === 0xff) offset++;
    if (offset + 3 > bytes.length) fail(422, "invalid_photo");
    const marker = bytes[offset++];
    if (marker === 0xda) {
      if (!dimensions) fail(422, "invalid_photo");
      return bytes;
    }
    if (marker === 0xd9 || marker === 0x00 || marker === 0xd8) fail(422, "invalid_photo");
    const length = bytes.readUInt16BE(offset);
    if (length < 2 || offset + length > bytes.length) fail(422, "invalid_photo");
    if ([0xc0, 0xc1, 0xc2].includes(marker)) {
      if (length < 8) fail(422, "invalid_photo");
      const height = bytes.readUInt16BE(offset + 3), width = bytes.readUInt16BE(offset + 5);
      if (width < 1 || height < 1 || width > 8192 || height > 8192 || width * height > 24000000) fail(422, "invalid_photo");
      dimensions = true;
    }
    offset += length;
  }
  fail(422, "invalid_photo");
}

// Called while the caller holds the shift row lock in the close/resolve transaction.
export async function requireShiftProof(shift, proofId) {
  if (!shift.proof_of_work_required) return null;
  if (typeof proofId !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(proofId)) fail(422, "proof_required");
  const proof = await one("SELECT id, captured_at FROM shift_proofs WHERE shift_id=$1 AND id=$2::uuid", [shift.id, proofId]);
  if (!proof) fail(422, "proof_required");
  if (Date.now() - new Date(proof.captured_at).getTime() > EVIDENCE_TTL_MS) fail(422, "proof_expired");
  return proof.id;
}
