//
//  API.swift
//  NFCTimeSheets
//
//  The wire contract, and nothing else. Foundation only - no SwiftUI, no SwiftData, no
//  AuthenticationServices - so checks/tag-link-check.swift can compile and exercise it
//  outside Xcode. (Branding.swift and TagLink.swift are Foundation-only too and must be
//  concatenated ahead of this file; see the header of that check.)
//
//  Every field name below is snake_case and spelled out in an explicit CodingKeys. The
//  previous version of this file used camelCase names of its own invention ("worker",
//  "tagUID", "manualFinish") that the server had never heard of; every POST came back
//  400 and was swallowed by a bare `catch {}`, so shifts piled up on the phone forever
//  with a clean-looking UI. Explicit keys are here to be diffed against server/routes/
//  by eye. Do not replace them with .convertToSnakeCase.
//

import Foundation

enum API {
    // Derived from Branding.apiHost, and ONLY Branding.apiHost (decision-40, TASK-188).
    // TagLink.host (the tag host) must never appear here: it is a different, PERMANENT
    // machine, written on physical cards, and this app already shipped one bug where the
    // two were conflated - it worked only because they happened to hold the same value,
    // until the tag host was corrected and would have taken every API call down with it.
    // The fallback on the right is unreachable in practice - Branding.apiHost is already
    // validated non-empty - and is there so a typo'd host cannot turn into a force-unwrap
    // crash on launch.
    static let base = URL(string: "https://\(Branding.apiHost)") ?? URL(string: "https://\(Branding.defaultApiHost)")!

    // This key is NOT a secret, and is deliberately committed in cleartext.
    //
    // It is compiled into the binary, so `strings` on any installed IPA recovers it.
    // Hiding it from git would protect nothing while it sits readable on every worker's
    // phone. It is a coarse gate against unauthenticated internet noise, nothing more.
    //
    // Since decision-22 it carries no authority on its own: /roster and every /shifts/*
    // route require a worker session (SMS OTP or the admin-issued code, decision-50), and
    // the app key alone answers 401. Extracting it buys an attacker no ability to file or
    // read hours.
    //
    // Because it is not a secret it is intentionally NOT in the psst vault - keeping it
    // there blocked every commit touching this file for no security gain. THIS LINE IS
    // THE RECORD: /etc/nfc/env on the VM must carry the same value, and re-provisioning
    // reads it from here.
    //
    // Rotated 2026-07-28; the previous key is permanently burned (leaked to an agent
    // transcript and a plaintext env file beside a public VM). Rotating REQUIRES shipping
    // a new build and updating /etc/nfc/env together - an old build stops working the
    // moment the server flips.
    //
    // CEILING: fine for a TestFlight-internal single-company app. If the API ever needs a
    // credential that must genuinely stay secret, this constant must go entirely - the fix
    // is not to hide it better, it is to never compile a credential in.
    static let appKey = "tsk_9880d49f83794967790deb8a2c8f3dd46633cc78104c2f65"

    // No admin surface here on purpose. The X-Admin-Pin header is gone; admin is
    // password-authenticated on the web (decision-20).

    /// Apple audience for the identity token. The SERVER verifies this claim; it is
    /// surfaced here only so the two halves can be diffed by eye against
    /// server/lib/apple.js APPLE_AUDIENCE. Read from the running bundle (Branding), so it
    /// stays correct automatically when a different entity signs with their own bundle id.
    static let bundleId = Branding.bundleId
}

/// The session died server-side (expired, revoked, worker deactivated). Posted from the
/// single response choke point below so no call site can forget to handle it, and the
/// app drops to signed-out instead of retrying a request that can never succeed.
extension Notification.Name {
    static let sessionRejected = Notification.Name("io.github.qwadratic.NFCTimeSheets.sessionRejected")
}

// MARK: - Date coding

/// One encoder and one decoder for the whole app.
/// Encode: ISO-8601 with fractional seconds, UTC (`2026-07-28T14:03:11.412Z`).
/// Decode: fractional first, then plain - Postgres hands back whole seconds when the
/// microseconds happen to be zero, and a decoder that only knew one shape would throw
/// on an otherwise perfect response.
enum Wire {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func string(from date: Date) -> String { isoFractional.string(from: date) }

    static func date(from text: String) -> Date? {
        isoFractional.date(from: text) ?? isoPlain.date(from: text)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(string(from: date))
        }
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = date(from: text) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "not ISO-8601: \(text)"))
            }
            return date
        }
        return d
    }()
}

// MARK: - Errors

/// A failed call, classified. `status == 0` means the request never got an answer.
struct APIFailure: Error {
    let status: Int
    let code: String
    let field: String?
    let body: Data?

    init(status: Int, code: String, field: String? = nil, body: Data? = nil) {
        self.status = status
        self.code = code
        self.field = field
        self.body = body
    }

    /// Retry, or give up and tell the worker?
    ///
    /// Retrying a 400 forever is pointless - the same bytes will be rejected the same
    /// way after lunch. A 4xx means THIS payload is wrong and a human has to act; a
    /// transport error, a 5xx, a 408 or a 429 means the payload may well be fine and
    /// the next attempt can succeed.
    ///
    /// 409 shift_already_open is the one 4xx that is retryable: it means an OLDER shift
    /// of ours has not been closed on the server yet. The sync pass works in start-time
    /// order, so the next pass closes that one first and this open then lands.
    ///
    /// 422 zone_unverified is retryable for the same reason: requireVerifiedPlace
    /// (server/lib/validate.js) rejects a clock-in at a zone an operator has not yet
    /// test-scanned (decision-47), which is a temporary state of the SERVER's
    /// configuration, not a defect in this payload - the operator's scan later makes the
    /// identical request succeed, so a locally-recorded worked shift must not be stranded
    /// by it.
    ///
    /// Every OTHER 401 is retryable, and that is the fix for a measured payroll data-loss
    /// bug (ops/break-taps.sh §8): a worker session that lapses mid-shift 401s the
    /// clock-out, and the bytes were always fine - a 401 is a statement about the
    /// CREDENTIAL, not the payload. The one exception is `invalid_code`: a sign-in code is
    /// single-use and rate-limited, so auto-retrying a rejected one would burn the
    /// worker's remaining attempts and lock the phone out for fifteen minutes at the exact
    /// moment they are trying to get in. See checks/tag-link-check.swift for the vectors
    /// this exact expression is pinned against.
    var isRetryable: Bool {
        code == "shift_already_open" || code == "zone_unverified" || (status == 401 && code != "invalid_code")
            || status == 0 || status == 408 || status == 429 || status >= 500
    }

    /// Shown to the worker. Deliberately says what to DO, not what broke.
    ///
    /// LOCALISED, via Localizable.xcstrings. The default language is German (decision-8)
    /// and the crew reading these sentences at a door in Vienna is German-speaking; the
    /// English literals below are the KEYS, not the output.
    ///
    /// It is still a `switch` over the server's own error codes and not a lookup by
    /// generated key: a code this build has never seen falls into `default` and says so,
    /// rather than rendering an empty string at a door in the dark.
    var workerMessage: String {
        switch code {
        case "proof_required", "proof_expired", "proof_challenge_expired":
            return String(localized: "Take a new photo to finish this shift. Your shift has not been finished.")
        case "network":
            return String(localized: "No connection - will send when you're back online.")
        case "unknown_worker":
            return String(localized: "Your name is no longer on the roster. Ask your admin.")
        case "unknown_location":
            return String(localized: "This location was removed. Ask your admin.")
        case "unknown_shift":
            return String(localized: "The server doesn't have this shift. Ask your admin.")
        case "unknown_request":
            return String(localized: "The server doesn't have this request any more. Ask your admin.")
        case "not_found":
            // An unrouted path, i.e. this build is newer than the server. Never a
            // rejection of what was sent - see MaterialStore.push, which keeps the row.
            return String(localized: "Not available on the server yet - saved and will be sent later.")
        case "shift_already_open":
            return String(localized: "Another shift is still running - finishing it first.")
        case "end_before_start":
            return String(localized: "Finish time is before the start time.")
        case "timestamp_in_future", "timestamp_out_of_range":
            return String(localized: "This phone's clock looks wrong. Check Date & Time in Settings.")
        case "unauthorized":
            return String(localized: "This app version was rejected by the server. Update it.")
        case "no_session":
            return String(localized: "You were signed out. Sign in again.")
        case "zone_unverified":
            // decision-47 / server/lib/validate.js requireVerifiedPlace. Same wording as
            // Android's err_zone_unverified - one sentence across both phones.
            return String(localized: "This tag hasn't been activated yet. No shift was started. Please contact your administration.")
        case "tag_unbound":
            // server/lib/validate.js activePlace: the card was written and reported but nobody
            // has made it a zone yet. TERMINAL, like Android's err_tag_unbound - the same
            // sentence on both phones (decision-76 §4). Before this case iOS fell through to
            // "Rejected by the server (tag_unbound)", which reads as a broken card.
            return String(localized: "This tag isn't assigned to a building yet. No shift was started. Please contact your administration.")
        case "too_many_attempts":
            return String(localized: "Too many attempts - try again shortly.")
        default:
            return status >= 500 || status == 0
                ? String(localized: "Server trouble - will retry.")
                : String(localized: "Rejected by the server (\(code)). Ask your admin.")
        }
    }
}

// MARK: - Wire types

struct WireWorker: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}

// MARK: - Auth (decision-22, decision-50)

/// 200 from POST /auth/sms/verify, POST /auth/code and GET /auth/session. The session
/// cookie rides in the headers.
/// `expiresAt` is informational and OPTIONAL: only the sign-in response carries it,
/// /auth/session answers with the worker alone. The server enforces expiry either way,
/// so the app never pre-empts it.
struct WireSession: Decodable {
    let worker: WireWorker
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case worker
        case expiresAt = "expires_at"
    }
}

/// `{}`. Used where the server answers with an empty object.
struct WireEmpty: Decodable {}

struct WireLocation: Codable, Identifiable, Hashable {
    /// UUID. This is what a tag carries (decision-21).
    let id: String
    /// Human-readable handle. Display and log lines ONLY - never goes on a tag.
    let slug: String
    let name: String
}

/// One zone of GET /roster (decision-43): a door inside a building. `id` is what a zone's
/// card carries and what a tap posts; `locationId` is the BUILDING it belongs to.
/// `tagSerial` is only ever present for a VERIFIED zone (server/routes/app.js, decision-47).
struct WireZone: Codable, Hashable {
    let id: String
    let locationId: String
    let name: String
    let tagSerial: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case locationId = "location_id"
        case tagSerial = "tag_serial"
    }
}

/// GET /roster. The server also sends a `workers` array; it is deliberately NOT decoded.
/// The app has no picker to fill any more (decision-22) and does not need a staff list on
/// every phone - and leaving the field out means the day the server stops sending it, the
/// location cache keeps decoding instead of the app forgetting every tag it knows.
///
/// `zones` IS DECODED LEAST-STRICTLY OF ALL, and that is the same fear stated one field
/// over: a zone row this build cannot parse, or a server too old to send the key at all, must
/// never cost the app its LOCATIONS. A missing key is an empty list; one malformed zone drops
/// that zone and nothing else.
struct WireRoster: Codable {
    let locations: [WireLocation]
    let zones: [WireZone]

    enum CodingKeys: String, CodingKey { case locations, zones }

    init(locations: [WireLocation], zones: [WireZone] = []) {
        self.locations = locations
        self.zones = zones
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        locations = try container.decode([WireLocation].self, forKey: .locations)
        zones = ((try? container.decode([LossyZone].self, forKey: .zones)) ?? []).compactMap(\.value)
    }

    private struct LossyZone: Decodable {
        let value: WireZone?
        init(from decoder: Decoder) throws { value = try? WireZone(from: decoder) }
    }
}

/// One PLANNED assignment of GET /me/schedule (decision-80). Display only: a plan is a
/// picture of the week, never an input to a clock-in, sync, signal or payroll.
///
/// Five fields and no more. The server row (`SELECT p.*, worker_name, location_name`,
/// server/routes/schedule.js) carries `location_id`, `worker_id`, `worker_name`, `tenant_id`,
/// `cancelled_at`, `version`, `created_at`, `updated_at` as well; NONE is decoded, and
/// `location_id` least of all: it is a BUILDING id and a building id is no clock-in target
/// (decision-69), so a plan must not offer the app one to tap. Android's Wire.scheduleAssignment
/// reads the same five. `note` is NOT NULL on the server, yet it is the one optional key here
/// (absent or null reads as ''): a missing instruction is cosmetic and must not cost the worker
/// the line that says where and when.
struct WireScheduleAssignment: Decodable, Identifiable, Equatable {
    /// The plan's own UUID (a row identity, not a place), kept as the server sent it.
    let id: String
    /// The building's name, joined server-side. Plain text for display.
    let locationName: String
    let startsAt: Date
    let endsAt: Date
    let note: String

    enum CodingKeys: String, CodingKey {
        case id
        case locationName = "location_name"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case note
    }

    init(id: String, locationName: String, startsAt: Date, endsAt: Date, note: String = "") {
        self.id = id
        self.locationName = locationName
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        locationName = try container.decode(String.self, forKey: .locationName)
        startsAt = try container.decode(Date.self, forKey: .startsAt)
        endsAt = try container.decode(Date.self, forKey: .endsAt)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

/// 200 body of GET /me/schedule: `{assignments: [...]}`.
///
/// DECODED THE WAY THE ROSTER'S ZONES ARE: one row this build cannot read drops THAT row and
/// nothing else, so one odd plan never takes the whole list down (Android's strict `map` would
/// show "could not load" for all of them). The one exception is the case where rows WERE sent
/// and not one could be read: that is a shape this build does not understand, and rendering it
/// as "no assignments planned" would tell a worker with a full week that they have nothing.
/// It throws instead, and the card says "could not load". A missing or non-array `assignments`
/// key throws too.
struct WireScheduleEnvelope: Decodable {
    let assignments: [WireScheduleAssignment]

    enum CodingKeys: String, CodingKey { case assignments }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rows = try container.decode([LossyAssignment].self, forKey: .assignments)
        let readable = rows.compactMap(\.value)
        if !rows.isEmpty && readable.isEmpty {
            throw DecodingError.dataCorruptedError(
                forKey: .assignments, in: container,
                debugDescription: "\(rows.count) assignment row(s), none readable")
        }
        assignments = readable
    }

    private struct LossyAssignment: Decodable {
        let value: WireScheduleAssignment?
        init(from decoder: Decoder) throws { value = try? WireScheduleAssignment(from: decoder) }
    }
}

/// The single shift shape every shift endpoint returns.
/// `location_slug` / `location_name` ride along on the joined queries only.
struct WireShift: Codable, Identifiable {
    let id: Int
    let workerId: Int
    let locationId: String
    let startTime: Date
    let endTime: Date?
    let autoClosed: Bool
    let correctedAt: Date?
    /// decision-56. Additive and OPTIONAL: a server that has not shipped the migration yet
    /// simply omits them, and `?? false` keeps every existing row reading exactly as before.
    let manualStart: Bool?
    let manualClose: Bool?
    /// Nullable in the schema, and not necessarily UUID-shaped for rows the server made
    /// itself, so it is decoded as a plain String.
    let clientUuid: String?
    let locationSlug: String?
    let locationName: String?
    var locationIntervalSeconds: Int? = nil
    var proofOfWorkRequired: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case workerId = "worker_id"
        case locationId = "location_id"
        case startTime = "start_time"
        case endTime = "end_time"
        case autoClosed = "auto_closed"
        case correctedAt = "corrected_at"
        case manualStart = "manual_start"
        case manualClose = "manual_close"
        case clientUuid = "client_uuid"
        case locationSlug = "location_slug"
        case locationName = "location_name"
        case locationIntervalSeconds = "location_interval_seconds"
        case proofOfWorkRequired = "proof_of_work_required"
    }

    /// Derived, never stored (decision-10): the 8h timer closed it and no human has
    /// fixed it yet. No third flag exists that could disagree with these two.
    var needsResolution: Bool { autoClosed && correctedAt == nil }
}

struct WireShiftEnvelope: Codable {
    let shift: WireShift
    let duplicate: Bool?
}

struct WireOptionalShiftEnvelope: Codable {
    let shift: WireShift?
}

struct WireShiftListEnvelope: Codable {
    let shifts: [WireShift]
}

/// decision-22: NO worker_id. Who is clocking in is decided by the session cookie on
/// the server, never by a field the phone fills in. Putting it back would restore the
/// hole this whole change exists to close - anyone could file hours as anyone.
struct OpenShiftRequest: Encodable {
    let clientUuid: String
    let locationUuid: String
    let startTime: Date
    /// decision-56: the worker picked the building out of the roster instead of tapping a
    /// card. OPTIONAL on the wire and omitted when false, so a server that predates the
    /// field sees byte-identical bodies to the ones it has always taken. Validation is
    /// UNCHANGED server-side - a manual open only succeeds where a real tap would too.
    let manual: Bool?

    enum CodingKeys: String, CodingKey {
        case clientUuid = "client_uuid"
        case locationUuid = "location_uuid"
        case startTime = "start_time"
        case manual
    }
}

struct CloseShiftRequest: Encodable {
    var proofId: String? = nil
    let clientUuid: String
    let endTime: Date
    /// True when the APP closed the shift rather than the worker deliberately tapping out
    /// (today: they tapped a different building first). The end time is then the moment they
    /// turned up elsewhere, which nobody confirmed, so the server flags it for resolution.
    let autoClosed: Bool
    /// decision-56: the worker pressed Stop instead of tapping out. NOT the same fact as
    /// `autoClosed` and never conflated with it - the 8h timer / other-building path is
    /// untouched. The server stamps `corrected_at` in the same update, so this row lands
    /// already resolved and needs no follow-up confirmation. Omitted when false.
    let manual: Bool?

    enum CodingKeys: String, CodingKey {
        case clientUuid = "client_uuid"
        case endTime = "end_time"
        case autoClosed = "auto_closed"
        case proofId = "proof_id"
        case manual
    }
}

struct ResolveShiftRequest: Encodable {
    var proofId: String? = nil
    let endTime: Date

    enum CodingKeys: String, CodingKey {
        case proofId = "proof_id"
        case endTime = "end_time"
    }
}

// MARK: - Transport

private func apiURL(_ path: String, query: [String: String]) -> URL {
    var parts = URLComponents(url: API.base.appending(path: path), resolvingAgainstBaseURL: false)!
    if !query.isEmpty {
        parts.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
    }
    return parts.url!
}

/// Single choke point: every response is classified before anything else sees it.
private func send(_ request: URLRequest) async throws -> Data {
    let data: Data
    let response: URLResponse
    do {
        (data, response) = try await URLSession.shared.data(for: request)
    } catch {
        // Offline, DNS, timeout, TLS. Always retryable.
        throw APIFailure(status: 0, code: "network")
    }

    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
        // Server error bodies are `{"error":"code"}` (+ optional `"field"`).
        let parsed = try? Wire.decoder.decode(WireError.self, from: data)
        // Any 401 that is not invalid_code means this session is not coming back: expired,
        // revoked, or the worker was deactivated in the admin panel. Drop to signed-out
        // ONCE, from here, rather than letting each caller retry a request that can never
        // succeed (decision-22). invalid_code is a sign-IN rejection, not a session loss -
        // there is no session yet to drop - so it must NOT post this notification.
        if status == 401, parsed?.error != "invalid_code" {
            NotificationCenter.default.post(name: .sessionRejected, object: nil)
        }
        throw APIFailure(status: status,
                         code: parsed?.error ?? "http_\(status)",
                         field: parsed?.field,
                         body: data)
    }
    return data
}

private struct WireError: Decodable {
    let error: String
    let field: String?
}

/// The worker session rides in a cookie, held by URLSession's shared cookie store. No
/// call site here sets or reads it: HTTPCookieStorage does that, persists it across
/// launches (the server sends Max-Age), and keeps it in the app's protected container
/// rather than in UserDefaults where a backup or a file browser would find it. The
/// worker therefore signs in about once a week, not once per shift.
func apiGet<Out: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> Out {
    var request = URLRequest(url: apiURL(path, query: query))
    request.setValue(API.appKey, forHTTPHeaderField: "X-App-Key")
    return try Wire.decoder.decode(Out.self, from: try await send(request))
}

func apiPost<In: Encodable, Out: Decodable>(_ path: String, _ body: In) async throws -> Out {
    var request = URLRequest(url: apiURL(path, query: [:]))
    request.httpMethod = "POST"
    request.setValue(API.appKey, forHTTPHeaderField: "X-App-Key")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try Wire.encoder.encode(body)
    return try Wire.decoder.decode(Out.self, from: try await send(request))
}

// MARK: - Endpoints

/// Sign-in, session restore, sign-out. Everything else on the app surface assumes the
/// cookie one of these left behind. Sign in with Apple is retired from this app
/// (decision-50); the two doors below are the whole surface. POST /auth/apple stays on
/// the SERVER (deprecated in words, not deleted - see server/routes/auth.js), but this
/// file has no caller for it any more.
enum AuthAPI {
    /// POST /auth/sms/request {phone} -> 202 {status:"accepted"}.
    ///   404 unknown_phone (decision-51) · 422 invalid_phone (shape only) ·
    ///   429 too_many_attempts · 503 sms_not_configured.
    /// Mints no session - the caller (Session.requestSmsCode) only learns whether a code
    /// went out. The specific failure copy lives beside the field it is shown next to
    /// (ContentView.swift SignInView), not here.
    static func requestSmsCode(phone: String) async throws -> WireSmsRequestAck {
        try await apiPost("/auth/sms/request", PhoneRequest(phone: phone))
    }

    /// POST /auth/sms/verify {phone, code} -> worker session cookie (ts_worker).
    /// BYTE-IDENTICAL 200 body to POST /auth/code's.
    ///   401 invalid_code (every failure mode) · 429 too_many_attempts · 503 sms_not_configured.
    static func verifySmsCode(phone: String, code: String) async throws -> WireSession {
        try await apiPost("/auth/sms/verify", SmsVerifyRequest(phone: phone, code: code))
    }

    /// POST /auth/code {code} -> worker session cookie (ts_worker). decision-26: the
    /// admin-issued enrolment code, EnrolmentCode.swift-normalised by the caller before
    /// this is ever reached.
    ///   401 invalid_code (every failure mode) · 429 too_many_attempts.
    static func signInWithCode(_ code: String) async throws -> WireSession {
        try await apiPost("/auth/code", CodeRequest(code: code))
    }

    /// GET /auth/capabilities -> {sms: Bool}. THE APP'S ONE PUBLIC CAPABILITY READ
    /// (decision-59 §2), the twin of Android's `Api.capabilities()`.
    ///
    /// `auth: "app"`, NO SESSION: the screen that needs the answer is exactly the screen a
    /// phone with no session yet is showing, so this must be askable before any cookie
    /// exists. It carries the app key like every other call here and nothing else.
    ///
    /// The server ANDs two things into the one field - Twilio being configured and the
    /// `sms_login` flag (server/routes/auth.js `capabilities`) - so the phone never learns,
    /// and never needs to learn, WHICH of the two closed the door.
    ///
    /// Prefer `smsDoorAvailable()` below at call sites; it is the fail-closed read.
    static func capabilities() async throws -> WireCapabilities {
        try await apiGet("/auth/capabilities")
    }

    /// `capabilities().sms`, with EVERY failure read as false - offline, a timeout, an old
    /// server that predates the route, a malformed body. Byte-for-byte the intent of
    /// Android's `runCatching { app.api.capabilities() }.getOrDefault(false)`.
    ///
    /// FAIL CLOSED IS THE FEATURE, not defensive habit: a phone that could not confirm the
    /// SMS door is open must behave exactly like a phone whose server says it is shut,
    /// never like one where it is open. Drawing a control on a guess is the 503-on-tap this
    /// route exists to delete.
    static func smsDoorAvailable() async -> Bool {
        (try? await capabilities())?.sms ?? false
    }

    /// GET /auth/session - is this cookie still a worker? 401 when it is not.
    /// Asked on every launch: the server, not the phone, decides who is signed in, so
    /// deactivating a worker in the admin panel locks them out on their next launch.
    static func me() async throws -> WireSession { try await apiGet("/auth/session") }

    /// POST /auth/logout - revokes the session server-side, not just locally.
    static func logout() async throws {
        let _: WireEmpty = try await apiPost("/auth/logout", WireLogoutRequest())
    }
}

/// 200 body of GET /auth/capabilities. ONE FIELD, and deliberately no `missing[]` or
/// `sender_kind`: that detail is for the person who can fix it (GET /admin/sms-status,
/// admin-auth only), not for anyone holding the app key `strings` recovers from an IPA.
struct WireCapabilities: Decodable {
    let sms: Bool
}

private struct PhoneRequest: Encodable { let phone: String }
private struct CodeRequest: Encodable { let code: String }
private struct SmsVerifyRequest: Encodable { let phone: String; let code: String }

/// 202 body of POST /auth/sms/request. The one field is never inspected - a 2xx status is
/// already the whole answer - but it is decoded so a shape change on the server is a
/// decode failure here, not a silently-ignored body.
struct WireSmsRequestAck: Decodable { let status: String }

/// POST with no fields. `{}` rather than an empty body so the server's JSON parse is
/// never handed zero bytes.
private struct WireLogoutRequest: Encodable {}

enum ShiftAPI {
    /// POST /shifts/open  {client_uuid, location_uuid, start_time}
    /// 201 new · 200 duplicate (same client_uuid) · 409 shift_already_open.
    /// The worker is the session's worker. See OpenShiftRequest for why.
    static func open(clientUuid: String, locationId: String, startTime: Date,
                     manual: Bool = false) async throws
        -> WireShiftEnvelope
    {
        try await apiPost("/shifts/open",
                          OpenShiftRequest(clientUuid: clientUuid,
                                           locationUuid: locationId,
                                           startTime: startTime,
                                           manual: manual ? true : nil))
    }

    /// POST /shifts/close {client_uuid, end_time}. No duration ceiling any more: the old
    /// 422 shift_too_long blocked exactly the worker the 8h net exists for (decision-10).
    static func close(clientUuid: String, endTime: Date, autoClosed: Bool = false,
                      manual: Bool = false, proofId: String? = nil) async throws -> WireShiftEnvelope {
        try await apiPost("/shifts/close",
                          CloseShiftRequest(proofId: proofId, clientUuid: clientUuid, endTime: endTime,
                                            autoClosed: autoClosed, manual: manual ? true : nil))
    }

    /// GET /shifts/open - the server, not the phone, is authoritative for "who is clocked
    /// in right now" (decision-19), and for WHO is asking (decision-22). The ?worker=
    /// parameter is gone: it let any caller read any worker's whereabouts.
    static func currentOpen() async throws -> WireShift? {
        let envelope: WireOptionalShiftEnvelope = try await apiGet("/shifts/open")
        return envelope.shift
    }

    /// GET /shifts/unresolved - auto_closed AND corrected_at IS NULL, for the session's
    /// worker. ?worker= removed for the same reason as above.
    static func unresolved() async throws -> [WireShift] {
        let envelope: WireShiftListEnvelope = try await apiGet("/shifts/unresolved")
        return envelope.shifts
    }

    /// GET /shifts/mine?since=<iso8601> - this worker's shifts, newest first.
    ///
    /// Exists so the on-device migration can ask "does the server already hold this
    /// client_uuid?" before touching a legacy row (DataMigrations.swift), instead of
    /// guessing or duplicating. The worker is the session's worker; there is no ?worker=
    /// and there must never be one (decision-22).
    static func mine(since: Date) async throws -> [WireShift] {
        let envelope: WireShiftListEnvelope =
            try await apiGet("/shifts/mine", query: ["since": Wire.string(from: since)])
        return envelope.shifts
    }

    /// POST /shifts/:id/resolve {end_time} - the worker supplies the real finish time.
    static func resolve(shiftId: Int, endTime: Date, proofId: String? = nil) async throws -> WireShift {
        let envelope: WireShiftEnvelope = try await apiPost("/shifts/\(shiftId)/resolve",
                                                            ResolveShiftRequest(proofId: proofId, endTime: endTime))
        return envelope.shift
    }
}

enum RosterAPI {
    /// GET /roster -> workers + locations the app may pick from.
    static func fetch() async throws -> WireRoster { try await apiGet("/roster") }
}

/// decision-80. The signed-in worker's PLANNED assignments, read-only.
enum ScheduleAPI {
    /// GET /me/schedule -> {assignments:[{id, location_name, starts_at, ends_at, note, ...}]}.
    ///
    /// Worker session cookie + X-App-Key, NO query: who is asking is the session's worker and
    /// nobody else (decision-22; the server ignores a `?worker_id=`), so this takes no worker id
    /// and must never gain one. Through `apiGet`, the worker's cookie jar - never `OperatorAPI`.
    /// The server answers this worker's uncancelled plans that end after now and start within
    /// 31 days, in start order, at most 200 (server/routes/schedule.js `mine`).
    ///
    /// 401 -> signed out by `send` (the response choke point); a transport failure is
    /// `APIFailure(status: 0)`; a server that predates migration 025 answers 404 / 500. This
    /// function only reports - ScheduleStore decides how each reads, and nothing on the tap, sync
    /// or signal path ever calls it.
    static func mine() async throws -> [WireScheduleAssignment] {
        let envelope: WireScheduleEnvelope = try await apiGet("/me/schedule")
        return envelope.assignments
    }
}

/// decision-57. GET /flags (worker auth) -> {name: bool} for every row in feature_flags.
/// No envelope: the object IS the map, so a second flag costs a row and no client change.
enum FlagsAPI {
    static func fetch() async throws -> [String: Bool] { try await apiGet("/flags") }
}
