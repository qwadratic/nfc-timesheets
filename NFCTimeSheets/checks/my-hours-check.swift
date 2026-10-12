// Runnable check: "My hours", the worker's last 60 days as the SERVER has them (TASK-365.8, iOS P7,
// decision-83). Ported from Android at 60f6886 (TimeSheetViewModel.loadMyHours, TimeSheetApp.kt
// MyHoursScreen / myHoursStatusRes, TASK-189).
//
//   cd NFCTimeSheets && ./checks/run.sh          (or, on its own:)
//   cat NFCTimeSheets/Branding.swift NFCTimeSheets/TagLink.swift NFCTimeSheets/API.swift \
//     NFCTimeSheets/WorkerScope.swift NFCTimeSheets/LoadGuard.swift NFCTimeSheets/ViennaTime.swift \
//     NFCTimeSheets/MyHours.swift checks/my-hours-check.swift > /tmp/my-hours-check.swift \
//     && swift /tmp/my-hours-check.swift
//
// WHAT THE FEATURE IS: Settings > "My hours" pushes a read-only list of GET /shifts/mine?since=now-60d,
// fetched on EVERY entry and never cached: loading / offline + Refresh / error + Refresh / empty / rows.
// A row is the building, the status word, "Manual" when either half was manual, the date, the start,
// the end or "No end yet", and the duration - in Europe/Vienna, never a rate, never a total.
//
// WHAT THIS CHECK GUARDS, in five parts, because each one is a way the screen would quietly mislead:
//   1. THE STATUS WORD. Android's `myHoursStatusRes` order: no end time FIRST (a running shift can
//      never read as anything else, whatever flags it carries), then needs-resolution, then
//      corrected, else closed. Duration is omitted - not zero - for the running row.
//   2. THE WIRE AND THE WINDOW. A real server row (extra keys and all) decodes; `since` is exactly
//      60 days before the injected clock; the request is GET /shifts/mine with a `since` and no worker id.
//   3. VIENNA TIME. The same instants read the same in Los Angeles, Auckland, UTC and Vienna, across both
//      DST changes: the worker reads the SAME shift on the admin board.
//   4. THE STORE, run for real with an injected fetch: the answer, the drop of the old list on a
//      reload, a stale answer, a worker change (B never sees A's hours, not for a frame), a
//      sign-out, a cancel, offline = status 0 and nothing else, a 401 reads as nothing, and a new
//      entry is a new fetch (nothing is cached).
//   5. THE WIRING, read as text: read-only (no total, no rate, no write, no storage), the Settings
//      row, the one fetch, no surface of its own, and BOTH languages with Android's German verbatim.
//
// WHAT THIS CANNOT PIN: that the rows look right, that VoiceOver reads a row as one element, that a
// push from Settings fires `.task` on every entry. Those need a worker session on a device or
// simulator (TASK-365.22 is the rig that signs one in).
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
func inOrder(_ s: String, _ needles: [String]) -> Bool {
    var from = s.startIndex
    for needle in needles {
        guard let r = s.range(of: needle, range: from..<s.endIndex) else { return false }
        from = r.upperBound
    }
    return true
}
func count(_ s: String, _ needle: String) -> Int { s.components(separatedBy: needle).count - 1 }
func iso(_ s: String) -> Date { Wire.date(from: s)! }

// ---------------------------------------------------------------------------------
// 1. THE STATUS WORD
// ---------------------------------------------------------------------------------

func shift(_ id: Int, start: String = "2026-09-01T06:00:00Z", end: String? = "2026-09-01T10:30:00Z",
           autoClosed: Bool = false, corrected: String? = nil, manualStart: Bool? = nil, manualClose: Bool? = nil,
           name: String? = "Musterhaus Wien 3") -> WireShift {
    WireShift(id: id, workerId: 7, locationId: "0b9e5a44-3c1d-4f60-8a77-2d9e1c3b5f10",
              startTime: iso(start), endTime: end.map(iso), autoClosed: autoClosed,
              correctedAt: corrected.map(iso), manualStart: manualStart, manualClose: manualClose,
              clientUuid: "u-\(id)", locationSlug: nil, locationName: name)
}

check(MyHours.status(of: shift(1)) == .closed, "an ordinary finished shift is Closed")
check(MyHours.status(of: shift(2, end: nil)) == .running, "no end time is running")
check(MyHours.status(of: shift(3, autoClosed: true)) == .autoClosed,
      "closed by the timer and nobody has fixed it is Auto-closed")
check(MyHours.status(of: shift(4, autoClosed: true, corrected: "2026-09-02T08:00:00Z")) == .corrected,
      "closed by the timer and then corrected is Corrected")
check(MyHours.status(of: shift(5, corrected: "2026-09-02T08:00:00Z")) == .corrected,
      "a correction stamp alone (a manual stop: the server stamps corrected_at in the same update) is Corrected")
// THE ORDER (Android: end_time-null is checked FIRST). A running shift is never anything else.
check(MyHours.status(of: shift(6, end: nil, autoClosed: true)) == .running,
      "no end time wins over auto-closed: a running shift can never fall into another branch")
check(MyHours.status(of: shift(7, end: nil, autoClosed: true, corrected: "2026-09-02T08:00:00Z")) == .running,
      "...and over corrected")
// needs-resolution is checked BEFORE corrected, but the two are exclusive by construction
// (needsResolution = autoClosed && correctedAt == nil), so autoClosed + corrected is Corrected.
check(MyHours.status(of: shift(8, autoClosed: true, corrected: "2026-09-02T08:00:00Z")) != .autoClosed,
      "a corrected auto-closed shift no longer says Auto-closed")

// ROWS. Building, manual, duration.
let closedRow = MyHours.row(from: shift(10))
check(closedRow.building == "Musterhaus Wien 3" && closedRow.id == 10 && closedRow.status == .closed,
      "a row carries the building name, the id and the status")
check(closedRow.duration == 4.5 * 3600, "the duration of a finished shift is end - start (4h 30m): \(String(describing: closedRow.duration))")
let openRow = MyHours.row(from: shift(11, end: nil))
check(openRow.duration == nil && openRow.end == nil,
      "the running row has NO duration and no end - omitted, not zero, not a made-up 'now'")
check(MyHours.row(from: shift(12, name: nil)).building == nil,
      "no location_name stays nil (the screen says 'Unknown location'; this file never invents a name)")
check(MyHours.row(from: shift(13)).manual == false
      && MyHours.row(from: shift(14, manualStart: false, manualClose: false)).manual == false,
      "a tapped shift is not manual (absent or false on both halves)")
check(MyHours.row(from: shift(15, manualStart: true)).manual && MyHours.row(from: shift(16, manualClose: true)).manual
      && MyHours.row(from: shift(17, manualStart: true, manualClose: true)).manual,
      "either manual half makes the row Manual (decision-56 section 5)")

// ---------------------------------------------------------------------------------
// 2. THE WIRE AND THE WINDOW
// ---------------------------------------------------------------------------------

// A row exactly as `SELECT s.*..., l.slug AS location_slug, l.name AS location_name, z.name AS zone_name`
// sends it (server/routes/app.js myShifts), extra keys and all.
let serverRow = """
{"id":4711,"worker_id":7,"location_id":"0b9e5a44-3c1d-4f60-8a77-2d9e1c3b5f10","start_zone_id":"11111111-1111-4111-8111-111111111111",
 "end_zone_id":null,"start_time":"2026-09-01T06:00:00.000Z","end_time":"2026-09-01T10:30:00.000Z","auto_closed":false,
 "corrected_at":"2026-09-01T10:30:00.500Z","manual_start":false,"manual_close":true,"manual_note":"tag broken","client_uuid":"3f2a1c7e-0b64-4c1a-9e2d-5a7b8c9d0e11",
 "location_interval_seconds":0,"proof_of_work_required":false,"proof_id":null,
 "location_slug":"musterhaus-wien-3","location_name":"Musterhaus Wien 3","zone_name":"Haupteingang"}
"""
let runningServerRow = """
{"id":4712,"worker_id":7,"location_id":"0b9e5a44-3c1d-4f60-8a77-2d9e1c3b5f10","start_zone_id":null,"end_zone_id":null,
 "start_time":"2026-09-02T05:00:00Z","end_time":null,"auto_closed":false,"corrected_at":null,"client_uuid":"u-run",
 "location_slug":"musterhaus-wien-3","location_name":"Musterhaus Wien 3","zone_name":null}
"""
func decodeShifts(_ json: String) throws -> [WireShift] {
    try Wire.decoder.decode(WireShiftListEnvelope.self, from: Data(json.utf8)).shifts
}
let decoded = (try? decodeShifts("{\"shifts\":[\(runningServerRow),\(serverRow)]}")) ?? []
check(decoded.count == 2 && decoded.map(\.id) == [4712, 4711],
      "a real /shifts/mine body decodes and keeps the server's order (newest first)")
if decoded.count == 2 {
    let rows = decoded.map(MyHours.row(from:))
    check(rows[0].status == .running && rows[0].duration == nil && rows[0].manual == false,
          "a running server row (end_time null, no manual keys at all) reads as running with no duration")
    check(rows[1].status == .corrected && rows[1].manual && rows[1].building == "Musterhaus Wien 3",
          "...and a manual stop reads Corrected + Manual with the BUILDING's name, not the zone's")
    check(rows[1].start == iso("2026-09-01T06:00:00Z") && rows[1].end == iso("2026-09-01T10:30:00Z"),
          "'.000Z' timestamps decode to the right instants")
}
check((try? decodeShifts("{\"shifts\":[]}"))?.isEmpty == true, "an empty list decodes to an empty list (the empty sentence)")
// STRICT: one row this build cannot read fails the list - never a silently shorter list of somebody's hours.
check((try? decodeShifts("{\"shifts\":[\(serverRow),{\"id\":\"x\"}]}")) == nil,
      "one unreadable row throws: the screen says 'could not be loaded', never a shorter list")
check((try? decodeShifts("{}")) == nil, "a body without 'shifts' throws")

// THE WINDOW: exactly 60 days before the (injected) now, nothing else.
check(MyHours.windowDays == 60 && MyHours.window == 5_184_000, "the window is 60 days (Android 60 * 86_400 s)")
let now0 = iso("2026-10-12T10:00:00Z")
check(MyHours.since(now: now0) == iso("2026-08-13T10:00:00Z"), "since is now - 60 days exactly")

// THE REQUEST: GET /shifts/mine?since=, the session's worker, no ?worker=.
let apiSource = source("API.swift")
let mineText = code(between(apiSource, "static func mine(since: Date) async throws -> [WireShift] {", "\n    }"))
check(mineText.contains("apiGet(\"/shifts/mine\", query: [\"since\": Wire.string(from: since)])") && !mineText.contains("worker"),
      "ShiftAPI.mine is apiGet(\"/shifts/mine\", query: [\"since\": ...]) and takes no worker id (decision-22)")
check(!source("OperatorAPI.swift").contains("shifts/mine"), "the operator's client never asks for a worker's hours")

// ---------------------------------------------------------------------------------
// 3. VIENNA TIME
// ---------------------------------------------------------------------------------

let enGB = Locale(identifier: "en_GB")
let deAT = Locale(identifier: "de_AT")
// (name, instant, en_GB date, de_AT date, time)
let viennaCases: [(String, String, String, String, String)] = [
    ("winter, 08:00 CET", "2026-01-14T07:00:00Z", "14 Jan 2026", "14.01.2026", "08:00"),
    ("summer, 08:00 CEST (one hour earlier in UTC)", "2026-07-14T06:00:00Z", "14 Jul 2026", "14.07.2026", "08:00"),
    ("23:30 Vienna is still the 14th in UTC and Los Angeles, and already the 15th here", "2026-07-14T21:30:00Z", "14 Jul 2026", "14.07.2026", "23:30"),
    ("00:30 Vienna on the 15th is the 14th in UTC", "2026-07-14T22:30:00Z", "15 Jul 2026", "15.07.2026", "00:30"),
    ("DST spring forward: 03:30 CEST, the 02:00 hour never existed", "2026-03-29T01:30:00Z", "29 Mar 2026", "29.03.2026", "03:30"),
    ("DST fall back: 02:30 CET (the second one)", "2026-10-25T01:30:00Z", "25 Oct 2026", "25.10.2026", "02:30"),
]
for deviceZone in ["America/Los_Angeles", "Pacific/Auckland", "UTC", "Asia/Kolkata", "Europe/Vienna"] {
    NSTimeZone.default = TimeZone(identifier: deviceZone)!
    let probe = iso("2026-07-14T12:00:00Z"), wanted = TimeZone(identifier: deviceZone)!.secondsFromGMT(for: probe)
    check(NSTimeZone.default.secondsFromGMT(for: probe) == wanted, "the check really set the device zone to \(deviceZone)")
    for (name, instant, english, german, time) in viennaCases {
        let at = iso(instant)
        check(ViennaTime.date(at, locale: enGB) == english, "[\(deviceZone)] en_GB date: \(name): got '\(ViennaTime.date(at, locale: enGB))'")
        check(ViennaTime.date(at, locale: deAT) == german, "[\(deviceZone)] de_AT date: \(name): got '\(ViennaTime.date(at, locale: deAT))'")
        check(ViennaTime.time(at, locale: enGB) == time && ViennaTime.time(at, locale: deAT) == time,
              "[\(deviceZone)] time: \(name): got '\(ViennaTime.time(at, locale: enGB))'")
    }
}
NSTimeZone.default = TimeZone(identifier: "UTC")!

// ---------------------------------------------------------------------------------
// 4. THE STORE, for real, with an injected fetch
// ---------------------------------------------------------------------------------

let hoursA = [shift(101, name: "A building"), shift(102, end: nil, name: "A building 2")]
let hoursB = [shift(201, name: "B building")]
let rowsA = hoursA.map(MyHours.row(from:))
let rowsB = hoursB.map(MyHours.row(from:))

/// A server the check controls: each fetch parks until the check answers it, and remembers `since`.
@MainActor final class FakeServer {
    private(set) var calls = 0
    private(set) var sinces: [Date] = []
    private var pending: [CheckedContinuation<[WireShift], Error>] = []
    func fetch(since: Date) async throws -> [WireShift] {
        calls += 1
        sinces.append(since)
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func answer(_ index: Int, _ result: Result<[WireShift], Error>) { pending[index].resume(with: result) }
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
    // Initial and the basic round trip, with the window taken from the injected clock.
    do {
        let server = FakeServer(), session = FakeSession(7)
        let store = MyHoursStore(fetch: server.fetch, now: { now0 })
        check(store.state == .loading, "a new store is loading")
        let task = store.load(for: 7) { session.worker }
        check(task != nil && store.state == .loading && server.calls == 0,
              "load returns at once: the request has not even started when it returns")
        await server.waitForCalls(1)
        check(server.sinces.first == iso("2026-08-13T10:00:00Z"), "the request asks since = now - 60 days: \(server.sinces)")
        server.answer(0, .success(hoursA))
        await task?.value
        check(store.state == .loaded(rowsA), "the answer is published as rows: \(store.state)")

        // A second entry is a second fetch and drops the list first: nothing is cached.
        let again = store.load(for: 7) { session.worker }
        check(store.state == .loading, "a reload drops the previous list at once - nothing is cached")
        await server.waitForCalls(2)
        server.answer(1, .success([]))
        await again?.value
        check(store.state == .loaded([]) && server.calls == 2, "...and shows the new answer, one fetch per entry: \(store.state)")
    }
    // A brand-new store (a new entry to the screen) starts from loading and asks again: a fresh screen has no memory.
    do {
        let server = FakeServer(), session = FakeSession(7)
        let first = MyHoursStore(fetch: server.fetch, now: { now0 })
        let t1 = first.load(for: 7) { session.worker }
        await server.waitForCalls(1)
        server.answer(0, .success(hoursA)); await t1?.value
        let second = MyHoursStore(fetch: server.fetch, now: { now0 })
        check(second.state == .loading, "a new entry starts from .loading, not from the last visit's list")
        _ = second.load(for: 7) { session.worker }
        await server.waitForCalls(2)
        check(server.calls == 2, "...and asks the server again")
        server.answer(1, .failure(APIFailure(status: 0, code: "network")))
    }

    // A STALE answer does not overwrite a newer one, in both arrival orders.
    for newerFirst in [true, false] {
        let server = FakeServer(), session = FakeSession(7)
        let store = MyHoursStore(fetch: server.fetch, now: { now0 })
        let first = store.load(for: 7) { session.worker }
        await server.waitForCalls(1)
        let second = store.load(for: 7) { session.worker }
        await server.waitForCalls(2)
        if newerFirst {
            server.answer(1, .success(hoursB)); await second?.value
            server.answer(0, .success(hoursA)); await first?.value
        } else {
            server.answer(0, .success(hoursA)); await first?.value
            server.answer(1, .success(hoursB)); await second?.value
        }
        check(store.state == .loaded(rowsB),
              "a slow STALE answer never overwrites the newer one (newer answered \(newerFirst ? "first" : "last")): \(store.state)")
    }

    // Failures: offline is status 0 and NOTHING else.
    let failures: [(String, Error, MyHoursState?)] = [
        ("status 0 (no answer) is OFFLINE", APIFailure(status: 0, code: "network"), .failed(offline: true)),
        ("a 400 (since rejected) is the generic error", APIFailure(status: 400, code: "invalid_timestamp"), .failed(offline: false)),
        ("a 422 timestamp_in_future is the generic error", APIFailure(status: 422, code: "timestamp_in_future"), .failed(offline: false)),
        ("500 is the generic error", APIFailure(status: 500, code: "http_500"), .failed(offline: false)),
        ("503 is the generic error", APIFailure(status: 503, code: "http_503"), .failed(offline: false)),
        ("a body this build cannot read is the generic error", DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "x")), .failed(offline: false)),
        ("any other error is the generic error", URLError(.timedOut), .failed(offline: false)),
        ("a 401 renders NOTHING (the app is signing out), the state stays loading", APIFailure(status: 401, code: "unauthorized"), nil),
    ]
    for (name, error, expected) in failures {
        let server = FakeServer(), session = FakeSession(7)
        let store = MyHoursStore(fetch: server.fetch, now: { now0 })
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
        let store = MyHoursStore(fetch: server.fetch, now: { now0 })
        let task = store.load(for: 7) { session.worker }
        await server.waitForCalls(1)
        store.cancel()                                                        // the screen went away
        server.answer(0, .failure(APIFailure(status: 0, code: "network")))   // what send() makes of the cancel
        await task?.value
        check(store.state == .loading, "a CANCELLED request does not paint the offline sentence: \(store.state)")
    }
    do {
        let server = FakeServer(), session = FakeSession(7)
        let store = MyHoursStore(fetch: server.fetch, now: { now0 })
        let task = store.load(for: 7) { session.worker }
        await server.waitForCalls(1)
        store.cancel()
        server.answer(0, .success(hoursA))
        await task?.value
        check(store.state == .loading, "...and a cancelled request that DID get an answer does not publish it either: \(store.state)")
    }

    // IDENTITY. Sign-out in flight: nothing is published.
    do {
        let server = FakeServer(), session = FakeSession(7)
        let store = MyHoursStore(fetch: server.fetch, now: { now0 })
        let task = store.load(for: 7) { session.worker }
        await server.waitForCalls(1)
        session.worker = nil                                                  // A signed out
        server.answer(0, .success(hoursA)); await task?.value
        check(store.state == .loading, "an answer that lands after sign-out is dropped: \(store.state)")
    }
    // ...and a worker change in flight, on the same store: B never sees A's hours, not for a frame.
    do {
        let server = FakeServer(), session = FakeSession(7)
        let store = MyHoursStore(fetch: server.fetch, now: { now0 })
        let forA = store.load(for: 7) { session.worker }
        await server.waitForCalls(1)
        server.answer(0, .success(hoursA)); await forA?.value
        check(store.state == .loaded(rowsA), "A sees A's hours")

        session.worker = 9                                                    // B signs in on the same phone
        let forB = store.load(for: 9) { session.worker }
        check(store.state == .loading, "B's load STARTS LOADING: A's hours are not shown to B for a single frame (\(store.state))")
        await server.waitForCalls(2)
        server.answer(1, .success(hoursB)); await forB?.value
        check(store.state == .loaded(rowsB), "B sees B's hours: \(store.state)")
    }
    do {
        let server = FakeServer(), session = FakeSession(7)
        let store = MyHoursStore(fetch: server.fetch, now: { now0 })
        let forA = store.load(for: 7) { session.worker }
        await server.waitForCalls(1)
        session.worker = 9                                                    // replaced while A's request is out
        let forB = store.load(for: 9) { session.worker }
        await server.waitForCalls(2)
        server.answer(1, .success(hoursB)); await forB?.value
        server.answer(0, .success(hoursA)); await forA?.value                // A's late answer
        check(store.state == .loaded(rowsB), "A's late answer never replaces B's: \(store.state)")
    }
    // A load for somebody who does not hold the session is a no-op.
    do {
        let server = FakeServer(), session = FakeSession(9)
        let store = MyHoursStore(fetch: server.fetch, now: { now0 })
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

let logic = code(source("MyHours.swift"))
let screen = code(source("MyHoursView.swift"))
let content = code(source("ContentView.swift"))

// READ-ONLY and NEVER CACHED: not one line of persistence, and no write verb, in either file.
for (name, text) in [("MyHours.swift", logic), ("MyHoursView.swift", screen)] {
    check(!text.contains("SwiftData") && !text.contains("ModelContext") && !text.contains("@Query") && !text.contains("@Model")
          && !text.contains("UserDefaults") && !text.contains("@AppStorage") && !text.contains("FileManager")
          && !text.contains("@SceneStorage") && !text.contains("context.save"),
          "\(name) persists nothing: the list is in memory only and fetched fresh on every entry")
    check(!text.contains("ShiftAPI.open") && !text.contains("ShiftAPI.close") && !text.contains("ShiftAPI.resolve")
          && !text.contains("ShiftFlowAPI") && !text.contains("apiPost") && !text.contains("syncPending")
          && !text.contains("handleTap") && !text.contains("TapInbox") && !text.contains("ShiftSignal"),
          "\(name) writes nothing and reaches no tap, sync or signal: this screen is read-only about the past")
}
// NO TOTAL, NO RATE, NO AMOUNT, anywhere.
for pattern in [#"\.reduce\("#, #"\bsum\b"#, #"\.sum\b"#, #"(?i)\btotal"#, #"(?i)hourly"#, #"(?i)\brate\b"#, "\u{20AC}", #"\bEUR\b"#,
                #"(?i)payroll"#, #"(?i)\bcost"#, #"(?i)\bamount"#] {
    let regex = try! NSRegularExpression(pattern: pattern)
    for (name, text) in [("MyHours.swift", logic), ("MyHoursView.swift", screen)] {
        check(regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil,
              "\(name) has no total, no rate and no amount (matched /\(pattern)/): Android's screen is deliberately narrower than History")
    }
}
// THE ONE FETCH: exactly the migration's client call, through the guard, never from refresh() / the tap path.
check(count(logic, "ShiftAPI.mine(since: since)") == 1 && count(content, "ShiftAPI.mine") == 0 && count(screen, "ShiftAPI") == 0,
      "ShiftAPI.mine(since:) is called in exactly one place: the store's default fetch (the screen and LogView never call the API)")
check(logic.contains("let ticket = loadGuard.begin(for: workerId)") && logic.contains("loadGuard.accepts(ticket, sessionWorkerId: session, cancelled: cancelled)")
      && logic.contains("cancelled: Task.isCancelled") && logic.contains("Task { [weak self] in") && !logic.contains(".task"),
      "the load goes through LoadGuard in an unstructured Task that hands over its cancellation")
check(logic.contains("guard WorkerScope.isCurrent(workerId, session: session()) else { return nil }"),
      "a load for somebody who does not hold the session is a no-op")
check(logic.contains("state = .loading\n") && inOrder(logic, ["let ticket = loadGuard.begin(for: workerId)", "state = .loading", "let task = Task"]),
      "the previous list is dropped (.loading) BEFORE the request starts")
let fetchDefault = between(logic, "init(fetch: @escaping (Date) async throws -> [WireShift] =", "now: @escaping () -> Date = { .now }) {")
check(fetchDefault.contains("{ since in try await ShiftAPI.mine(since: since) }"),
      "the store's default fetch is ShiftAPI.mine(since:), with the window's `since`")
check(logic.contains("let since = MyHours.since(now: now())"), "`since` is taken from the clock at load time")

// THE VIEW: states, window sentence, refresh, and no surface.
check(inOrder(screen, ["Your shifts from the last 60 days, as stored on the server.", "switch store.state {", "case .loading:",
                       "case .failed(let offline):", "case .loaded(let rows):", "No shifts in this period.", "MyHoursRowView(row: $0)"]),
      "the screen is: the window sentence, then loading / failed / loaded (the empty sentence, or the rows)")
check(screen.contains(".task { load() }") && screen.contains(".onDisappear { store.cancel() }")
      && screen.contains("@State private var store = MyHoursStore()"),
      "every entry asks (.task), the store is the screen's own @State, and leaving the screen cancels the request")
check(screen.contains("Button(\"Refresh\", action: retry)") && screen.contains(".buttonStyle(.bordered)")
      && screen.contains("MyHoursFailure(offline: offline, retry: load)"),
      "the failure state has a bordered Refresh that asks again")
check(inOrder(screen, ["if offline {", "No connection. Your hours can't be loaded right now.", "} else {", "Your hours could not be loaded."]),
      "offline and generic are two different sentences, offline only for status 0")
check(screen.contains("AccessibilityNotification.Announcement(spoken).post()") && screen.contains("accessibilitySpeechAnnouncementPriority = .high"),
      "a failure is announced when it appears (Android: an assertive live region)")
check(inOrder(screen, ["Text(verbatim: building)", "Text(\"Unknown location\")"]),
      "the building is data (verbatim), else 'Unknown location'")
check(inOrder(screen, ["if row.manual { pill(\"Manual\", .blue) }", "statusPill", "Text(\"Date: \\(ViennaTime.date(row.start))\")",
                       "Text(\"Start: \\(ViennaTime.time(row.start))\")", "Text(\"End: \\(ViennaTime.time(end))\")", "Text(\"No end yet\")",
                       "Text(\"Duration: \\(fmtDur(duration))\")"]),
      "a row is: building, Manual, the status word, date, start, end or 'No end yet', duration - in Vienna time")
check(screen.contains("if let duration = row.duration {"), "the duration line exists only for a row that has one")
let statusPill = between(screen, "@ViewBuilder private var statusPill: some View {", "\n    }")
check(inOrder(statusPill, ["case .running: pill(\"In progress\", .orange)", "case .autoClosed: pill(\"Auto-closed\", .red)",
                           "case .corrected: pill(\"Corrected\", .purple)", "case .closed: pill(\"Closed\", .secondary)"]),
      "the four status words are ShiftRow's pills (In progress / Auto-closed / Corrected) plus 'Closed'")
for banned in [".background(", ".listRow", "RoundedRectangle", "Capsule(", ".clipShape", ".cornerRadius", ".shadow(", "Color(", "Color.",
               ".overlay(", ".border(", "UIColor", ".foregroundColor(", ".fill(", ".stroke("] {
    check(!screen.contains(banned),
          "MyHoursView.swift has no hard-coded surface (found '\(banned)'): the Blue Hour reskin restyles the container and the shared pill")
}
let styles = screen.components(separatedBy: ".foregroundStyle(").dropFirst().map { $0.components(separatedBy: ")")[0] }
check(!styles.isEmpty && styles.allSatisfy { [".secondary"].contains($0) }, "only the semantic secondary colour is used here (\(styles))")
check(!screen.contains("? Text(") && !screen.contains("Text(offline ?") && !screen.contains("? \"") ,
      "no ternary of two string literals (the verbatim initialiser ships English, TASK-298)")

// THE SETTINGS ROW: one, in the identity section, pushing the screen for THIS worker.
let settings = between(content, "struct SettingsView: View {", "\n}\n")
check(count(settings, "NavigationLink(\"My hours\") { MyHoursView(worker: worker) }") == 1
      && inOrder(settings, ["Section(\"Signed in as\") {", "LabeledContent(\"Name\", value: worker.name)", "NavigationLink(\"My hours\")", "Hours, locations and payroll are managed"]),
      "Settings has exactly one 'My hours' row, in the identity section, built for the signed-in worker")
check(count(content, "MyHoursView(") == 1, "ContentView.swift builds the screen in exactly one place")
// NOTHING ELSE KNOWS ABOUT IT: not the tap path, the sync pass, the signals, the session, the caches.
for (name, from, to) in [
    ("refresh()", "private func refresh() async {", "\n    }"),
    ("handleTap", "private func handleTap(", "\n    private func outcome("),
    ("startManual", "private func startManual() {", "private func manualStop() {"),
    ("finishManualStop", "private func finishManualStop() {", "\n    #if DEBUG"),
    ("prepareCompletion", "private func prepareCompletion(", "\n    }"),
    ("scan", "private func scan() {", "\n    }"),
    ("currentRunning", "private func currentRunning() -> RunningShift? {", "\n    }"),
] {
    let body = between(content, from, to)
    check(!body.isEmpty, "found \(name) in ContentView.swift")
    check(!body.contains("MyHours"), "\(name) never reads, awaits or waits for My hours (display only)")
}
for name in ["Sync.swift", "ShiftSignal.swift", "ShiftSignalCenter.swift", "TapInbox.swift", "TapScanner.swift", "Auth.swift",
             "ManualStart.swift", "Zones.swift", "RosterZones.swift", "WorkerScope.swift", "AppUpdate.swift", "Telemetry.swift",
             "MaterialStore.swift", "MaterialsView.swift", "OperatorAPI.swift", "OperatorSession.swift", "ScheduleStore.swift",
             "PendingWork.swift", "PendingNotice.swift", "NFCTimeSheetsApp.swift"] {
    check(!code(source(name)).contains("MyHours"), "\(name) does not know My hours exists")
}
check(!between(code(source("NFCTimeSheetsApp.swift")), "private func invalidateCachesIfUpdated", "\n}").contains("MyHours"),
      "decision-62's cache invalidation has no My hours line: there is no cache")

// STRINGS: both languages, Android's German verbatim.
let catalogue = try! JSONSerialization.jsonObject(with: Data(source("Localizable.xcstrings").utf8)) as! [String: Any]
let strings = catalogue["strings"] as! [String: Any]
func german(_ key: String) -> String? {
    (((((strings[key] as? [String: Any])?["localizations"] as? [String: Any])?["de"]) as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
}
func androidString(_ name: String) -> String? {
    guard let xml = try? String(contentsOfFile: "../android/app/src/main/res/values/strings.xml", encoding: .utf8) else { return nil }
    let open = "<string name=\"\(name)\">"
    guard let start = xml.range(of: open), let end = xml.range(of: "</string>", range: start.upperBound..<xml.endIndex) else { return nil }
    return String(xml[start.upperBound..<end.lowerBound]).replacingOccurrences(of: "\\'", with: "'")
}
let catalogue60: [(String, String)] = [
    ("My hours", "myhours_open"),
    ("Your shifts from the last 60 days, as stored on the server.", "myhours_window"),
    ("No shifts in this period.", "myhours_empty"),
    ("No connection. Your hours can't be loaded right now.", "myhours_offline"),
    ("Your hours could not be loaded.", "myhours_error"),
    ("Date: %@", "myhours_date"),
    ("Start: %@", "myhours_start"),
    ("End: %@", "myhours_end"),
    ("No end yet", "myhours_end_open"),
    ("Duration: %@", "myhours_duration"),
    ("Closed", "status_closed"),
]
for (key, androidName) in catalogue60 {
    let expected = androidString(androidName)?.replacingOccurrences(of: "%1$s", with: "%@")
    check(german(key) != nil && german(key) == expected,
          "'\(key)' is in the catalogue with Android's German '\(expected ?? "?")' verbatim (\(androidName)); got '\(german(key) ?? "nil")'")
}
for key in ["In progress", "Auto-closed", "Corrected", "Manual", "Refresh", "Unknown location"] {
    check(german(key) != nil, "the reused key '\(key)' is in the catalogue")
}
check(german("Refresh") == androidString("log_refresh"), "'Refresh' is Android's log_refresh verbatim")
check(german("Closed") == "Abgeschlossen" && german("Date: %@") == "Datum: %@" && german("Start: %@") == "Beginn: %@"
      && german("End: %@") == "Ende: %@" && german("Duration: %@") == "Dauer: %@" && german("No end yet") == "Noch kein Ende",
      "the labels read exactly as the worker's German vocabulary expects")

if failed { exit(1) }
print("my-hours-check: OK")
