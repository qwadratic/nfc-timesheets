# SMS auth — design and plan

**Status: design only. Nothing here is implemented. Production was not touched.**
Binding record: `backlog/decisions/decision-31`. Where this document and that record
disagree, the record wins.

Worker identity becomes **a phone number the worker proved they control**. Sign in with
Apple retires. Admin-issued enrolment codes stay, demoted to break-glass. `worker_sessions`
does not change.

```
today                              after
─────                              ─────
iPhone  → Apple ID → session       any phone → SMS OTP → session   (the only normal path)
Android → admin code → session     any phone → admin code → session (break-glass, nags)
                                                ↑ does NOT set phone_confirmed_at
```

---

## 0. What was read before writing this

`backlog/decisions/decision-22`, `decision-26`, `decision-23`, `decision-16`, `decision-24`,
`decision-29`; `server/lib/auth.js`, `lib/enrolment.js`, `lib/validate.js`, `lib/scrub.js`,
`routes/auth.js`, `server/instrument.mjs`, `server/server.js`; migrations `001`–`005`;
`ops/sync-secrets.sh`; `backlog/docs/BACKLOG-TRIAGE.md`, `ENROLMENT-CODES.md`.

Production was inspected only through documents. No connection was opened to it.

---

## 1. Phone numbers: normalisation at the trust boundary

New file `server/lib/phone.js`. One implementation, used by the admin save path and by
`/auth/sms/*`. Two implementations would be two chances for the panel and the auth route to
disagree about which worker a number names — and that disagreement is an account takeover,
not a display bug.

### The rules, in order

```
input  →  strip  [ space, NBSP, - , . , / , ( , ) ]      (people type all of these)
       →  "00…"        →  "+…"                          (European international prefix)
       →  starts "+"   →  keep as written
       →  starts "0"   →  "+43" + rest-without-the-0     (Austria: the common case)
       →  anything else                → null            (REJECTED, never guessed)
       →  test ^\+[1-9][0-9]{7,14}$    → else null       (E.164: 8..15 digits)
```

`null` is the only failure signal, exactly as `normaliseCode` does it. A caller must treat
"wrong shape" identically to "unknown number".

**Austria is the default region, not the only one.** `+421…` (SK), `+40…` (RO), `+49…` (DE),
`+36…` (HU) pass through untouched. Vienna's cleaning workforce is not exclusively Austrian
and assuming so would silently mangle a Slovak mobile into an Austrian one that does not
exist.

**A bare `664123456` is rejected.** With no `+`, no `00` and no leading `0` there is nothing
to distinguish an Austrian number missing its trunk prefix from a foreign one missing its
country code. Guessing would produce a valid-looking number belonging to someone else. The
admin gets a specific error and retypes it; that is cheap and safe.

### Test table (goes in `check-api.js`, table-driven)

| input | → | why |
|---|---|---|
| `0664 123 45 67` | `+436641234567` | the common case, as the director types it |
| `0664/1234567` | `+436641234567` | the other way the director types it |
| `+43 664 1234567` | `+436641234567` | already international |
| `0043 664 1234567` | `+436641234567` | `00` is the European prefix |
| `+421 903 123 456` | `+421903123456` | Slovak mobile, untouched |
| `01 4000 0` | `+43140000` | Vienna landline. Shape-valid, not a mobile — §1 ceiling |
| `664123456` | `null` | ambiguous. Rejected, not guessed |
| `+0664…` | `null` | `[1-9]` after `+` |
| `+43664` | `null` | too short (< 8 digits) |
| `+4366412345678901` | `null` | too long (> 15 digits) |
| `0664 ABC 4567` | `null` | letters |
| `"" / null / 200-char string` | `null` | length-capped before the regex, like `normaliseCode` |

> **This table was executed, not asserted.** A 6-line reference implementation of the rules
> above passes all 14 rows, and the mutation *drop the `00` rule* turns the `0043…` row RED
> (`+430436641234567`, not `+436641234567`). The implementation task must reproduce both.

**ponytail:** this is ~20 lines of regex, not libphonenumber. **Ceiling:** it does not know
that `+43 664` is a mobile and `+43 1` is a Vienna landline, so it will accept a shape-valid
number that no SIM answers. **Upgrade path:** Twilio Lookup (`GET /v2/PhoneNumbers/{e164}`,
one fetch, no dependency, ~€0.005) called **once, on the admin save path only, never on the
OTP path**, with the result cached in a column. Not in v1: it is a per-lookup charge to solve
a problem the confirmation step already solves — an unconfirmable number is visible as
`phone_confirmed_at IS NULL`.

---

## 2. Schema — migration `006_phone_identity.sql`

Additive only, over a live box. Every added column is NULLable with no default.

```sql
ALTER TABLE workers
  ADD COLUMN phone_e164         TEXT UNIQUE
    CHECK (phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  ADD COLUMN phone_confirmed_at TIMESTAMPTZ;
```

`UNIQUE` because the number is now the identity: two workers on one number makes "who is
this" unanswerable at the exact moment it matters. NULLs are not unique in Postgres, so
every worker without a number coexists fine.

`workers.phone` (free text, migration 003) **stays**. It is what the director recognises on
screen and it is the audit trail of what was typed. `phone_e164` is derived from it.

```sql
CREATE TABLE sms_challenges (
  phone_e164    TEXT PRIMARY KEY,
  worker_id     BIGINT NOT NULL REFERENCES workers(id) ON DELETE CASCADE,
  code_hash     TEXT NOT NULL,
  expires_at    TIMESTAMPTZ NOT NULL,
  attempts      SMALLINT NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX sms_challenges_expires_at_idx ON sms_challenges (expires_at);
```

**Keyed on the phone number, not on the hash.** This is the single most important
difference from `004_worker_enrolment_codes.sql`, and it is what makes six digits safe:

- Enrolment codes are looked up **by digest**, so every live code is a valid answer to one
  guess and the search space is shared across the whole fleet (`lib/enrolment.js` does that
  arithmetic).
- An OTP is looked up **by the number the caller typed**. The caller must name their target.
  A guess is worth 1-in-10⁶ against one worker, not n-in-2⁴⁰ against all of them.

It also removes a collision problem that would otherwise be real: at 10⁶ codes, two workers
holding `123456` simultaneously is ordinary, and a `UNIQUE` digest would either reject a
legitimate send or make redemption ambiguous.

`PRIMARY KEY (phone_e164)` gives **one live challenge per number**; a resend is an `UPDATE`
that replaces the code and resets `attempts` to 0. Same "one active per subject, no separate
table" reasoning decision-26 used.

`code_hash` is `hashToken("<phone_e164>:<code>")` — the existing SHA-256 hex helper in
`lib/auth.js`, salted with the number so a digest cannot be lifted from one row into another.

```sql
-- The COST LEDGER. Not a log; a spend limit.
CREATE TABLE sms_sends (
  id          BIGSERIAL PRIMARY KEY,
  phone_e164  TEXT NOT NULL,
  channel     TEXT NOT NULL CHECK (channel IN ('sms','voice')),
  sent_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  provider_sid TEXT,
  ok          BOOLEAN NOT NULL
);
CREATE INDEX sms_sends_phone_idx ON sms_sends (phone_e164, sent_at DESC);
CREATE INDEX sms_sends_sent_idx  ON sms_sends (sent_at DESC);
```

**Why a table and not the in-memory counters of `lib/auth.js`.** Those counters carry an
honest `ponytail:` note that they reset on restart. For a guess limit that is an acceptable
ceiling. For a **spend** limit it is not: `systemctl restart nfc-api` must not refill the
owner's SMS budget, and `Restart=always` means a crash loop would refill it repeatedly.
Money is the failure mode here, so the counter goes where a restart cannot reach it.

Retention: a phone number is PII, so `sms_sends` rows older than **30 days** are swept
opportunistically on insert (same idiom as the `sessions` sweep in `createSession`). 30 days
covers "why was the bill high last week" and nothing longer.

### Backfill, and what it deliberately does NOT do

```sql
-- Only where lib/phone.js normalisation is unambiguous. Applied by a one-shot
-- script, not by SQL: the normaliser is the single source of the rules (§1).
UPDATE workers SET phone_e164 = $normalised WHERE id = $id;
```

`phone_confirmed_at` is left **NULL for every existing row, without exception**. A number
the director typed is not a number the worker proved. Backfilling a confirmation would
delete the entire point of the feature on its first day.

---

## 3. The OTP, and the arithmetic

| parameter | value | why |
|---|---|---|
| alphabet | `0-9` | iOS `.oneTimeCode` autofill and Android autofill both key on digits |
| length | 6 | convention; usability, **not** the security property |
| TTL | 5 min | it arrives in seconds and the worker is holding the phone |
| attempts | **3** per challenge | autofilled, so a typo is rare; 3 is generous |
| single use | yes | cleared by the same `UPDATE` that mints the session |
| at rest | `hashToken("<e164>:<code>")` | SHA-256 hex, the existing helper |
| sends | 3/number/hour, 5/number/day | the money bound |
| global | `SMS_DAILY_CAP`, default 200/day | the other money bound |

Generation: `randomInt(0, 1_000_000)` from `node:crypto`, zero-padded to 6. `randomInt` is
rejection-sampled by Node, so there is no modulo bias — the same property `newEnrolmentCode`
gets from slicing exactly 5 bits at a time.

### Brute force, worst case, spelled out

The attacker must know a worker's phone number (they are not secret — assume they do) and
must **cause** each challenge to exist, which means causing an SMS to that worker's handset.

```
space                       10^6
attempts per challenge      3
p(hit one challenge)        3 / 10^6                    = 3.0e-6

live challenges an attacker can force, worst case:
  per number                5 / day            (send cap)
  fleet of 20 workers       100 / day
p(any hit in a day)         100 * 3.0e-6                = 3.0e-4    ~ 1 in 3_300 days
p(any hit in a year)        365 * 3.0e-4                = 0.11      -- see below
sustained to 50%            ~2_310 days                 ~ 6.3 years

and every one of those days costs the ATTACKER nothing but costs the OWNER:
  100 SMS/day * ~EUR 0.08                               ~ EUR 8/day
  and rings 20 cleaners' phones 5 times each, every day, for years
```

The `0.11` per year is the number to argue with, and the answer is that the attack is not
quiet: it is a permanent, visible SMS flood against real handsets with a matching Twilio
bill, detected on day one by anyone reading either. The **global daily ceiling** is what
converts "expensive and loud" into "bounded": at `SMS_DAILY_CAP = 200`, the whole system
cannot exceed 200 challenges/day no matter how many numbers are attacked.

Compare the shape of the enrolment-code figures (`lib/enrolment.js`): there, 43 200
guesses/day were reachable by one attacker with no cost and no side effects, and 40 bits of
entropy were doing the work. Here, 300 guesses/day is the ceiling and it costs €8/day and a
phone ringing. **Different mechanism, different defence.**

**Redo this block if** the code length, TTL, attempt limit, either send cap, or the fleet
size changes. Same rule, same reason, as the block in `lib/enrolment.js`.

Note where the binding constraint switches: at 5 sends/number/day, the global cap of 200 is
reached at **40 workers**. Beyond that the fleet figure stops growing and the ceiling is
`200 * 3e-6 = 6.0e-4/day = 0.22/year` — unless the cap is raised with the roster, in which
case the code goes to 7 digits or the per-number daily cap drops to 3.

---

## 4. Endpoints

Both sit behind `auth: "app"` (`X-App-Key`), exactly like `/auth/apple` and `/auth/code`.
That is a coarse "this is our app" gate and never identity — `lib/auth.js` says so and it
stays true.

### `POST /auth/sms/start  {phone}`

```
200 {"sent": true, "expires_in": 300}     ALWAYS
429 {"error": "too_many_attempts"}        rate limit only
```

**Always 200.** Unknown number, deactivated worker, malformed input, Twilio unconfigured,
daily budget spent — same body, same bytes. Any other answer makes this a worker directory:
"is +43 664 X a cleaner at this company" is a question a stranger must not be able to ask.

Order of work:

```
1  checkSmsGlobalRate()                 process-wide, before anything
2  checkLoginRate(`sms:${ip}`)          existing limiter, own bucket (like routes/portal.js)
3  e164 = normalisePhone(body.phone)    null => compose the 200 and return, send nothing
4  worker = SELECT ... WHERE phone_e164 = $1 AND active
                                        null => compose the 200 and return, send nothing
5  send budget check against sms_sends  over  => compose the 200, return, log to Sentry
6  code = 6 digits; UPSERT sms_challenges (attempts reset to 0)
7  RESPOND 200
8  dispatch the Twilio POST on a DETACHED promise, insert into sms_sends when it settles
```

**Step 7 before step 8, deliberately.** Two reasons: a slow Twilio must never delay the
worker's screen, and awaiting a ~200 ms HTTP call only for known numbers would make
known/unknown distinguishable by stopwatch — reintroducing the oracle the constant response
body just removed.

Fire-and-forget hides failures, so the detached promise has `AbortSignal.timeout(5000)`, a
`catch` that reports to Sentry, and writes `sms_sends.ok = false`. It never rejects into the
process. (Delivery *receipts* need Twilio's `StatusCallback` webhook — deliberately out of
scope for v1, listed in §11.)

### `POST /auth/sms/verify  {phone, code}`

```
200 {"worker":{"id","name"},"expires_at":"..."}  + Set-Cookie: ts_worker
401 {"error":"invalid_code"}                     EVERYTHING else
429 {"error":"too_many_attempts"}
```

**One failure response, byte for byte** — the rule `/auth/code` already follows. Unknown
number, no challenge, wrong code, expired, already redeemed, attempts exhausted, worker
deactivated, malformed input: identical. "Merely expired" in particular must not be
distinguishable; it would confirm the number belongs to a worker and that a code was really
sent.

The redemption is **one statement, decided by the database**, the same idiom and for the same
race reason as `codeAuth`:

```sql
DELETE FROM sms_challenges c
 USING workers w
 WHERE c.phone_e164 = $1
   AND c.code_hash  = $2
   AND c.expires_at > now()
   AND c.attempts   < 3
   AND w.id = c.worker_id
   AND w.active
RETURNING c.worker_id, w.name;
```

Under READ COMMITTED the second of two racing verifications finds no row and mints nothing.
An `if (alreadyUsed)` in this process could not do that — both racers would read "unused".

On a miss: `UPDATE sms_challenges SET attempts = attempts + 1 WHERE phone_e164 = $1` and
`fail(401, "invalid_code")`. The counter is **in the row**, so it survives a restart and
cannot be evaded by rotating source IPs — which is precisely the weakness the `ponytail:`
note on the in-memory limiter admits to.

Exactly one `safeEqual` runs on every path, hit or miss, against per-process random decoys —
reuse `DECOY_STORED` / `DECOY_PRESENTED` from `lib/enrolment.js` rather than minting a second
pair.

On success: `phone_confirmed_at := now()`, `last_sign_in_at := now()`, then
`createWorkerSession(worker_id)`. Unchanged function, unchanged table, unchanged cookie.

### `POST /auth/sms/voice  {phone}`

Same code, same challenge row, read aloud by Twilio over a voice call
(`POST /Accounts/{sid}/Calls.json` with a TwiML `<Say>` URL). Counts against the same send
budget with `channel = 'voice'`. Available only after at least one SMS send for that
challenge, so it cannot be the first thing an attacker reaches for. Response: identical
always-200.

### `POST /auth/apple`

Returns `410 {"error":"gone"}` for one release, then the route and `lib/apple.js` are
deleted. `workers.apple_sub` stays as an audit column.

### `POST /auth/code`

Unchanged mechanism, one behavioural change: it **does not set `phone_confirmed_at`**.

### `GET /auth/session`

Gains `"phone_confirmed": boolean` so the app knows whether to nag. Nothing else. It still
returns no email and no `apple_sub` — what is not returned cannot be logged.

---

## 5. Sessions

`worker_sessions` is **not modified**. Same table, same `ts_worker` cookie, same 90-day TTL,
same `requireWorkerSession` with its `AND w.active` re-read on every request.
**`worker_id` comes from the session and never from a request body** — decision-22's actual
security property, reaffirmed.

Two additions, both in `lib/auth.js`:

**Rolling expiry.** In `requireWorkerSession`, if `expires_at` is more than 7 days from its
maximum, push it back out to now + 90 days. An actively working cleaner then never
re-authenticates, which removes "the SMS did not arrive" from the doorstep at 06:00 for
everyone except a genuinely new hire — who is enrolling in an office, not in a stairwell.
One `UPDATE`, at most once a week per worker.

**Revocation on number change.** Admin changes `phone_e164` ⇒ `phone_confirmed_at := NULL`
**and** `destroyWorkerSessions(worker_id)`, in one transaction. If the number is the
credential, editing it is a credential change; leaving the old session live would make the
admin panel an accomplice to a SIM swap.

---

## 6. Cost and abuse — how the owner's money is bounded

**The structural bound comes first, because it is the one that matters.**

> An SMS is only ever sent to a number that is already a row in `workers`.

The destination set is the roster — 4 numbers today, ~20 at pilot scale. An attacker cannot
make this server text an arbitrary number, so it cannot be used for **SMS pumping / IRSF
toll fraud**: the attack where an OTP endpoint is driven to dial premium-rate ranges abroad
and someone collects the termination fee. That attack is what actually empties an account,
and it is closed by construction rather than by a threshold.

On top of that, four thresholds:

| bound | value | enforced |
|---|---|---|
| per number, hourly | 3 sends | `sms_sends`, SQL count |
| per number, daily | 5 sends | `sms_sends`, SQL count |
| whole system, daily | `SMS_DAILY_CAP` = 200 | `sms_sends`, SQL count |
| per IP | existing limiter, bucket `sms:${ip}` | memory (see ceiling below) |

```
worst case at the ceiling   200 SMS/day * ~EUR 0.08  ~ EUR 16/day  ~ EUR 480/month
realistic                   20 workers enrol once, plus a handful of re-auths
                            < 50 SMS/month           ~ EUR 4/month
```

The €0.08 is an estimate for Austrian mobile termination and **must be confirmed by the
owner on Twilio's pricing page before `SMS_DAILY_CAP` is chosen** — it is the multiplier on
every figure above.

Three more controls that live in the Twilio console, not in this repo, and are part of setup:

1. **Geo Permissions**: enable only the countries the roster actually contains (AT, plus
   whatever the current workforce needs). Everything else disabled. This is a second,
   independent barrier against toll fraud.
2. **A billing alert / spend trigger** at a monthly figure the owner picks. Twilio can email
   and can pause the sub-account.
3. **Keep the account on a low prepaid balance with auto-recharge off**, so the absolute
   worst case is bounded by the balance and not by the card.

When the daily cap is hit: sending stops, `/auth/sms/start` still answers the identical 200,
one Sentry event is raised, and the worker sees the standard "no code arrived" screen with
the break-glass instruction. **Hitting a spend cap must never look like a broken endpoint to
an attacker, and must never be silent to the owner.**

---

## 7. Delivery failure is a normal path

No signal, a wrong number, a carrier holding a message for four minutes, a full inbox, a
prepaid SIM out of credit — these are the ordinary Tuesday, not the exception. The design
answer, in order, with only the last one needing the director:

**What the worker sees**

```
┌──────────────────────────────────────┐
│  Code an  +43 664 ••• ••67  gesendet │  ← masked read-back: last 2 digits only.
│                                      │    A wrong number is caught HERE, before
│  [ _ ] [ _ ] [ _ ] [ _ ] [ _ ] [ _ ] │    anyone waits five minutes for nothing.
│                                      │
│  Kein Code angekommen?               │
│  Erneut senden in 0:47               │  ← 60 s, then 120 s. 3 sends max.
└──────────────────────────────────────┘
```

Masking shows enough to spot a transposed digit and not enough to be a directory lookup for
someone holding a stolen handset.

**After the third send, the screen changes rather than repeating itself:**

```
│  Anruf statt SMS                     │  ← Twilio reads the same code aloud.
│  [ Code vorlesen lassen ]            │    Different carrier path. Works on a
│                                      │    landline. Nobody has to be awake.
│                                      │
│  Ihre Arbeitszeit wird trotzdem      │  ← THE IMPORTANT LINE. A worker who
│  erfasst. Sie können jetzt stempeln  │    cannot sign in must not lose a shift.
│  und sich später anmelden.           │
│                                      │
│  Immer noch nichts? Büro anrufen:    │  ← the director, last.
│  <number from ops/branding.json>     │
```

**The four fallbacks, ranked**

1. **Wait and resend.** Carrier delay is the single most common cause and time fixes it.
   60 s / 120 s backoff, 3 sends.
2. **Voice call.** Same code, different transport. No human involved. Covers SMS filtering,
   a landline, and a handset whose SMS app is broken.
3. **The tap queues locally.** The device records the tap with its real timestamp and
   flushes when a session exists. Combined with rolling sessions (§5), a regularly working
   cleaner never reaches this path — only a brand-new hire does, and they are enrolling in
   an office.
   > **OPEN ITEM, not a solved one.** `lib/validate.js` tolerates 5 minutes of clock skew.
   > A tap queued for three hours would be rejected by the server today. Widening that
   > window for queued taps is a **security-relevant change to a money-producing endpoint**
   > (`start_time` determines pay) and needs its own task and probably its own decision:
   > the client would be asserting a past time. Sketch of the safe shape — accept a client
   > timestamp only when it is (a) not in the future beyond the existing skew, (b) not more
   > than 24 h old, (c) carried by the existing `client_uuid` idempotency key, and (d)
   > flagged on the shift row as client-asserted so the payroll screen can show it. Do not
   > implement it as part of this work.
4. **Break-glass enrolment code.** The director issues one, exactly as decision-26 describes.
   It signs the phone in but leaves `phone_confirmed_at` NULL, so the app keeps asking for
   SMS confirmation at every launch until it is done.

---

## 8. Twilio

### Plain REST, no SDK

```
POST https://api.twilio.com/2010-04-01/Accounts/{TWILIO_ACCOUNT_SID}/Messages.json
Authorization: Basic base64(TWILIO_API_KEY_SID + ":" + TWILIO_API_KEY_SECRET)
Content-Type: application/x-www-form-urlencoded

MessagingServiceSid={TWILIO_MESSAGING_SERVICE_SID}&To=%2B436641234567&Body=...
```

One `fetch`, `AbortSignal.timeout(5000)`. Server dependencies stay **`pg` + `@sentry/node`
and nothing else** (decision-23). The Twilio SDK would add ~20 packages plus its own
retry/telemetry behaviour to a process that already has a tracer, for an HTTP POST with
Basic auth.

**API key, not the account Auth Token.** `SKxxxx` + secret authenticates against the same
Account SID URL and can be revoked in the console without rotating the credential that
controls everything else in the account.

**Twilio Verify is rejected.** It would generate, store, expire and check the code for us —
attractive, and wrong here: it moves the trust boundary to a vendor, costs more per
verification than the SMS it replaces, makes the code un-hashable by us, and creates a
second place where a worker exists. We already own this arithmetic (§3).

### Optional at boot, like `SENTRY_DSN`

```js
// server/lib/sms.js
const SMS_CONFIGURED = Boolean(
  process.env.TWILIO_ACCOUNT_SID &&
  process.env.TWILIO_API_KEY_SID &&
  process.env.TWILIO_API_KEY_SECRET &&
  process.env.TWILIO_MESSAGING_SERVICE_SID,
);
```

- **Not** in `server.js`'s `REQUIRED_ENV`. Not in `sync-secrets.sh`'s required list.
- No parsing, no I/O, no throw at module load — `instrument.mjs` explains why
  (`Restart=always` + a throwing module = a crash loop that takes the API down for a
  non-essential feature).
- Unset ⇒ one WARN at boot: `sms: disabled (TWILIO_* unset) — break-glass codes only`.
- `/health` reports `"sms": "disabled"`.
- `/auth/sms/start` still returns the byte-identical 200 and sends nothing.
- **Stated fallback: admin-issued break-glass codes — i.e. exactly the system that runs in
  production today.** A missing Twilio credential degrades to the status quo, never to a
  broken API and never to a blocked clock-in.

**Dev seam.** When `!SMS_CONFIGURED && process.env.NODE_ENV !== "production"`, the code is
printed to stdout so `check-api.js` and the `nfc_demo` rig can drive the flow. The
`NODE_ENV` guard is load-bearing and gets a mutation test (§10).

### The message body

```
123456 ist Ihr Anmeldecode für NFC TimeSheets.

@timesheets.exe.xyz #123456
```

The `@domain #code` line is Apple's domain-bound-code format: iOS offers the code as a
keyboard suggestion and binds it to the app, killing the most common OTP phishing route.

> **It requires `webcredentials` in two places that do not have it today**, and this is a
> decision-24 change, not an incidental edit:
> - the AASA needs a `webcredentials: { apps: [<appID>] }` section — `ops/gen-wellknown.mjs`
>   renders `applinks` only, so it must learn to render it, from `ops/branding.json`, with
>   the append-only appID rule and `server/wellknown/verify.sh` still green;
> - `NFCTimeSheets.entitlements` needs `webcredentials:timesheets.exe.xyz` as a **checked
>   literal**, beside the existing `applinks:` line. That file is not `project.pbxproj` and
>   is safe to edit; **`project.pbxproj` must not be touched.**
>
> Without it the code is still readable and still typable. Autofill is a convenience, and it
> must not become a prerequisite.

The German text is the default (decision-8), with an English variant selected from the
worker's device locale. Both strings live in the normal message catalogues.

**Android autofill** reads a 6-digit code from the notification heuristically on current
Android and needs nothing from us. Google's `SmsRetriever` would need an 11-character app
hash appended to the body, which cannot coexist with Apple's `@domain #code` suffix in one
message. **ponytail:** ship one body with the Apple suffix. **Ceiling:** Android users may
have to copy the code manually. **Upgrade path:** a `platform` field on `/auth/sms/start`
picking the suffix — client-controlled but harmless, since it only chooses trailing text.

### Sender

A Messaging Service (`MG…`) rather than a bare `From`, so the sender can be changed without
a deploy. Sender identity for Austria is the owner's choice in the console: an alphanumeric
sender ID (`TimeSheets`) is more recognisable but **cannot receive replies**, so STOP/HELP
must be handled by the office rather than by the carrier. A2P 10DLC registration is a US
requirement and does not apply.

---

## 9. Admin panel and iOS/Android parity

**Both platforms get the identical flow.** One screen, one endpoint pair, one set of
strings. No platform branches beyond the SMS body suffix.

```
launch → GET /auth/session
   401                      → phone entry → 6-digit entry → session
   200, phone_confirmed=false → banner, dismissible per launch, not per session
   200, phone_confirmed=true  → straight to the shift screen
```

**Admin panel (`web/`), Mitarbeiter screen:**

- Phone number becomes **required**, not optional. `optionalPhone` in `lib/validate.js`
  stays for `contacts.phone`; workers get `requiredE164`.
- On save the panel shows the normalised form back for confirmation: typed `0664 123 45 67`
  → *"Wird gespeichert als **+43 664 123 45 67**"*. The director approves the interpretation
  rather than discovering it later.
- A status column: `Bestätigt am 12.08.2026` / `Nicht bestätigt` / `Telefonnummer fehlt`.
- Changing the number shows a **confirmation dialog** naming both consequences — the
  worker is signed out on every device, and must confirm the new number.
- The enrolment-code block is relabelled **Notfall-Zugang** with one line of explanation:
  it gets the worker in, it does **not** confirm their number, and the app will keep asking.
- The email field loses its "this is how they sign in" hint entirely. It is contact info.

**i18n:** every string above lands in `web/messages/de.json` and `en.json` with **exact key
parity**, German as the real text (decision-8). No bare JSX literals. New keys sit under the
existing `workers.*` namespace next to `codeStandingNote` and friends, and the whole
`codeExplain`/`codeStandingNote` family is rewritten — it currently says the email address
is how an iPhone signs in, which stops being true.

**decision-29 (phone-sized admin panel):** the workers table already becomes labelled cards
below 768 px via `.data-table` + `ResponsiveTableLabels.tsx`. Two new columns must be
verified there, not assumed — a label that "exists" but is wrong has bitten this project
before.

**Accessibility:** the 6-digit entry is a single `<input inputmode="numeric"
autocomplete="one-time-code">`, not six boxes. Six boxes break screen readers, break paste,
and break autofill. The resend countdown is announced via `aria-live="polite"`; the error is
`role="alert"` and is the same one sentence for every failure, matching the endpoint.

---

## 10. Verification — every check must be provable RED

> A check whose negative case cannot fail is not a check. Each item below names its
> mutation: the change that must make it fail. Anything that cannot be shown RED does not
> count as done.

| # | Check | Mutation that must turn it RED |
|---|---|---|
| 1 | `normalisePhone` table (§1), all 12 rows | drop the `00` rule → the `0043…` row fails |
| 2 | `/auth/sms/verify` failure bodies are **byte-identical** across wrong / expired / used / exhausted / unknown-number / malformed. Assert `JSON.stringify(body)` **and** the status are equal across all six. | make the expired branch return `"expired"` → RED |
| 3 | **No SMS to a non-worker number.** Inject a fake sender; call `start` with an unknown number; assert **zero** sends. | remove the `WHERE phone_e164 = $1 AND active` lookup → the sink records a send → RED |
| 4 | **`start` response is identical for known and unknown numbers**, body and status. | return `{"sent":false}` for unknown → RED |
| 5 | **Boots with no Twilio vars.** `assertEnv({DATABASE_URL, APP_KEY, PORT})` passes; `node --import ./instrument.mjs -e "0"` exits 0. | add `TWILIO_ACCOUNT_SID` to `REQUIRED_ENV` → RED |
| 6 | **Daily cap actually stops sends.** Insert `SMS_DAILY_CAP` rows into `sms_sends` (nfc_demo), call `start`, assert zero sends **and** an unchanged 200. | remove the cap check → the sink records a send → RED |
| 7 | **Attempt burn survives a process restart.** 3 wrong codes, drop and recreate the module state, 4th attempt still 401 and no session. | move `attempts` into an in-memory Map → RED |
| 8 | **Single use under concurrency.** Fire two correct verifications in parallel; exactly one 200, exactly one session row. | replace the `DELETE … RETURNING` with select-then-delete → both mint → RED |
| 9 | **Dev code-print never fires in production.** `NODE_ENV=production` + no Twilio vars ⇒ nothing matching `/\d{6}/` on stdout. | remove the `NODE_ENV` guard → RED |
| 10 | **The code never leaves the process.** Drive a full flow with the scrub hooks capturing; grep every access-log line, Sentry event and breadcrumb for the code and the E.164 number. | remove the `phone` key from `SECRET_KEY_RE` → RED |
| 11 | **Changing `phone_e164` revokes sessions.** Sign in, change the number via the admin route, assert `worker_sessions` for that worker is empty and the cookie 401s. | drop the `destroyWorkerSessions` call → RED |
| 12 | **`phone_confirmed_at` stays NULL after a break-glass redemption.** | set it in `codeAuth` → RED |
| 13 | **Rolling expiry.** A session used at day 80 has `expires_at` pushed out; a session used at day 1 does **not** get a write. | always roll → the day-1 case fails |
| 14 | **de/en key parity** for all new strings, both directions. | add a key to `en.json` only → RED |

Items 3, 4, 6 and 9 need a **send sink**: `lib/sms.js` exports its transport, and
`check-api.js` swaps in a recorder. Do not test by watching for a real SMS.

`lib/scrub.js` needs `phone` and `phone_e164` added to `SECRET_KEY_RE` **anchored** — an
unanchored `/phone/` is fine here, but confirm it does not eat a field that makes a 4xx
diagnosable, which is the mistake the `^code$` comment in that file already documents.

All of this runs against **`nfc_demo`**, whose guards (`demo/check-guards.sh`) refuse any
other database. Production is not written to at any point in this work.

---

## 11. What the owner must do — exact commands

### Step A — in the Twilio console. Only the owner can do this.

**No agent has or should ask for Twilio console access.** These credentials are created by
the owner, in a browser, and pasted into the local vault by the owner.

1. Create (or log in to) the Twilio account and buy/verify a sender for Austria — either an
   Austrian long code or a registered alphanumeric sender ID.
2. **Messaging → Services → create a Messaging Service**, add the sender to its pool.
   Copy its SID → starts `MG`.
3. **Account → API keys & tokens → Create API key**, type **Standard**.
   Copy the **SID** (`SK…`) and the **Secret** — the secret is shown **once**.
4. Copy the **Account SID** (`AC…`) from the console dashboard.
5. **Messaging → Settings → Geo Permissions**: enable **only** the countries the roster
   needs (Austria, plus any other country a current worker's mobile is registered in).
   Disable everything else. This is a real anti-toll-fraud control, not paperwork.
6. **Billing → set a spend trigger / alert** at a monthly figure you choose.
7. Note the **per-SMS price to Austrian mobiles** from Twilio's pricing page — it is the
   multiplier on every cost figure in §6, and it sets `SMS_DAILY_CAP`.

### Step B — paste into the psst vault. Exactly these commands.

```sh
cd /Users/gerhardgustav/Desktop/ai-automations/hoiv/cleaning-timesheets

psst set TWILIO_ACCOUNT_SID           --tag server
psst set TWILIO_API_KEY_SID           --tag server
psst set TWILIO_API_KEY_SECRET        --tag server
psst set TWILIO_MESSAGING_SERVICE_SID --tag server
psst set SMS_DAILY_CAP 200            --tag server
```

**`psst set NAME` with no value prompts for it.** Use it exactly as written: the value then
never enters shell history, never appears in `ps`, and never lands in a scrollback that gets
pasted into a chat. `SMS_DAILY_CAP` is the one exception — it is a number, not a secret, and
it is in the vault only because `ops/sync-secrets.sh` rewrites `/etc/nfc/env` wholesale from
the vault, so the vault is the only route into the service environment.

**The four values, and where each comes from:**

| name | shape | Twilio console location |
|---|---|---|
| `TWILIO_ACCOUNT_SID` | `AC` + 32 hex | Dashboard → Account Info |
| `TWILIO_API_KEY_SID` | `SK` + 32 hex | Account → API keys & tokens |
| `TWILIO_API_KEY_SECRET` | 32-char secret | shown **once**, at key creation |
| `TWILIO_MESSAGING_SERVICE_SID` | `MG` + 32 hex | Messaging → Services |

**Do not put the account Auth Token in the vault.** It is the master credential for the whole
Twilio account; the API key above exists so it does not have to travel to an
internet-facing VM.

### Step C — verify, then push.

```sh
psst list --tag server            # names only. Confirm all five appear.
sh ops/sync-secrets.sh --dry-run  # prints NAMES that would be written. Never values.
sh ops/sync-secrets.sh            # writes /etc/nfc/env, restarts nfc-api, checks /health
```

`sync-secrets.sh` reads names from `psst list --tag server` and fetches values one at a
time — `psst export --tag server` silently ignores `--tag` and would push the Play upload-key
password to the VM. Use the script, never `psst export`.

**Do this only after the code is deployed.** Adding the credentials to a server that has no
`lib/sms.js` is harmless (the values are simply unread), but adding them and *not* deploying
gives a false sense that SMS is live.

---

## 12. Before the migration runs — read-only production checks

Run these, read the output, and only then run 006. **`SELECT` only.**

```sql
-- 1. How many workers, and how many hold a live session (the "already enrolled" set)?
SELECT count(*) FILTER (WHERE active)                         AS active_workers,
       count(*) FILTER (WHERE apple_sub IS NOT NULL)          AS apple_enrolled,
       count(*) FILTER (WHERE enrolment_code_redeemed_at IS NOT NULL) AS code_enrolled
  FROM workers;

SELECT count(DISTINCT worker_id) AS workers_with_live_session
  FROM worker_sessions WHERE expires_at > now();

-- 2. Which phone numbers will normalise, and which will not?
--    Read the raw values and run them through lib/phone.js locally. Do NOT normalise in SQL:
--    the normaliser is the single source of the rules (§1) and a second copy would drift.
SELECT id, active, phone FROM workers ORDER BY id;

-- 3. Would UNIQUE(phone_e164) be violated? Two workers sharing a number blocks the migration.
--    Answer this from the output of query 2, in the normaliser, before touching the DB.
```

If any active worker's `phone` does not normalise, **fix it in the admin panel first**. The
migration must not guess and must not be run against a roster it will half-populate.

---

## 13. Implementation order

Each step is independently deployable and leaves the system working.

| # | Step | Effort | Note |
|---|---|---|---|
| 1 | `lib/phone.js` + its table test | low | pure function, no schema, no risk |
| 2 | Migration 006 + the read-only pre-checks (§12) | low | additive, all-NULLable |
| 3 | Admin panel: required phone, normalised read-back, status column, revoke-on-change | med | i18n parity, decision-29 card check |
| 4 | Backfill script (normalise only, never confirm) | low | run once, output reviewed by a human |
| 5 | `lib/sms.js` — transport, `SMS_CONFIGURED`, budget checks, send sink | med | the dependency-budget and boot-optional gates live here |
| 6 | `/auth/sms/start` + `/verify` + checks 2,3,4,6,7,8 | **high** | the trust boundary; the mutation tests are the deliverable, not an extra |
| 7 | iOS + Android sign-in screens, identical flow | med | one screen each, plus the nag banner |
| 8 | `webcredentials` in branding.json / gen-wellknown / entitlement | low | decision-24 gates must stay green; **never** `project.pbxproj` |
| 9 | Twilio credentials into psst, deploy, one real end-to-end SMS | low | owner-blocked (§11) |
| 10 | `/auth/apple` → 410; delete `lib/apple.js` one release later | low | do **not** bundle with step 6 |
| 11 | Voice-call fallback | low | one more Twilio endpoint, same challenge row |

Steps 1–5 touch no live auth path. Step 6 is where the care goes.

---

## 14. Open items — named, not hidden

1. **Guideline 4.8.** The claim that a first-party phone login does not trigger the Sign in
   with Apple requirement is **unverified**. Read the current guideline text and record the
   quote before the next submission. It is the one thing that could reverse decision-31 §5.
2. **Queued-tap clock skew** (§7 item 3). Currently 5 minutes; a queued tap needs more. It is
   a change to a money-producing field and needs its own task and probably its own decision.
   Not part of this work.
3. **Delivery receipts.** Twilio's `StatusCallback` webhook would turn "we dispatched it"
   into "the handset got it", which is what the admin panel really wants to show. Deferred:
   it is a new public endpoint with its own signature-verification trust boundary.
4. **Per-SMS price to Austria.** Owner-verified figure needed before `SMS_DAILY_CAP` is
   final (§6).
5. **Transition end date.** Three enrolment mechanisms coexist between step 6 and step 10.
   That window needs a date written on it, or decision-26's "two paths to keep correct"
   quietly becomes three.
6. **Android SMS Retriever.** Shipping one message body with the Apple suffix; Android users
   may copy manually. Revisit only if someone complains.
