---
id: decision-31
title: >-
  Worker identity is a confirmed phone number - SMS OTP replaces Sign in with
  Apple and demotes enrolment codes to break-glass
date: '2026-08-12 05:32'
status: proposed
---
> **Numbering note.** The task brief asked for `decision-29`. That number was taken on
> 2026-08-08 by "The admin panel works on a phone", and 30 by "Worker rate history". This
> record is 31. Nothing else about the brief changed.

## Context

Worker identity has been decided twice and is about to be decided a third time. That is
the important fact in this record, so it goes first.

- **decision-22** (accepted): identity is Sign in with Apple. It closed a real hole — the
  server had been trusting `worker_id` from the request body — and it is live.
- **decision-26** (accepted): Sign in with Apple does not survive Android, because an
  Android-owning cleaner has no Apple ID and "identity that depends on owning a
  competitor's hardware is not identity, it is a hiring filter". Android enrols with an
  admin-issued code instead. iOS keeps Apple. Two enrolment mechanisms, one session.

decision-26 was right about the constraint and picked the best option **available at the
time it was written**. What it did not resolve, and what this record resolves:

1. **Two front doors that fail differently.** Apple sign-in fails with a JWKS fetch, a
   nonce mismatch, or a `privaterelay.appleid.com` address the admin has to be read aloud
   and pasted back into the panel. Enrolment codes fail by expiring after an hour. Two
   support scripts, two trust boundaries, two things to keep correct — and decision-26
   said so itself under Costs.
2. **`workers.email` became load-bearing for a population that does not use email.**
   Cleaners are not an email-first workforce. The admin has to obtain, type, and keep
   correct an address that exists only so a phone can sign in. Every typo is a
   `not_eligible` dead end.
3. **The enrolment code is a bearer credential in transit, spoken over the phone.**
   decision-26 named this as its real cost. It is issued by a human, to a human, and a
   code that reaches the wrong person is the expected failure mode, not the exotic one.
4. **The director is the single point of failure for onboarding.** Both existing paths
   need the director awake: to type an email into the panel, or to press "create code"
   and read it out. That is fine for four workers and does not survive twenty.
5. **The phone number was already there and already mandatory in practice.** `workers.phone`
   has existed since migration 003. The director asked for "exactly two fields for a
   cleaner: name and phone". Everyone who works here has a working mobile number — it is
   how the job is coordinated. It is the only identifier that is already universal in this
   workforce and already collected.

The honest counter-argument, stated before the decision rather than after it: **a phone
number is a weaker identity than an Apple ID.** SIM swap is real, Austrian mobile numbers
are recycled after deactivation, and SMS is delivered by carriers we do not control. This
record accepts that downgrade deliberately; the reasoning is under Consequences and it
depends on the blast radius being small.

## Decision

**Worker identity is a phone number that the worker has proved they control.** Proof is a
one-time code delivered by SMS, verified by this server. Confirmation is **mandatory**: a
worker row without `phone_confirmed_at` can hold a session but the app nags at every
launch until it is set.

The full design — schema, arithmetic, endpoints, message bodies, failure screens, the
verification plan — is `backlog/docs/SMS-AUTH.md`. This record states only what is binding.

### 1. Phone number is the identity; E.164 is the stored form

`workers.phone_e164` is added: `TEXT UNIQUE CHECK (phone_e164 ~ '^\+[1-9][0-9]{7,14}$')`.
Normalisation happens **at the trust boundary**, in `lib/phone.js`, and is the single
implementation for the admin panel and the auth route. `workers.phone` stays as the
as-typed contact string, because it is what the director recognises.

Austrian numbers are the common case and the **only** case where a national-format input
is accepted (`0664…` → `+43664…`). A bare number with no `+`, no `00` and no leading `0`
is **rejected, never guessed**. A number that already carries `+` or `00` is honoured as
written, so a Slovak, Romanian, German or Hungarian mobile works.

### 2. The OTP

Six digits, `0-9`, five minute TTL, single use, at most **three** verification attempts per
challenge, stored only as `hashToken()` SHA-256 of `"<phone_e164>:<code>"`.

The lookup key is the **phone number**, never the digest. This is the one structural
difference from decision-26's enrolment codes and it is what makes six digits safe: the
search space is **not shared**. An attacker must name the phone they are attacking, so a
guess is worth `1e-6` against one worker instead of `n/2^40` against all of them.

Six digits is also not a security number — it is a **usability** number, chosen because
iOS and Android autofill numeric codes and Crockford base32 cannot be autofilled. The
security comes from the per-challenge attempt burn and the per-phone send cap. The
arithmetic is written out in `SMS-AUTH.md` and, exactly as `lib/enrolment.js` says of its
own block, **must be redone if the length, TTL, attempt limit, send cap or fleet size
changes.**

### 3. Byte-identical failure, on both endpoints

`POST /auth/sms/start` answers `200 {"sent":true,"expires_in":300}` **always** — unknown
number, deactivated worker, malformed input, Twilio unconfigured, daily budget spent. Any
other answer turns it into a worker directory.

`POST /auth/sms/verify` answers `401 {"error":"invalid_code"}` for every failure: wrong,
expired, already used, attempts exhausted, no challenge, worker deactivated. Same status,
same body, no field, no message — the rule decision-26 already set for `/auth/code`, for
the same reason.

### 4. `worker_sessions` is untouched

Same table, same `ts_worker` cookie, same 90-day TTL, same `requireWorkerSession`, same
`AND w.active` re-check on every request. **`worker_id` still comes from the session and
never from a request body (decision-22 stands, unamended).** SMS OTP is a third way to
mint the same row, and nothing downstream of the mint changes. This is the property that
made decision-26 safe to add and it is the property that makes this safe to add.

One addition: **sessions roll**. A session used with more than 7 days elapsed has its
`expires_at` pushed out. An actively working cleaner then never re-authenticates, which is
what removes "SMS did not arrive" from the door at 06:00 — see item 7.

### 5. Sign in with Apple is RETIRED

Plainly, since the brief asks for it plainly: **it goes.**

- decision-26 already established it cannot be the fleet's identity.
- Keeping it as a third mechanism means a third trust boundary, a JWKS fetch on the
  sign-in path, nonce handling, and the Hide My Email two-pass dance — for a population
  now fully served by a mechanism that works on every phone.
- Removing it lets `workers.email` stop being an identity column.
- App Store Guideline 4.8 requires an equivalent option only when an app offers a
  **third-party or social** login. A first-party phone-number login is not that. **This
  claim is not yet verified against the current guideline text and must be, in writing,
  before the next submission** — it is the one thing that could reverse this item.

`workers.apple_sub` is **kept as a nullable, no-longer-read audit column**, not dropped.
Dropping it would destroy the record of how the pilot workers originally enrolled, and
costs nothing to keep. `POST /auth/apple` returns `410 gone` for one release, then is
deleted with `lib/apple.js`.

### 6. Enrolment codes are DEMOTED, not deleted

decision-26's mechanism survives as **break-glass only**, relabelled as such in the admin
panel. It exists because a permanently undeliverable number (dead prepaid SIM, no
coverage, a number entered wrong twice) must not mean a person cannot be paid — the exact
failure decision-26 rejected in Sign in with Apple.

The demotion is real, not cosmetic: **a break-glass code does not confirm a phone number.**
It mints a session with `phone_confirmed_at` still NULL, and the app nags at every launch
until the worker completes SMS confirmation. "Mandatory phone confirmation" stays true.

### 7. Delivery failure is a normal path with a designed response

In order, and only the last one needs the director:

1. **Resend** — 60s, then 120s, at most 3 sends per number per hour. Carrier delay is the
   common case and time fixes it.
2. **Voice call** — the same code, read aloud by Twilio over a voice call. A different
   carrier path, works on a landline, works where SMS is filtered. No human involved.
3. **The tap is never lost.** A worker who cannot sign in still taps; the tap queues on the
   device and flushes when a session exists, carrying its original timestamp. Combined
   with rolling sessions (item 4), a working cleaner does not meet this path at all.
   `lib/validate.js` currently tolerates 5 minutes of clock skew — **queued taps need a
   wider server-side window and that is an open item, called out in `SMS-AUTH.md`, not
   silently assumed.**
4. **Break-glass code** — the director, awake.

### 8. Twilio: plain REST, optional at boot, never in the request path

One `fetch` to `POST https://api.twilio.com/2010-04-01/Accounts/{AccountSid}/Messages.json`
with Basic auth and a form body. **No SDK.** Server dependencies stay exactly `pg` +
`@sentry/node` (decision-23, decision-16), unamended.

**Twilio Verify is rejected.** It would hand the OTP lifecycle to a vendor, cost more per
verification than the SMS it replaces, make the code un-hashable by us, and create a second
place where a worker exists. We already own this arithmetic.

Credentials are **optional at boot, exactly like `SENTRY_DSN`** — not in `REQUIRED_ENV`,
no parsing that can throw, no startup network call. Missing credential ⇒ `sms: disabled`,
one WARN line at boot, `/health` reports it, `/auth/sms/start` still returns the identical
200 and sends nothing, and the stated fallback is break-glass codes, i.e. **exactly the
system that runs today**. A missing Twilio key must never stop the API booting and must
never block a clock-in.

Credentials are an **API Key SID + Secret**, not the account Auth Token, because an API key
is revocable without rotating everything else. They live in the psst vault under tag
`server` and reach the VM only via `ops/sync-secrets.sh`. **The owner creates them in the
Twilio console. No agent has, or should ask for, Twilio console access.**

### 9. Cost is bounded structurally, not just by a limit

The strongest control is not a rate limit: **an SMS is only ever sent to a number already
in the `workers` table.** The destination set is bounded by the roster (4 rows today), so
this endpoint cannot be used for SMS pumping or IRSF toll fraud — the attack that actually
empties an owner's account, by making an OTP endpoint dial premium-rate numbers abroad.

On top of that: 3 sends/number/hour, 5/number/day, and a **process-wide daily ceiling**
(`SMS_DAILY_CAP`, default 200 ≈ €15/day absolute worst case). The counters live in a
**database table, not memory**, because `systemctl restart` must not reset a spend limit —
this is the one place where `lib/auth.js`'s in-memory limiter is not good enough, and the
reason is that the failure mode here is money rather than a guess.

### 10. Changing a worker's number revokes their sessions

If the phone number is the credential, editing it is a credential change. Admin edits
`phone_e164` ⇒ `phone_confirmed_at := NULL` **and** `destroyWorkerSessions(worker_id)`.
Silently re-pointing a live session at a new number would be the SIM-swap attack with the
admin panel as the accomplice.

### 11. The two already-enrolled workers are not disrupted

They keep working, with no forced re-authentication:

- Their `worker_sessions` rows are **not touched** by the migration, so nobody is logged
  out and no shift is at risk.
- `apple_sub` is preserved as an audit column.
- Migration 006 backfills `phone_e164` from `workers.phone` **only where normalisation
  succeeds unambiguously**, and never invents one. `phone_confirmed_at` is left NULL for
  everyone — a number typed by the director is not a number the worker proved.
- At next launch each of them confirms by SMS, once, and the nag clears.
- Anyone whose `phone` does not normalise appears in the admin panel as "Telefonnummer
  fehlt" and is fixed by typing it, not by a migration guess.

Exact worker and session counts must be read from production **read-only** immediately
before the migration runs; the queries are in `SMS-AUTH.md`. This record deliberately does
not assert a number it did not verify.

## Consequences

**Good**

- One front door, on every phone, with no vendor account and no email address.
- The director stops being the bottleneck: a worker onboards themselves from the number
  already in the roster.
- `workers.email` demoted to contact info. No more Hide My Email read-aloud dance.
- One trust boundary to keep correct instead of two, and a *smaller* one — deleting
  `lib/apple.js` removes a JWKS fetch and a nonce protocol from the sign-in path.
- The shared search space of decision-26 is gone. Attacks are per-worker again.
- The dependency budget is untouched: still `pg` + `@sentry/node`.

**Costs, honestly**

- **This is a downgrade in identity strength.** SIM swap and number recycling are real, and
  a carrier can hand a recycled Austrian mobile to a stranger. Accepted because the blast
  radius is small: a stolen worker session can file hours for one person. It cannot read
  payroll, cannot see other workers, cannot change rates. The admin panel is a separate
  cookie, a separate table and a separate password (decision-20). Deactivating a worker
  still kills every session on the next request.
- **Real money per authentication, from the owner's card.** Every control in item 9 exists
  because of this line. Twilio account-level spend triggers are a required part of setup,
  not an optional extra.
- **A dependency on carrier delivery.** Item 7 is the whole answer, and item 7 item 3 is an
  open item, not a solved one.
- **A 6-digit code hashed with SHA-256 is not preimage-resistant.** 10⁶ candidates is a
  fraction of a second offline. Hashing at rest defends a *stale* dump — the digest is
  worthless five minutes after it was written — and nothing else. Saying otherwise would be
  security theatre, so it is said here instead of implied by the word "hashed".
- **Three enrolment mechanisms exist during the transition** (Apple 410'd, break-glass,
  SMS). The transition must be short and must have a written end date, or decision-26's
  "two paths means two paths to keep correct" simply becomes three.
- **Apple review risk on Guideline 4.8** (item 5) is unverified and is the one thing that
  could force Sign in with Apple back.

**Supersedes**

- **decision-22** — superseded *in part*. Its security property (worker_id comes from the
  session, never the body) is **reaffirmed and unchanged**. Only its mechanism, Sign in
  with Apple, is replaced.
- **decision-26** — superseded *in part*. Admin-issued enrolment codes survive as
  break-glass, with their expiry, single use, revocation, hashing and rate limiting intact.
  Its *conclusion* — that identity must not require a particular vendor's phone — is what
  this record follows to its end.
- **decision-16 / decision-23** — untouched. No new dependency.

**Reversal condition.** If Apple review forces Guideline 4.8 compliance, or if SMS delivery
to Austrian mobiles proves unreliable in the pilot, the reversal is: un-410 `/auth/apple`,
restore `lib/apple.js` from history, and keep the phone number as a confirmed attribute
rather than the identity. Nothing in this design makes that hard, which is why
`apple_sub` is kept.
