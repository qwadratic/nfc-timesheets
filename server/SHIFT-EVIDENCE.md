# Shift location and photo evidence

Migration `028_shift_evidence.sql` must precede the server release. Dependencies remain
`pg` and `@sentry/node`. Tables use forced company RLS and composite company/shift foreign
keys. Photos are private PostgreSQL `bytea`, at most 2 MiB per shift. There is no public
photo URL or filesystem upload directory.

## Policy

`GET /shift-policy` (worker), `GET /admin/shift-policy` and `PUT /admin/shift-policy`
(company administrator) return `{policy:{location_interval_seconds,proof_of_work_required}}`.
The PUT body is the two policy fields directly. Interval is `0` (disabled) or an integer
from `60` to `86400`. Proof defaults to `false`. Missing company policy means both disabled.

Opening a shift snapshots both fields. Every worker shift response includes those fields
and nullable `proof_id`. Changing settings affects only subsequently opened shifts;
existing and pre-migration shifts retain their policy. Cached policy is advisory: clients
must use the server's open-shift snapshot before starting collection.

## Location

`POST /shifts/:client_uuid/locations` (worker):

```json
{"sample_uuid":"UUID","captured_at":"ISO timestamp","latitude":48.2,"longitude":16.3,"accuracy_m":4}
```

Returns `201 {accepted:true}`, or `200` for a repeated sample UUID on that same shift.
The shift must belong to the session worker, be open, and have tracking enabled. Only
finite coordinates and accuracy 0–10000m are accepted. Capture must be inside the shift,
at most ten minutes old, and no more than five seconds ahead of the server clock.
Samples are serialized on the shift lock and must respect its interval; earlier or
too-frequent samples return `429 location_interval_not_elapsed`. Closed-shift delivery
returns `409 shift_not_active`; clients must discard such samples rather than collect
or continue retrying outside a shift. This API does not promise background OS scheduling.

## Camera proof

1. Before opening the camera, call `POST /shifts/:client_uuid/proof-challenge {}`.
   Response: `201 {challenge_id,expires_at}`; expires after ten minutes.
2. Capture using the native camera only, without a gallery picker. Upload with
   `POST /shifts/:client_uuid/proof {challenge_id,captured_at,jpeg_base64}`. JPEG is bounded
   to 2 MiB decoded and 8192px per side / 24 megapixels, with marker/size validation.
   Response: `201 {proof_id}`; a repeated challenge upload returns the original ID.
   Retaking with a new challenge replaces the unconsumed photo for this shift.
3. Include `proof_id` in `POST /shifts/close` or `POST /shifts/:id/resolve`. A required
   photo must belong to this shift and be no older than ten minutes at this request.

Missing or mismatched proof returns `422 proof_required`; stale proof returns
`422 proof_expired`. Challenge rejection returns `422 proof_challenge_expired`.
Malformed image or capture time returns `422 invalid_photo` / `invalid_capture_time`.
Body size overflow is `413 body_too_large`. All worker close paths, including manual,
automatic client flags and queued writes, share the enforcement. Already completed close
retries return the stored result even after proof expiry, preserving idempotency.

The server's eight-hour timeout still closes unattended shifts without a photo. Resolving
that historical timeout requires a photo captured now; it documents the resolution, not
retroactive proof of the original end time. Required proof needs connectivity before camera
capture and upload; an offline close remains pending and needs fresh proof on reconnect.

A challenge bounds freshness and binds a submission to a signed-in worker's shift. It
does not cryptographically prove the bytes originated from a camera: camera-only source
selection is enforced by the shipped clients, not inferred from EXIF or an API claim.

## Administrator review

`GET /admin/shifts/:client_uuid/evidence` returns `{shift,samples,proof}`. `shift` contains
`id,client_uuid,location_interval_seconds,proof_of_work_required,proof_id`; `samples`
contains up to 1000 chronologically ordered `{sample_uuid,captured_at,latitude,longitude,accuracy_m}`;
`proof` is nullable `{id,captured_at,received_at}` for the consumed photo only.
`GET /admin/shifts/:client_uuid/proof/:proof_id` serves that photo as `image/jpeg` with
`Cache-Control: no-store` and `X-Content-Type-Options: nosniff`. Both require a company
admin session and answer 404 for another company's shift. Worker/operator sessions cannot
use them. Telemetry excludes photo bytes, coordinates, accuracy and proof/challenge fields.

## Verification

`DATABASE_URL=postgresql://...@127.0.0.1:.../... node server/check-workspaces.js` creates and
removes an isolated schema and restricted API role. It runs `check-shift-evidence.js`
against real HTTP and PostgreSQL, covering policy snapshots, required photo closure and
timeout resolution, freshness, malformed/oversize uploads, coordinate validation,
interval enforcement, tenant isolation and private image delivery.

Optional `--serve` retains synthetic fixtures until shutdown. `PREVIEW_PORT` defaults to
8080; use a free port when another preview is running. The real company's schema is never
used by this suite. Browser, Android camera and iOS camera verification are separate checks.
