// Runnable check: the worker's PLANNED assignments (TASK-365.5, iOS P4, decision-80).
//
//   cd NFCTimeSheets && ./checks/run.sh          (or, on its own:)
//   cat NFCTimeSheets/Branding.swift NFCTimeSheets/TagLink.swift NFCTimeSheets/API.swift \
//     NFCTimeSheets/WorkerScope.swift NFCTimeSheets/LoadGuard.swift NFCTimeSheets/ViennaTime.swift \
//     NFCTimeSheets/ScheduleStore.swift checks/schedule-check.swift > /tmp/schedule-check.swift \
//     && swift /tmp/schedule-check.swift
//
// WHAT THE FEATURE IS: GET /me/schedule, shown read-only as a collapsed "Next planned assignment"
// row on the idle and the running screen and an expanded "My schedule" card. Ported from Android at
// 60f6886 (TimeSheetViewModel.loadSchedule, WorkerHomeCards.kt).
//
// WHAT THIS CHECK GUARDS, in five parts, because each one is a way this feature would quietly be
// wrong without anyone noticing at a door:
//   1. THE WIRE. A row with extra keys, ".000Z" and whole-second timestamps, no note, an empty list;
//      one unreadable row costs that row only; `location_id` is never decoded.
//   2. VIENNA TIME. Fixed instants, winter and summer, a 22:00-02:00 night, an end at exactly
//      00:00, both DST changes, and a device zone that is NOT Vienna (it is set to Los Angeles,
//      Auckland, UTC and Kolkata in turn). One vector is the same day in UTC and two days in
//      Vienna: it is what a formatter that quietly uses the phone's zone gets wrong.
//   3. THE GUARD. A stale answer, a different worker, the same worker, a cancelled request.
//   4. THE STORE, run for real with an injected fetch: every one of those rules as the screen sees
//      them, plus "offline is status 0 and nothing else", "a 401 renders nothing", "a refused load
//      is a no-op".
//   5. THE WIRING, read as text (ContentView.swift, ShiftScreen.swift, ScheduleViews.swift, and the
//      files that must NOT know about any of this): the schedule is DISPLAY ONLY - not in refresh(),
//      handleTap, the sync pass, the signals or the tab lock - the views carry no surface of their
//      own (the Blue Hour reskin restyles them), and every string is in BOTH languages, the two
//      time-line templates match the catalogue to the character, and the German is Android's.
//
// WHAT THIS CANNOT PIN: that the views look right, that `.onAppear` fires on a tab return, that the
// refresh icon reads "Einsätze aktualisieren" under VoiceOver. Those need a worker session on a
// device or simulator (TASK-365.22 is the rig that signs one in).
//
// RED CASES, reproduced against mutated copies of the real files before this was trusted: see the
// commit that added it.

import Foundation

var failed = false
func check(_ ok: Bool, _ what: String) {
    if !ok {
        FileHandle.standardError.write(Data("FAIL: \(what)\n".utf8))
        failed = true
    }
}

func source(_ name: String) -> String {
    guard let text = try? String(contentsOfFile: "NFCTimeSheets/\(name)", encoding: .utf8) else {
        FileHandle.standardError.write(Data("FAIL: cannot read NFCTimeSheets/\(name)\n".utf8))
        exit(1)
    }
    return text
}
/// Code only: comments and doc comments carry the rationale and quote the very things this check bans.
func code(_ s: String) -> String {
    s.components(separatedBy: "\n")
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        .joined(separator: "\n")
}
func between(_ s: String, _ from: String, _ to: String) -> String {
    let after = s.components(separatedBy: from)
    guard after.count > 1 else { return "" }
    return after[1].components(separatedBy: to)[0]
}
func iso(_ s: String) -> Date { Wire.date(from: s)! }

// ---------------------------------------------------------------------------------
// 1. THE WIRE
// ---------------------------------------------------------------------------------

func decodeRows(_ json: String) throws -> [WireScheduleAssignment] {
    try Wire.decoder.decode(WireScheduleEnvelope.self, from: Data(json.utf8)).assignments
}
/// A decode that THROWS reads as no rows at all, so a regression is reported as a failed assertion
/// below and not as a crash in the middle of the script.
func rowsOrEmpty(_ json: String) -> [WireScheduleAssignment] { (try? decodeRows(json)) ?? [] }

// A row exactly as `SELECT p.*, w.name AS worker_name, l.name AS location_name` sends it
// (server/routes/schedule.js), extra keys and all.
let fullRow = """
{"id":"7a1c0f2e-5b34-4e8a-9d11-0c2f6a9b1e01","tenant_id":1,"worker_id":12,"worker_name":"Anna Muster",
 "location_id":"0b9e5a44-3c1d-4f60-8a77-2d9e1c3b5f10","location_name":"Musterhaus Wien 3",
 "starts_at":"2026-10-08T06:00:00.000Z","ends_at":"2026-10-08T10:00:00.000Z","note":"Bring keys",
 "cancelled_at":null,"version":1,"created_at":"2026-10-07T10:00:00.000Z","updated_at":"2026-10-07T10:00:00.000Z"}
"""
let full = rowsOrEmpty("{\"assignments\":[\(fullRow)]}")
check(full.count == 1, "a full server row decodes")
if let row = full.first {
    check(row.id == "7a1c0f2e-5b34-4e8a-9d11-0c2f6a9b1e01", "id is kept as the server sent it")
    check(row.locationName == "Musterhaus Wien 3", "location_name -> locationName")
    check(row.startsAt == iso("2026-10-08T06:00:00Z") && row.endsAt == iso("2026-10-08T10:00:00Z"),
          "a '.000Z' timestamp decodes to the right instant")
    check(row.note == "Bring keys", "note is kept")
}

// Exactly five fields: the extra keys (and location_id above all) are not decoded.
let rowFields = full.first.map { Mirror(reflecting: $0).children.compactMap(\.label) } ?? []
check(rowFields == ["id", "locationName", "startsAt", "endsAt", "note"],
      "WireScheduleAssignment has exactly id, locationName, startsAt, endsAt, note - no location_id (\(rowFields))")
let wireTypeText = code(between(source("API.swift"), "struct WireScheduleAssignment: Decodable", "/// 200 body of GET /me/schedule"))
check(!wireTypeText.contains("location_id") && !wireTypeText.contains("locationId"),
      "the plan's building id is never decoded (a building id is no clock-in target, decision-69)")

// Postgres hands back whole seconds when the fraction is zero; both shapes must decode.
let whole = rowsOrEmpty("{\"assignments\":[{\"id\":\"a\",\"location_name\":\"X\",\"starts_at\":\"2026-10-08T06:00:00Z\",\"ends_at\":\"2026-10-08T10:00:00Z\",\"note\":\"\"}]}")
check(whole.first?.startsAt == iso("2026-10-08T06:00:00Z") && whole.first?.endsAt == iso("2026-10-08T10:00:00Z"),
      "a whole-second timestamp (no fraction) decodes")
let mixed = rowsOrEmpty("{\"assignments\":[{\"id\":\"a\",\"location_name\":\"X\",\"starts_at\":\"2026-10-08T06:00:00.123Z\",\"ends_at\":\"2026-10-08T10:00:00Z\"}]}")
check(mixed.first.map { $0.endsAt.timeIntervalSince($0.startsAt) } ?? 0 > 14399, "a fractional start and a whole-second end in one row both decode")

// note: absent, null and "" are all ''.
let noNote = rowsOrEmpty("{\"assignments\":[{\"id\":\"a\",\"location_name\":\"X\",\"starts_at\":\"2026-10-08T06:00:00Z\",\"ends_at\":\"2026-10-08T10:00:00Z\"}]}")
check(noNote.first?.note == "", "note ABSENT reads as ''")
let nullNote = rowsOrEmpty("{\"assignments\":[{\"id\":\"a\",\"location_name\":\"X\",\"starts_at\":\"2026-10-08T06:00:00Z\",\"ends_at\":\"2026-10-08T10:00:00Z\",\"note\":null}]}")
check(nullNote.first?.note == "", "note NULL reads as ''")

check((try? decodeRows("{\"assignments\":[]}"))?.isEmpty == true, "an empty list decodes to an empty list (not an error)")

// The server's order is the order: no client-side sorting, grouping or re-ordering.
let twoRows = rowsOrEmpty("""
{"assignments":[
 {"id":"late","location_name":"B","starts_at":"2026-10-09T06:00:00Z","ends_at":"2026-10-09T10:00:00Z"},
 {"id":"early","location_name":"A","starts_at":"2026-10-08T06:00:00Z","ends_at":"2026-10-08T10:00:00Z"}]}
""")
check(twoRows.map(\.id) == ["late", "early"], "the server's order is kept (Android: server order, no grouping)")

// ONE MALFORMED ROW COSTS THAT ROW, never the list.
let withBad = rowsOrEmpty("""
{"assignments":[
 {"id":"ok1","location_name":"A","starts_at":"2026-10-08T06:00:00Z","ends_at":"2026-10-08T10:00:00Z"},
 {"id":"bad-date","location_name":"B","starts_at":"tomorrow morning","ends_at":"2026-10-08T10:00:00Z"},
 {"location_name":"no id","starts_at":"2026-10-08T06:00:00Z","ends_at":"2026-10-08T10:00:00Z"},
 {"id":7,"location_name":"numeric id","starts_at":"2026-10-08T06:00:00Z","ends_at":"2026-10-08T10:00:00Z"},
 {"id":"no-name","starts_at":"2026-10-08T06:00:00Z","ends_at":"2026-10-08T10:00:00Z"},
 42,
 {"id":"ok2","location_name":"C","starts_at":"2026-10-09T06:00:00Z","ends_at":"2026-10-09T10:00:00Z"}]}
""")
check(withBad.map(\.id) == ["ok1", "ok2"],
      "unreadable rows are dropped one by one and their neighbours survive (\(withBad.map(\.id)))")

// ...but "rows were sent and none could be read" is NOT "nothing planned".
check((try? decodeRows("{\"assignments\":[{\"id\":\"x\"},{\"nonsense\":true}]}")) == nil,
      "rows sent but none readable THROWS (the card says 'could not load'), it is never an empty plan")
check((try? decodeRows("{}")) == nil, "a body without 'assignments' throws")
check((try? decodeRows("{\"assignments\":null}")) == nil, "'assignments': null throws")
check((try? decodeRows("{\"assignments\":\"none\"}")) == nil, "a non-array 'assignments' throws")

// THE REQUEST: no worker id, no query, the worker's own jar.
let apiSource = source("API.swift")
let mine = code(between(apiSource, "enum ScheduleAPI {", "\n}\n"))
check(mine.contains("apiGet(\"/me/schedule\")") && !mine.contains("query:") && !mine.contains("worker"),
      "ScheduleAPI.mine is apiGet(\"/me/schedule\") with no query and no worker id (identity is the session's, decision-22)")
check(!source("OperatorAPI.swift").contains("me/schedule"), "the operator's client never asks for a worker's plan")

// ---------------------------------------------------------------------------------
// 2. VIENNA TIME
// ---------------------------------------------------------------------------------

check(TimeZone(identifier: "Europe/Vienna") != nil && ViennaTime.zone.identifier == "Europe/Vienna",
      "the tz database knows Europe/Vienna, so the fallback in ViennaTime.zone is never the one in use")

let enGB = Locale(identifier: "en_GB")
let deAT = Locale(identifier: "de_AT")

// (name, start, end, same Vienna day?, en_GB line, de_AT line)
let timeCases: [(String, String, String, Bool, String, String)] = [
    ("winter, same day 08:00-12:00 CET",
     "2026-01-14T07:00:00Z", "2026-01-14T11:00:00Z", true,
     "14 Jan 2026 · 08:00–12:00", "14.01.2026 · 08:00–12:00"),
    ("summer, same day 08:00-12:00 CEST (one hour earlier in UTC)",
     "2026-07-14T06:00:00Z", "2026-07-14T10:00:00Z", true,
     "14 Jul 2026 · 08:00–12:00", "14.07.2026 · 08:00–12:00"),
    ("winter night 22:00-02:00 crosses midnight",
     "2026-01-14T21:00:00Z", "2026-01-15T01:00:00Z", false,
     "14 Jan 2026, 22:00 – 15 Jan 2026, 02:00", "14.01.2026, 22:00 – 15.01.2026, 02:00"),
    ("summer night 22:00-02:00 crosses midnight",
     "2026-07-14T20:00:00Z", "2026-07-15T00:00:00Z", false,
     "14 Jul 2026, 22:00 – 15 Jul 2026, 02:00", "14.07.2026, 22:00 – 15.07.2026, 02:00"),
    ("an end at exactly 00:00 is already the NEXT day",
     "2026-07-14T19:00:00Z", "2026-07-14T22:00:00Z", false,
     "14 Jul 2026, 21:00 – 15 Jul 2026, 00:00", "14.07.2026, 21:00 – 15.07.2026, 00:00"),
    ("a start at exactly 00:00 stays on its own day",
     "2026-07-13T22:00:00Z", "2026-07-14T02:00:00Z", true,
     "14 Jul 2026 · 00:00–04:00", "14.07.2026 · 00:00–04:00"),
    ("SAME DAY IN UTC, TWO DAYS IN VIENNA (23:30-00:30)",
     "2026-07-14T21:30:00Z", "2026-07-14T22:30:00Z", false,
     "14 Jul 2026, 23:30 – 15 Jul 2026, 00:30", "14.07.2026, 23:30 – 15.07.2026, 00:30"),
    ("DST spring forward: 01:00 CET to 03:30 CEST, the 02:00 hour never existed",
     "2026-03-29T00:00:00Z", "2026-03-29T01:30:00Z", true,
     "29 Mar 2026 · 01:00–03:30", "29.03.2026 · 01:00–03:30"),
    ("DST spring forward across midnight",
     "2026-03-28T22:00:00Z", "2026-03-29T02:00:00Z", false,
     "28 Mar 2026, 23:00 – 29 Mar 2026, 04:00", "28.03.2026, 23:00 – 29.03.2026, 04:00"),
    ("DST fall back: the 25-hour day, 00:00 CEST to 06:00 CET, one calendar day",
     "2026-10-24T22:00:00Z", "2026-10-25T05:00:00Z", true,
     "25 Oct 2026 · 00:00–06:00", "25.10.2026 · 00:00–06:00"),
    ("DST fall back: 02:30 happens twice, both are Vienna 25 Oct",
     "2026-10-25T00:30:00Z", "2026-10-25T01:30:00Z", true,
     "25 Oct 2026 · 02:30–02:30", "25.10.2026 · 02:30–02:30"),
]

// THE DEVICE ZONE IS NOT VIENNA, in four different ways, and none of it may show.
for deviceZone in ["America/Los_Angeles", "Pacific/Auckland", "UTC", "Asia/Kolkata", "Europe/Vienna"] {
    NSTimeZone.default = TimeZone(identifier: deviceZone)!
    // NSTimeZone.default is what an un-pinned DateFormatter / Calendar / Date.formatted() reads. (This
    // Mac's own zone is Europe/Vienna, so WITHOUT this override a formatter that quietly used the
    // phone's zone would pass here and fail on a worker's phone in any other zone.)
    let probe = iso("2026-07-14T12:00:00Z"), wanted = TimeZone(identifier: deviceZone)!.secondsFromGMT(for: probe)
    check(NSTimeZone.default.secondsFromGMT(for: probe) == wanted && Calendar(identifier: .gregorian).timeZone.secondsFromGMT(for: probe) == wanted,
          "the check really set the device zone to \(deviceZone)")
    check(deviceZone == "Europe/Vienna" || wanted != ViennaTime.zone.secondsFromGMT(for: probe),
          "\(deviceZone) really is not Vienna")
    for (name, start, end, sameDay, english, german) in timeCases {
        let s = iso(start), e = iso(end)
        check(ViennaTime.sameDay(s, e) == sameDay, "[\(deviceZone)] sameDay: \(name)")
        let gotEnglish = ScheduleTimeLine.text(from: s, to: e, locale: enGB)
        check(gotEnglish == english, "[\(deviceZone)] en_GB: \(name): got '\(gotEnglish)', expected '\(english)'")
        let gotGerman = ScheduleTimeLine.text(from: s, to: e, locale: deAT)
        check(gotGerman == german, "[\(deviceZone)] de_AT: \(name): got '\(gotGerman)', expected '\(german)'")
    }
}
NSTimeZone.default = TimeZone(identifier: "UTC")!

// The two templates really differ only by the dash, and the compact one uses the UNSPACED en dash.
let compact = ScheduleTimeLine.text(from: iso("2026-07-14T06:00:00Z"), to: iso("2026-07-14T10:00:00Z"), locale: enGB)
let long = ScheduleTimeLine.text(from: iso("2026-07-14T20:00:00Z"), to: iso("2026-07-15T00:00:00Z"), locale: enGB)
check(compact.contains("\u{00B7}") && compact.contains("\u{2013}") && !compact.contains(" \u{2013} "),
      "the same-day form is '<date> · <from>–<to>': a middle dot and an unspaced en dash")
check(long.contains(" \u{2013} ") && !long.contains("\u{00B7}"),
      "the cross-day form is '<date>, <from> – <date>, <to>': a spaced en dash and no middle dot")

// ---------------------------------------------------------------------------------
// 3. THE GUARD (LoadGuard)
// ---------------------------------------------------------------------------------

var lg = LoadGuard()
let t1 = lg.begin(for: 7)
check(lg.accepts(t1, sessionWorkerId: 7, cancelled: false), "the latest request, for the session's worker, is accepted")
let t2 = lg.begin(for: 7)
check(!lg.accepts(t1, sessionWorkerId: 7, cancelled: false), "a STALE ticket (a newer request began) is ignored")
check(lg.accepts(t2, sessionWorkerId: 7, cancelled: false), "...and the newer one is accepted")
check(!lg.accepts(t2, sessionWorkerId: 9, cancelled: false), "an answer for A is dropped once B holds the session")
check(!lg.accepts(t2, sessionWorkerId: nil, cancelled: false), "...and once nobody does (signed out)")
check(!lg.accepts(t2, sessionWorkerId: 7, cancelled: true), "a CANCELLED request never publishes, whatever else is true")

var lg2 = LoadGuard()
check(lg2.adopt(7) == true, "the first adoption of a worker resets (there was nobody before)")
let g0 = lg2.generation
check(lg2.adopt(7) == false && lg2.generation == g0, "the SAME worker keeps: no reset, nothing superseded")
let tOld = lg2.begin(for: 7)
check(lg2.adopt(9) == true, "a DIFFERENT worker resets")
check(!lg2.accepts(tOld, sessionWorkerId: 9, cancelled: false) && !lg2.accepts(tOld, sessionWorkerId: 7, cancelled: false),
      "...and supersedes everything A had in flight, even if A somehow holds the session again")
let tNew = lg2.begin(for: 9)
check(tNew.generation > tOld.generation, "generations only go up")

// ---------------------------------------------------------------------------------
// 4. THE STORE, for real, with an injected fetch
// ---------------------------------------------------------------------------------

func assignment(_ id: String, _ building: String = "Musterhaus") -> WireScheduleAssignment {
    WireScheduleAssignment(id: id, locationName: building,
                           startsAt: iso("2026-10-08T06:00:00Z"), endsAt: iso("2026-10-08T10:00:00Z"), note: "")
}
let planA = [assignment("a1", "A building"), assignment("a2", "A building 2")]
let planB = [assignment("b1", "B building")]

/// A server the check controls: each fetch parks until the check answers it.
@MainActor final class FakeServer {
    private(set) var calls = 0
    private var pending: [CheckedContinuation<[WireScheduleAssignment], Error>] = []
    func fetch() async throws -> [WireScheduleAssignment] {
        calls += 1
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func answer(_ index: Int, _ result: Result<[WireScheduleAssignment], Error>) { pending[index].resume(with: result) }
    /// Let the store's Task run until it has asked `n` times (bounded: a hung store fails, not hangs).
    func waitForCalls(_ n: Int) async {
        var spins = 0
        while calls < n && spins < 10_000 { await Task.yield(); spins += 1 }
        check(calls >= n, "the store made \(n) request(s) (made \(calls))")
    }
}
/// The session, as the store asks about it after the await.
@MainActor final class FakeSession { var worker: Int?; init(_ worker: Int?) { self.worker = worker } }

@MainActor func runStoreChecks() async {
    // Initial and the basic round trip.
    do {
        let server = FakeServer(), session = FakeSession(7)
        let store = ScheduleStore(fetch: server.fetch)
        check(store.state == .loading, "a new store is loading")
        let task = store.load(for: 7) { session.worker }
        check(task != nil && store.state == .loading && server.calls == 0,
              "load returns at once: the request has not even started when it returns, nothing waits on it")
        await server.waitForCalls(1)
        server.answer(0, .success(planA))
        await task?.value
        check(store.state == .loaded(planA), "the answer is published: \(store.state)")
        check(server.calls == 1, "ONE load is ONE fetch (\(server.calls))")

        // Loading again DROPS the list first, as Android does.
        let again = store.load(for: 7) { session.worker }
        check(store.state == .loading, "a reload drops the previous list at once (state is .loading, not the old plan)")
        await server.waitForCalls(2)
        server.answer(1, .success(planB))
        await again?.value
        check(store.state == .loaded(planB) && server.calls == 2, "...and then shows the new answer, one fetch per load")
    }

    // A STALE answer does not overwrite a newer one, in both arrival orders.
    for newerFirst in [true, false] {
        let server = FakeServer(), session = FakeSession(7)
        let store = ScheduleStore(fetch: server.fetch)
        let first = store.load(for: 7) { session.worker }
        await server.waitForCalls(1)
        let second = store.load(for: 7) { session.worker }
        await server.waitForCalls(2)
        if newerFirst {
            server.answer(1, .success(planB)); await second?.value
            server.answer(0, .success(planA)); await first?.value
        } else {
            server.answer(0, .success(planA)); await first?.value
            server.answer(1, .success(planB)); await second?.value
        }
        check(store.state == .loaded(planB),
              "a slow STALE answer never overwrites the newer one (newer answered \(newerFirst ? "first" : "last")): \(store.state)")
    }

    // Failures: offline is status 0 and NOTHING else.
    let failures: [(String, Error, ScheduleState?)] = [
        ("status 0 (no answer) is OFFLINE", APIFailure(status: 0, code: "network"), .failed(offline: true)),
        ("404 (production without the route) is the generic error", APIFailure(status: 404, code: "not_found"), .failed(offline: false)),
        ("500 (migration 025 missing) is the generic error", APIFailure(status: 500, code: "http_500"), .failed(offline: false)),
        ("503 is the generic error", APIFailure(status: 503, code: "http_503"), .failed(offline: false)),
        ("a body this build cannot read is the generic error", DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "x")), .failed(offline: false)),
        ("any other error is the generic error", URLError(.timedOut), .failed(offline: false)),
        ("a 401 renders NOTHING (the app is signing out), the state stays loading", APIFailure(status: 401, code: "no_session"), nil),
    ]
    for (name, error, expected) in failures {
        let server = FakeServer(), session = FakeSession(7)
        let store = ScheduleStore(fetch: server.fetch)
        let task = store.load(for: 7) { session.worker }
        await server.waitForCalls(1)
        server.answer(0, .failure(error))
        await task?.value
        check(store.state == (expected ?? .loading), "\(name): got \(store.state)")
    }

    // A CANCELLED request never paints anything, least of all "offline": API.swift's send() turns a
    // cancelled URLSession call into APIFailure(status: 0).
    do {
        let server = FakeServer(), session = FakeSession(7)
        let store = ScheduleStore(fetch: server.fetch)
        let task = store.load(for: 7) { session.worker }
        await server.waitForCalls(1)
        task?.cancel()
        server.answer(0, .failure(APIFailure(status: 0, code: "network")))     // what send() makes of the cancel
        await task?.value
        check(store.state == .loading, "a CANCELLED request does not paint the offline sentence: \(store.state)")
    }
    do {
        let server = FakeServer(), session = FakeSession(7)
        let store = ScheduleStore(fetch: server.fetch)
        let task = store.load(for: 7) { session.worker }
        await server.waitForCalls(1)
        task?.cancel()
        server.answer(0, .success(planA))
        await task?.value
        check(store.state == .loading, "...and a cancelled request that DID get an answer does not publish it either: \(store.state)")
    }
    // A superseded request is cancelled outright, and its failure never shows.
    do {
        let server = FakeServer(), session = FakeSession(7)
        let store = ScheduleStore(fetch: server.fetch)
        let first = store.load(for: 7) { session.worker }
        await server.waitForCalls(1)
        let second = store.load(for: 7) { session.worker }
        await server.waitForCalls(2)
        check(first?.isCancelled == true, "starting a new load cancels the one in flight")
        server.answer(0, .failure(APIFailure(status: 0, code: "network"))); await first?.value
        check(store.state == .loading, "the superseded request's failure paints nothing: \(store.state)")
        server.answer(1, .success(planA)); await second?.value
        check(store.state == .loaded(planA), "...and the live one still lands: \(store.state)")
    }

    // IDENTITY. Sign-out in flight: nothing is published.
    do {
        let server = FakeServer(), session = FakeSession(7)
        let store = ScheduleStore(fetch: server.fetch)
        let task = store.load(for: 7) { session.worker }
        await server.waitForCalls(1)
        session.worker = nil                                                  // A signed out
        server.answer(0, .success(planA)); await task?.value
        check(store.state == .loading, "an answer that lands after sign-out is dropped: \(store.state)")
    }
    // ...and a worker change in flight, on the same store.
    do {
        let server = FakeServer(), session = FakeSession(7)
        let store = ScheduleStore(fetch: server.fetch)
        let forA = store.load(for: 7) { session.worker }
        await server.waitForCalls(1)
        server.answer(0, .success(planA)); await forA?.value
        check(store.state == .loaded(planA), "A sees A's plan")

        session.worker = 9                                                    // B signs in on the same phone
        let forB = store.load(for: 9) { session.worker }
        check(store.state == .loading, "B's store STARTS LOADING: A's plan is not shown to B for a single frame (\(store.state))")
        await server.waitForCalls(2)
        server.answer(1, .success(planB)); await forB?.value
        check(store.state == .loaded(planB), "B sees B's plan: \(store.state)")
    }
    do {
        let server = FakeServer(), session = FakeSession(7)
        let store = ScheduleStore(fetch: server.fetch)
        let forA = store.load(for: 7) { session.worker }
        await server.waitForCalls(1)
        session.worker = 9                                                    // replaced while A's request is out
        let forB = store.load(for: 9) { session.worker }
        await server.waitForCalls(2)
        server.answer(1, .success(planB)); await forB?.value
        server.answer(0, .success(planA)); await forA?.value                  // A's late answer
        check(store.state == .loaded(planB), "A's late answer never replaces B's: \(store.state)")
    }
    // A load for somebody who does not hold the session is a no-op.
    do {
        let server = FakeServer(), session = FakeSession(9)
        let store = ScheduleStore(fetch: server.fetch)
        let task = store.load(for: 7) { session.worker }
        check(task == nil && server.calls == 0 && store.state == .loading,
              "a load for a worker who does not hold the session asks nothing and changes nothing")
        let signedOut = FakeSession(nil)
        check(store.load(for: 7) { signedOut.worker } == nil, "a signed-out phone asks nothing (Android: if not SignedIn return)")
    }
}
await runStoreChecks()

// ---------------------------------------------------------------------------------
// 5. THE WIRING, read as text
// ---------------------------------------------------------------------------------

let viewSource = source("ContentView.swift")
let view = code(viewSource)
let shiftScreen = code(source("ShiftScreen.swift"))
let views = code(source("ScheduleViews.swift"))
let storeText = code(source("ScheduleStore.swift"))

// DISPLAY ONLY: every mention of the schedule in ContentView.swift is one of these eight lines, and
// none is in refresh(), handleTap, the sync pass, a scan, a manual start or stop, or the signals.
let trimmedMentions = view.components(separatedBy: "\n")
    .map { $0.trimmingCharacters(in: .whitespaces) }
    .filter { $0.lowercased().contains("schedule") }
let expectedMentions = [
    "@State private var schedule = ScheduleStore()",
    ".onAppear { loadSchedule() }",
    "schedule: schedule.state,",
    "onReloadSchedule: loadSchedule)",
    "loadSchedule()",
    "private func loadSchedule() {",
    "schedule.load(for: worker.id) { session.worker?.id }",
    "ScheduleSummary(state: schedule.state, retry: loadSchedule)",
]
check(trimmedMentions.sorted() == expectedMentions.sorted(),
      "ContentView.swift mentions the schedule in exactly the eight expected places (got \(trimmedMentions))")
for (name, from, to) in [
    ("refresh()", "private func refresh() async {", "\n    }"),
    ("handleTap", "private func handleTap(", "\n    private func outcome("),
    ("startManual", "private func startManual() {", "private func manualStop() {"),
    ("manualStop", "private func manualStop() {", "\n    }"),
    ("scan", "private func scan() {", "\n    }"),
    ("currentRunning", "private func currentRunning() -> RunningShift? {", "\n    }"),
    ("armIfStillCurrent", "private func armIfStillCurrent() {", "\n    }"),
] {
    let body = between(view, from, to)
    check(!body.isEmpty, "found \(name) in ContentView.swift")
    check(!body.lowercased().contains("schedule"),
          "\(name) never reads, awaits or waits for the schedule (display only: a failing schedule can never delay a clock-in)")
}
check(view.contains("            .id(worker.id)\n            .environment(materials)"),
      "the TabView still carries .id(worker.id) (P3): a direct worker change recreates LogView and its store, which starts loading")
check(view.contains(".refreshable { await refresh() }"),
      "pull-to-refresh is still just refresh(): the general refresh does NOT reload the schedule (Android)")

// The triggers: tab appearance (on the stack, not the swapping Group) and the foreground.
check(view.contains("content\n            .onAppear { loadSchedule() }"),
      "the schedule loads on the Log tab's appearance, from the NavigationStack (not from the idle/running Group)")
let foreground = view.components(separatedBy: ".onChange(of: scenePhase)").last!
    .components(separatedBy: "\n        }\n    }")[0]
let fgArm = foreground.range(of: "signals.arm(for: currentRunning())")
let fgRoster = foreground.range(of: "armIfStillCurrent()")
let fgLoad = foreground.range(of: "loadSchedule()")
check(fgArm != nil && fgRoster != nil && fgLoad != nil, "the foreground handler arms, refreshes the roster and loads the schedule")
if let fgArm, let fgRoster, let fgLoad {
    check(fgArm.upperBound < fgLoad.lowerBound && fgRoster.upperBound < fgLoad.lowerBound,
          "the schedule load comes AFTER the arm and the roster pass in the foreground handler, never before")
    check(!foreground[..<fgLoad.lowerBound].hasSuffix("await "), "the foreground schedule load is not awaited")
}
let loader = between(view, "private func loadSchedule() {", "\n    }")
check(loader.contains("schedule.load(for: worker.id)") && loader.contains("session.worker?.id") && !loader.contains("await"),
      "loadSchedule() asks for THIS worker's plan, re-asks the session after the await, and awaits nothing")

// PLACEMENT. Idle: after the unresolved banner, before Recent. Running: after the notifications-off card, before help.
let idle = between(view, "private var idleList: some View {", "#if DEBUG\n            manualMockSection")
let banner = idle.range(of: "if !unresolved.isEmpty {")
let row = idle.range(of: "ScheduleSummary(state: schedule.state, retry: loadSchedule)")
let recent = idle.range(of: "Section(\"Recent\")")
check(banner != nil && row != nil && recent != nil && banner!.upperBound < row!.lowerBound && row!.upperBound < recent!.lowerBound,
      "idle: the 'Next planned assignment' section sits between the unresolved banner and Recent")
let stack = between(shiftScreen, "VStack(spacing: 24) {", ".frame(maxWidth: .infinity)")
let off = stack.range(of: "notificationsOffCard"), card = stack.range(of: "scheduleCard"), help = stack.range(of: "helpButton")
check(off != nil && card != nil && help != nil && off!.upperBound < card!.lowerBound && card!.upperBound < help!.lowerBound,
      "running: the schedule card sits after the notifications-off card and before the help button")
let shiftMentions = shiftScreen.components(separatedBy: "\n")
    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.lowercased().contains("schedule") }
check(shiftMentions.allSatisfy { !$0.contains("ScheduleStore") && !$0.contains(".load(") },
      "ShiftScreen takes the schedule's STATE and a reload closure, never the store")
check(code(source("ShiftScreen.swift")).contains("let schedule: ScheduleState") && shiftScreen.contains("ScheduleSummary(state: schedule, retry: onReloadSchedule)"),
      "ShiftScreen renders the same ScheduleSummary the idle list does")

// NOTHING ELSE KNOWS ABOUT IT: not the sync pass, not the signals, not the session, not the caches.
for name in ["Sync.swift", "ShiftSignal.swift", "ShiftSignalCenter.swift", "TapInbox.swift", "TapScanner.swift", "Auth.swift",
             "ManualStart.swift", "Zones.swift", "RosterZones.swift", "WorkerScope.swift", "AppUpdate.swift", "Telemetry.swift",
             "MaterialStore.swift", "MaterialsView.swift", "OperatorAPI.swift", "OperatorSession.swift"] {
    let text = code(source(name))
    check(!text.contains("ScheduleStore") && !text.contains("ScheduleState") && !text.contains("ScheduleAPI")
          && !text.contains("WireSchedule") && !text.contains("ScheduleSummary") && !text.contains("me/schedule"),
          "\(name) does not know the schedule exists (a plan is never an input to sync, signals, sessions or caches)")
}
check(!between(code(source("NFCTimeSheetsApp.swift")), "private func invalidateCachesIfUpdated", "\n}").lowercased().contains("schedule"),
      "decision-62's cache invalidation has no schedule line: the plan is never cached")
for (name, text) in [("ScheduleStore.swift", storeText), ("LoadGuard.swift", code(source("LoadGuard.swift"))), ("ViennaTime.swift", code(source("ViennaTime.swift")))] {
    check(!text.contains("SwiftData") && !text.contains("ModelContext") && !text.contains("UserDefaults") && !text.contains("FileManager")
          && !text.contains("@Model") && !text.contains("@AppStorage"),
          "\(name) persists nothing: the plan is in memory only and fetched fresh")
}
check(storeText.contains("Task { [weak self] in") && !storeText.contains(".task"),
      "the load is an UNSTRUCTURED Task (a cancelled .task would turn into APIFailure(0) and paint 'offline')")
check(storeText.contains("cancelled: Task.isCancelled"), "the store hands LoadGuard the task's cancellation")

// THE VIEWS CARRY NO SURFACE: the caller (a List section, the running screen's card) supplies it.
for banned in [".background(", ".listRow", "RoundedRectangle", "Capsule(", ".clipShape", ".cornerRadius", ".shadow(", "Color(", "Color.",
               ".overlay(", ".border(", "UIColor", ".foregroundColor(", ".fill(", ".stroke("] {
    check(!views.contains(banned),
          "ScheduleViews.swift has no hard-coded surface (found '\(banned)'): the Blue Hour reskin restyles the container, not these views")
}
let styles = views.components(separatedBy: ".foregroundStyle(").dropFirst().map { $0.components(separatedBy: ")")[0] }
check(!styles.isEmpty && styles.allSatisfy { [".primary", ".secondary", ".tint"].contains($0) },
      "only semantic colours (.primary / .secondary / .tint) are used (\(styles))")
for banned in ["ScheduleStore", "@Environment", "ModelContext", "ShiftAPI", "ShiftFlowAPI", "OperatorAPI", "handleTap", "TapInbox", "ShiftSignal"] {
    check(!views.contains(banned), "ScheduleViews.swift is display only: it cannot reach '\(banned)'")
}
let buttons = views.components(separatedBy: "Button").count - 1
let borderless = views.components(separatedBy: ".buttonStyle(.borderless)").count - 1
check(buttons >= 4 && buttons == borderless,
      "every Button in a List row is .borderless, so several can live in one row (\(buttons) buttons, \(borderless) borderless)")
check(views.contains("Text(verbatim: assignment.locationName)") && views.contains("Text(verbatim: assignment.note)")
      && views.contains("Text(verbatim: ScheduleTimeLine.text("),
      "building, note and time line are DATA and go through Text(verbatim:), never the catalogue")
check(!views.contains("? Text(") && !views.contains("Text(offline ?") && !views.contains("Text(showAll ?") && !views.contains("Button(showAll ?"),
      "no ternary of two string literals (it picks the verbatim initialiser and ships English, TASK-298)")

// ---------------------------------------------------------------------------------
// 6. THE STRINGS: both languages, the exact keys, and the German is Android's
// ---------------------------------------------------------------------------------

guard let catalogueData = FileManager.default.contents(atPath: "NFCTimeSheets/Localizable.xcstrings"),
      let catalogueRoot = try? JSONSerialization.jsonObject(with: catalogueData) as? [String: Any],
      let catalogue = catalogueRoot["strings"] as? [String: Any]
else { print("FAIL: Localizable.xcstrings unreadable"); exit(1) }

func german(_ key: String) -> String? {
    (((catalogue[key] as? [String: Any])?["localizations"] as? [String: Any])?["de"] as? [String: Any])
        .flatMap { $0["stringUnit"] as? [String: Any] }.flatMap { $0["value"] as? String }
}

// Every string the views show is a catalogue key with a German value.
let viewKeys = [
    "Next planned assignment", "View", "Close", "My schedule", "Planned · Clock in separately",
    "Loading assignments …", "No assignments planned for the next 31 days.",
    "Could not load assignments without a connection.", "Could not load assignments.", "Try again",
    "Refresh assignments", "All upcoming assignments", "Show less",
]
for key in viewKeys {
    check(views.contains("Text(\"\(key)\")") || views.contains("Button(\"\(key)\"") || views.contains("accessibilityLabel(\"\(key)\")"),
          "ScheduleViews.swift shows '\(key)' through the catalogue: Text / Button / accessibilityLabel with the literal, never Text(verbatim:)")
    check(german(key) != nil && german(key) != "", "'\(key)' has a German value in Localizable.xcstrings")
}
// ...and every literal the views pass to Text / Button / accessibilityLabel is one of them.
let literal = try! NSRegularExpression(pattern: #"(?:Text|Button|accessibilityLabel)\("([^"\\]+)""#)
for match in literal.matches(in: views, range: NSRange(views.startIndex..., in: views)) {
    let key = String(views[Range(match.range(at: 1), in: views)!])
    check(viewKeys.contains(key) && catalogue[key] != nil, "ScheduleViews.swift shows the literal '\(key)', which must be a catalogue key (both languages)")
}
check(!views.contains("Text(\"\\("), "no interpolated Text literal in ScheduleViews.swift")
check(!views.contains("Text(verbatim: \""),
      "Text(verbatim:) is for DATA only: a literal sentence there skips the catalogue and ships English on a German phone")

// The two time-line templates: read OUT OF ViennaTime.swift as text, turned into the key the compiler
// extracts (each \(...) becomes %@), and required to exist in the catalogue to the character.
let vienna = code(source("ViennaTime.swift"))
let templateLiteral = try! NSRegularExpression(pattern: #"String\(localized: "([^"]+)"\)"#)
let interpolation = try! NSRegularExpression(pattern: #"\\\([^)]*\)"#)
var templateKeys: [String] = []
for match in templateLiteral.matches(in: vienna, range: NSRange(vienna.startIndex..., in: vienna)) {
    let raw = String(vienna[Range(match.range(at: 1), in: vienna)!])
    templateKeys.append(interpolation.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "%@"))
}
check(templateKeys.sorted() == ["%@ · %@–%@", "%@, %@ – %@, %@"].sorted(),
      "ViennaTime.swift's two time-line literals extract to '%@ · %@–%@' and '%@, %@ – %@, %@' (got \(templateKeys))")
for key in templateKeys {
    check(catalogue[key] != nil, "the catalogue has the EXACT key '\(key)' (a wrong dash makes the lookup miss and ships English)")
}
// The German template, applied for real: positional, so the German could reorder.
if let deSame = german("%@ · %@–%@"), let deLong = german("%@, %@ – %@, %@") {
    let s = iso("2026-07-14T20:00:00Z"), e = iso("2026-07-15T00:00:00Z")
    check(String(format: deSame, "14.07.2026", "08:00", "12:00") == "14.07.2026 · 08:00–12:00", "the German same-day template fills in")
    check(String(format: deLong, ViennaTime.date(s, locale: deAT), ViennaTime.time(s, locale: deAT),
                 ViennaTime.date(e, locale: deAT), ViennaTime.time(e, locale: deAT)) == "14.07.2026, 22:00 – 15.07.2026, 02:00",
          "the German cross-day template fills in")
} else { check(false, "the German time-line templates exist") }

// THE GERMAN IS ANDROID'S, VERBATIM, and the English key is Android's English (positional markers aside).
func androidStrings(_ path: String) -> [String: String] {
    guard let xml = try? String(contentsOfFile: path, encoding: .utf8) else {
        check(false, "cannot read \(path) - the German of this feature is read out of it"); return [:]
    }
    var out: [String: String] = [:]
    let entry = try! NSRegularExpression(pattern: #"<string name="([^"]+)"[^>]*>([\s\S]*?)</string>"#)
    for m in entry.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)) {
        out[String(xml[Range(m.range(at: 1), in: xml)!])] = String(xml[Range(m.range(at: 2), in: xml)!])
            .replacingOccurrences(of: "\\'", with: "'").replacingOccurrences(of: "&amp;", with: "&")
    }
    return out
}
let res = "../android/app/src/main/res"
let androidDe = androidStrings("\(res)/values/strings.xml")          // default resources ARE German
let androidEn = androidStrings("\(res)/values-en/strings.xml")
func nonPositional(_ s: String) -> String {
    s.replacingOccurrences(of: #"%\d+\$s"#, with: "%@", options: .regularExpression).replacingOccurrences(of: "%s", with: "%@")
}
func positional(_ s: String) -> String {
    s.replacingOccurrences(of: #"%(\d+)\$s"#, with: "%$1\\$@", options: .regularExpression).replacingOccurrences(of: "%s", with: "%@")
}
for (name, key) in [
    ("worker_planned", "Next planned assignment"), ("worker_show", "View"), ("worker_hide", "Close"),
    ("schedule_title", "My schedule"), ("worker_schedule_note", "Planned · Clock in separately"),
    ("schedule_loading", "Loading assignments …"), ("schedule_empty", "No assignments planned for the next 31 days."),
    ("schedule_offline", "Could not load assignments without a connection."), ("schedule_error", "Could not load assignments."),
    ("schedule_retry", "Try again"), ("schedule_refresh", "Refresh assignments"),
    ("schedule_more", "All upcoming assignments"), ("schedule_less", "Show less"),
    ("schedule_same_day", "%@ · %@–%@"), ("schedule_when", "%@, %@ – %@, %@"),
] {
    guard let de = androidDe[name], let en = androidEn[name] else { check(false, "Android has string '\(name)'"); continue }
    check(nonPositional(en) == key, "the iOS key for Android's \(name) is Android's English: '\(nonPositional(en))' vs '\(key)'")
    check(german(key) == positional(de), "the German for '\(key)' is Android's \(name), verbatim: '\(german(key) ?? "nil")' vs '\(positional(de))'")
}
check(!(try! String(contentsOfFile: "NFCTimeSheets/Localizable.xcstrings", encoding: .utf8)).contains("Gebäude"),
      "buildings are 'Objekt', never 'Gebäude'")

if failed { exit(1) }
print("schedule-check: OK")
