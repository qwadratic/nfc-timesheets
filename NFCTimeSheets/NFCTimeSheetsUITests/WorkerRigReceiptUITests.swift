//
//  WorkerRigReceiptUITests.swift
//  NFCTimeSheetsUITests
//
//  P7 (TASK-365.8, decision-83) DRIVEN: the "Shift finished" receipt and the one-shot
//  ring-then-check. My hours is WorkerRigMyHoursUITests. The phone half is here; the server half
//  (rows, wire, the preference the motion writes) is the driver's: ops/ios-rig/walk.sh p7.
//
//  TAPS are the DEBUG-only `--ts-demo-tap <zone uuid>` launch argument (a simulator has no NFC
//  radio); a cold launch is the only moment one can be injected, so "a tap while the receipt is
//  up" is a relaunch inside the two minutes, not a tap into a running app - said where it matters.
//
//  SLOW ANSWERS are how the motion is made observable. The ring plays at the moment the server
//  answers; an unheld answer lands a few tens of milliseconds after launch, before the first
//  picture of a walk can be taken. The rig front's `hold_ms` fault holds the ANSWER (the server has
//  already computed it: the row exists at once) for a few seconds, so the walk takes pictures
//  BEFORE the answer, at the answer and after it. The motion itself is `WorkerRigMotionProbe`.
//
//  The server half asks, among other things, what `ConfirmationMotion.claim` wrote into the app's
//  preferences (`worker-motion.clock-in` / `.clock-out`): the identity is consumed BEFORE anything
//  animates, so it is also the proof for the paths where nothing is drawn.
//
//  THE 45 SECONDS. "Second launch, tab return and resume do not replay" is only a statement about
//  the CONSUMED identity while the event is still under 45 s old - after that the age window alone
//  would hide a replay. Each phase writes a mark with its last frame's time and the driver checks
//  it against the start of the event; a phase later than that is reported as not discriminating.
//

import UIKit
import XCTest

final class WorkerRigReceiptUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "notifications") { alert in
            for label in ["Allow", "Allow While Using App", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
    }

    // MARK: - helpers

    /// Signs A in (server must be up) and ends on the idle screen.
    private func signedInIdle() -> XCUIApplication {
        let app = Rig.launch()
        ensureSignedIn(app, as: "A")
        waitForIdle(app)
        sleep(2)
        return app
    }

    /// A relaunch with a tap. The previous instance is terminated first (Rig.launch does that).
    private func tapLaunch(_ zone: String) -> XCUIApplication { Rig.launch(tap: Rig.zone(zone)) }

    private func finishWithoutTag(_ app: XCUIApplication) {
        let finish = app.buttons["Finish shift without a tag"]
        var swipes = 0
        while !finish.isHittable, swipes < 8 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(finish.waitForExistence(timeout: Rig.timeout), "the running screen's quiet finish")
        finish.tap()
        let confirm = app.buttons["Finish now"]
        XCTAssertTrue(confirm.waitForExistence(timeout: Rig.timeout), "the confirmation dialog")
        confirm.tap()
    }

    /// The system's notification prompt appears after the first clock-in of a fresh install; a picture
    /// with it in front of the card would be a false "hidden".
    private func clearPrompts() {
        sleep(1)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            dismissSystemAlerts()
            if springboard.alerts.count == 0 { break }
            sleep(1)
        }
    }

    private func receiptHeading(_ app: XCUIApplication) -> XCUIElement { app.staticTexts["Shift finished"] }

    /// The clock card: ONE accessibility element whose label is recomputed once a minute.
    private func clockCard(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS[c] %@ OR label BEGINSWITH[c] %@ OR label CONTAINS[c] %@",
            "recorded on this phone for", "Shift running for", "passed 8 hours")).firstMatch
    }

    private func line(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    /// Everything on screen that is text, as one string (evidence, not an assertion).
    private func screenText(_ app: XCUIApplication) -> String {
        app.staticTexts.allElementsBoundByIndex.filter { $0.exists }.map(\.label).joined(separator: " | ")
    }

    private func note(_ name: String, _ text: String) { MotionProbe.write(text, name: name) }

    private func clockGeometry(_ app: XCUIApplication) -> MotionProbe.Geometry? {
        let card = clockCard(app)
        guard card.waitForExistence(timeout: Rig.timeout) else { return nil }
        return MotionProbe.calibrate(app: app, block: card.frame)
    }

    private func receiptGeometry(_ app: XCUIApplication) -> MotionProbe.Geometry? {
        let heading = receiptHeading(app)
        guard heading.waitForExistence(timeout: Rig.timeout) else { return nil }
        let width = MotionProbe.screenWidth(app)
        let continueButton = app.buttons["Continue"]
        let bottom = continueButton.exists ? continueButton.frame.minY - 24 : heading.frame.maxY + 150
        let block = CGRect(x: 0, y: heading.frame.minY - 3, width: width, height: heading.frame.height + 6)
        return MotionProbe.calibrate(app: app, block: block, centerY: (heading.frame.minY + bottom) / 2)
    }

    /// One recorded stretch: the samples, the episodes, evidence on disk and the marks the driver reads.
    @discardableResult
    private func observe(_ name: String, seconds: TimeInterval, geometry: MotionProbe.Geometry,
                         keepPNGs: Bool = false) -> [MotionSample] {
        let rec = MotionProbe.record(seconds: seconds, geometry: geometry)
        let eps = MotionProbe.episodes(rec.samples)
        MotionProbe.write(MotionProbe.describe(rec.samples), name: "p7-\(name)-frames")
        if keepPNGs, !rec.kept.isEmpty {
            for (i, kept) in rec.kept.enumerated() where i == 0 || i == rec.kept.count / 2 || i == rec.kept.count - 1 {
                MotionProbe.writePNG(kept.1, name: "p7-\(name)-frame-\(i)")
            }
        }
        if let last = rec.samples.last { MotionProbe.mark("\(name)-last-frame", atEpoch: last.epoch) }
        MotionProbe.mark("\(name)-episodes-\(eps.count)", atEpoch: rec.samples.first?.epoch ?? Date().timeIntervalSince1970)
        for (i, e) in eps.enumerated() {
            MotionProbe.mark("\(name)-ring\(i)-first", atEpoch: e.first)
            MotionProbe.mark("\(name)-ring\(i)-last", atEpoch: e.last)
        }
        return rec.samples
    }

    // MARK: - #2 receipt after an online tap-in and tap-out

    /// Two shifts, in two buildings: the first leaves a row in Recent that is NOT the receipt's, so
    /// "Recent excludes the receipt's row" is a statement about a row that could have been there.
    func testP7ReceiptAfterOnlineTapInThenTapOut() throws {
        var app = signedInIdle()
        backgroundAndKill(app)

        // shift 1 at Beta: an acknowledged start, then the tap-out
        app = tapLaunch("B_VER")
        waitForRunning(app)
        clearPrompts()
        XCTAssertTrue(app.staticTexts["Shift in progress"].waitForExistence(timeout: Rig.timeout), "Beta's start is acknowledged")
        sleep(2)
        app = tapLaunch("B_VER")
        waitForIdle(app)
        XCTAssertTrue(receiptHeading(app).waitForExistence(timeout: Rig.timeout), "Beta's receipt")

        // shift 2 at Alpha (a relaunch inside the two minutes: Beta's receipt is replaced by the shift)
        app = tapLaunch("A_VER")
        waitForRunning(app)
        XCTAssertTrue(app.staticTexts["Shift in progress"].waitForExistence(timeout: Rig.timeout), "Alpha's start is acknowledged")
        sleep(62)                                   // so the duration reads 0h 1m, not 0h 0m
        app = tapLaunch("A_DEACT")                  // the second door of the building closes it
        waitForIdle(app)

        // the receipt
        XCTAssertTrue(receiptHeading(app).waitForExistence(timeout: Rig.timeout), "idle shows 'Shift finished'")
        XCTAssertTrue(app.staticTexts["Rig Haus Alpha"].exists, "it names the building")
        // the range of THIS receipt: the 'a – b' text between its heading and its Continue (Recent rows draw one too)
        let top = receiptHeading(app).frame.minY, bottom = app.buttons["Continue"].frame.minY
        let ranges = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "\\d{1,2}:\\d{2} – \\d{1,2}:\\d{2}"))
            .allElementsBoundByIndex.filter { $0.frame.minY > top && $0.frame.minY < bottom }
        XCTAssertEqual(ranges.count, 1, "the receipt shows ONE range 'a – b'")
        note("p7-receipt-online-range", ranges.first?.label ?? "(none)")
        XCTAssertTrue(app.staticTexts["0h 1m"].exists, "and the duration (the shift ran just over a minute)")
        XCTAssertTrue(app.staticTexts["Sent"].waitForExistence(timeout: 15), "the delivery line says 'Sent'")
        XCTAssertFalse(app.staticTexts["Manual"].exists || app.staticTexts["Corrected"].exists || app.staticTexts["Auto-closed"].exists,
                       "a tap start and a tap finish carry no pill")
        // the start Sections are the receipt's place: hidden while it is up
        XCTAssertFalse(app.buttons["Scan a tag"].exists, "the scan button is hidden")
        XCTAssertFalse(app.buttons["Start without a tag"].exists, "'Start without a tag' is hidden")
        XCTAssertFalse(app.staticTexts["Ready for your shift?"].exists, "the start card is replaced")
        // Recent keeps the OLDER row (Beta) and not the receipt's row (Alpha)
        XCTAssertTrue(app.staticTexts["Recent"].exists, "Recent is still there")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Rig Haus Beta")).count, 1, "Recent lists Beta once")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Rig Haus Alpha")).count, 1,
                       "Alpha is on screen ONCE: the receipt's name, not a Recent row as well")
        shot("p7-02-receipt")
        note("p7-02-receipt-text", screenText(app))
        Rig.mark("receipt-checked")

        // Continue brings the start Sections back, and the finished row joins Recent
        let cont = app.buttons["Continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: Rig.timeout) && cont.isHittable, "a full-width Continue")
        cont.tap()
        XCTAssertTrue(app.staticTexts["Ready for your shift?"].waitForExistence(timeout: Rig.timeout), "Continue returns the start card")
        XCTAssertTrue(app.buttons["Scan a tag"].exists, "scan is back")
        XCTAssertTrue(app.buttons["Start without a tag"].exists, "'Start without a tag' is back")
        XCTAssertFalse(receiptHeading(app).exists, "the receipt is gone")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Rig Haus Alpha")).count, 1,
                       "Alpha is now a Recent row")
        shot("p7-02-after-continue")
    }

    // MARK: - #3 the receipt stays past two minutes, and is not offered after a relaunch past them

    func testP7ReceiptStaysPastTwoMinutesAndIsGoneAfterARelaunch() throws {
        var app = signedInIdle()
        backgroundAndKill(app)
        app = tapLaunch("A_VER")
        waitForRunning(app)
        clearPrompts()
        XCTAssertTrue(app.staticTexts["Shift in progress"].waitForExistence(timeout: Rig.timeout))
        sleep(2)
        app = tapLaunch("A_DEACT")
        waitForIdle(app)
        XCTAssertTrue(receiptHeading(app).waitForExistence(timeout: Rig.timeout), "the receipt is up")
        XCTAssertTrue(app.staticTexts["Sent"].waitForExistence(timeout: 15))
        Rig.mark("receipt-up")
        shot("p7-03-receipt-up")

        sleep(125)                                  // past the two minutes, with the receipt on screen
        Rig.mark("receipt-after-window")
        XCTAssertTrue(receiptHeading(app).exists, "the receipt is STILL shown after the two minutes")
        XCTAssertTrue(app.buttons["Continue"].exists, "with its Continue")
        XCTAssertFalse(app.staticTexts["Ready for your shift?"].exists, "the start card did not come back by itself")
        shot("p7-03-receipt-after-window")

        // a re-render (pull to refresh) past the window keeps it
        pullToRefresh(app)
        sleep(3)
        XCTAssertTrue(receiptHeading(app).exists, "still shown after a refresh past the window")
        Rig.mark("receipt-after-refresh")

        // a tab round trip past the window: Android's receipt survives it (rememberSaveable); recorded, not asserted
        app.tabBars.buttons["More"].tap()
        sleep(1)
        app.tabBars.buttons["Shift"].tap()
        sleep(2)
        let kept = receiptHeading(app).exists
        Rig.mark(kept ? "tab-return-kept-receipt" : "tab-return-lost-receipt")
        note("p7-03-tab-return", "receipt after More and back, past the window: \(kept ? "KEPT" : "LOST")")
        shot("p7-03-after-tab-return")

        // a relaunch past the window: not offered
        app.terminate()
        app = Rig.launch()
        waitForIdle(app)
        XCTAssertTrue(app.staticTexts["Ready for your shift?"].waitForExistence(timeout: Rig.timeout),
                      "after a relaunch past two minutes the start card is back")
        XCTAssertFalse(receiptHeading(app).exists, "and no receipt is offered")
        Rig.mark("relaunch-no-receipt")
        shot("p7-03-relaunch-no-receipt")
    }

    // MARK: - #4 a stop with the server down

    func testP7OfflineStopShowsItsDeliveryStateThenSentAfterRefresh() throws {
        var app = signedInIdle()
        backgroundAndKill(app)
        app = tapLaunch("A_VER")
        waitForRunning(app)
        clearPrompts()
        XCTAssertTrue(app.staticTexts["Shift in progress"].waitForExistence(timeout: Rig.timeout))
        sleep(2)
        app.terminate()
        XCTAssertTrue(Rig.rendezvous("net-down"), "driver: the front is stopped (connection refused)")
        app = tapLaunch("A_DEACT")
        waitForIdle(app)
        XCTAssertTrue(receiptHeading(app).waitForExistence(timeout: Rig.timeout), "the receipt is up for the stop made offline")
        sleep(4)                                    // past the 2 s in-flight grace
        let states = ["Sent", "Sending…", "Saved on this phone · not yet confirmed", "No connection - will send when you're back online."]
        let shown = states.filter { app.staticTexts[$0].exists }
        note("p7-04-offline-line", "delivery line with the server down: \(shown.isEmpty ? "(none of the known four)" : shown.joined(separator: " + "))\n"
             + screenText(app))
        Rig.mark("offline-line-read")
        XCTAssertFalse(app.staticTexts["Sent"].exists, "never 'Sent' while the server has not answered")
        XCTAssertFalse(app.staticTexts["Sending…"].exists, "and not 'Sending…' once the grace is over")
        shot("p7-04-offline-receipt")

        XCTAssertTrue(Rig.rendezvous("net-up"), "driver: the front is started again")
        Rig.mark("net-restored")
        pullToRefresh(app)
        XCTAssertTrue(app.staticTexts["Sent"].waitForExistence(timeout: 25), "after the refresh the line says 'Sent'")
        Rig.mark("sent-seen")
        shot("p7-04-after-refresh")
    }

    // MARK: - #5 finish without a tag

    func testP7ManualFinishReceiptShowsManualAndCorrected() throws {
        var app = signedInIdle()
        backgroundAndKill(app)
        app = tapLaunch("A_VER")
        waitForRunning(app)
        clearPrompts()
        XCTAssertTrue(app.staticTexts["Shift in progress"].waitForExistence(timeout: Rig.timeout))
        sleep(2)
        finishWithoutTag(app)
        waitForIdle(app)
        XCTAssertTrue(receiptHeading(app).waitForExistence(timeout: Rig.timeout), "the receipt is up")
        XCTAssertTrue(app.staticTexts["Rig Haus Alpha"].exists, "it names the building")
        XCTAssertTrue(app.staticTexts["Manual"].exists, "the 'Manual' pill")
        XCTAssertTrue(app.staticTexts["Corrected"].exists, "the 'Corrected' pill")
        XCTAssertFalse(app.staticTexts["Auto-closed"].exists, "and not 'Auto-closed'")
        XCTAssertTrue(app.staticTexts["Sent"].waitForExistence(timeout: 15), "delivered")
        shot("p7-05-manual-finish-receipt")
        note("p7-05-text", screenText(app))
    }

    // MARK: - #6 a tap at another building while a shift is open

    /// A at Alpha, a tap at Beta (the switch: Alpha is closed unconfirmed and flagged), then Beta is
    /// finished. The idle screen shows Beta's receipt AND the resolver banner for Alpha's row AND that
    /// row in Recent with its red 'Auto-closed' pill - the receipt hides none of them and does not
    /// stop the banner from opening the resolver.
    func testP7SwitchBuildingKeepsTheBannerAndTheAutoClosedRowBesideTheReceipt() throws {
        var app = signedInIdle()
        backgroundAndKill(app)
        app = tapLaunch("A_VER")
        waitForRunning(app)
        clearPrompts()
        XCTAssertTrue(app.staticTexts["Shift in progress"].waitForExistence(timeout: Rig.timeout))
        sleep(2)
        app = tapLaunch("B_VER")
        waitForRunning(app)
        XCTAssertTrue(line(app, "Finished your open shift at Rig Haus Alpha and started at Rig Haus Beta").waitForExistence(timeout: Rig.timeout),
                      "the switch notice names both buildings")
        XCTAssertTrue(app.staticTexts["Shift in progress"].waitForExistence(timeout: Rig.timeout), "Beta's start is acknowledged")
        sleep(2)
        finishWithoutTag(app)
        waitForIdle(app)

        XCTAssertTrue(receiptHeading(app).waitForExistence(timeout: Rig.timeout), "Beta's receipt is up")
        let banner = line(app, "unfinished shift")
        XCTAssertTrue(banner.waitForExistence(timeout: Rig.timeout), "the resolver banner is NOT hidden by the receipt")
        XCTAssertLessThan(banner.frame.minY, receiptHeading(app).frame.minY, "the banner stays above the receipt")
        note("p7-06-banner", banner.label)
        shot("p7-06-banner-and-receipt")

        // the receipt does not gate the banner: it opens the resolver
        banner.tap()
        XCTAssertTrue(app.navigationBars["Unfinished shifts"].waitForExistence(timeout: Rig.timeout), "the resolver sheet opens")
        shot("p7-06-resolver")
        app.buttons["Later"].tap()
        XCTAssertTrue(receiptHeading(app).waitForExistence(timeout: Rig.timeout), "the receipt is still there afterwards")

        // the previous row: 'Auto-closed' in Recent, drawn red
        let pill = app.staticTexts["Auto-closed"]
        var swipes = 0
        while !(pill.exists && pill.isHittable), swipes < 8 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(pill.exists, "the previous row says 'Auto-closed'")
        let reds = MotionProbe.reddishPixels(app: app, frame: pill.frame)
        note("p7-06-pill-red", "red pixels in the 'Auto-closed' pill: \(reds)")
        XCTAssertGreaterThan(reds, 10, "the pill's text is drawn in red")
        shot("p7-06-auto-closed-row")
    }

    // MARK: - #7 a tap while the receipt is up

    func testP7TapWhileTheReceiptIsUpStartsANewShiftAndTheReceiptIsGone() throws {
        var app = signedInIdle()
        backgroundAndKill(app)
        app = tapLaunch("A_VER")
        waitForRunning(app)
        clearPrompts()
        XCTAssertTrue(app.staticTexts["Shift in progress"].waitForExistence(timeout: Rig.timeout))
        sleep(2)
        app = tapLaunch("A_DEACT")
        waitForIdle(app)
        XCTAssertTrue(receiptHeading(app).waitForExistence(timeout: Rig.timeout), "the receipt is up")
        XCTAssertTrue(app.staticTexts["Sent"].waitForExistence(timeout: 15))
        shot("p7-07-receipt-before-tap")
        Rig.mark("receipt-before-tap")

        // the next tag tap, inside the two minutes (a cold launch is the only way to inject one)
        app = tapLaunch("A_VER")
        waitForRunning(app)
        XCTAssertTrue(app.staticTexts["Shift in progress"].waitForExistence(timeout: Rig.timeout), "a new shift is running")
        XCTAssertFalse(receiptHeading(app).exists, "the receipt is gone")
        XCTAssertFalse(app.staticTexts["Sent"].exists && app.staticTexts["Shift finished"].exists)
        shot("p7-07-new-shift")
        Rig.mark("new-shift-running")
        // and stays gone on the next plain launch (a running shift is not an idle list)
        sleep(2)
        app = Rig.launch()
        waitForRunning(app)
        XCTAssertFalse(receiptHeading(app).exists, "no receipt on the next launch either")
    }

    // MARK: - #8 an online tap-in: ring then check, once, after the answer

    func testP7OnlineTapInPlaysTheRingOnceAfterTheAnswer() throws {
        var app = signedInIdle()
        backgroundAndKill(app)
        XCTAssertTrue(Rig.rendezvous("hold-open-8s"), "driver: POST /shifts/open answers after 8 s")
        Rig.mark("tap-launched")
        app = tapLaunch("A_VER")
        waitForRunning(app)
        clearPrompts()
        guard let geo = clockGeometry(app) else { XCTFail("no clock card with a head line"); return }
        let first = observe("in", seconds: 5, geometry: geo, keepPNGs: true)
        XCTAssertFalse(first.first?.hidden ?? true, "before the answer the content is shown (nothing is drawn yet)")
        XCTAssertEqual(MotionProbe.episodes(first).count, 1, "ONE ring-then-check over the clock card")
        XCTAssertTrue(app.staticTexts["Shift in progress"].waitForExistence(timeout: 10), "the shift ends up 'in progress'")
        shot("p7-08-after-ack")

        // a SECOND launch (the shift is still running, still under 45 s old)
        app.terminate()
        app = Rig.launch()
        waitForRunning(app)
        guard let geo2 = clockGeometry(app) else { XCTFail("no clock card after relaunch"); return }
        let second = observe("in-relaunch", seconds: 2.5, geometry: geo2)
        XCTAssertEqual(MotionProbe.episodes(second).count, 0, "the second launch does not replay")

        // a TAB RETURN
        app.tabBars.buttons["Materials"].tap()
        sleep(1)
        app.tabBars.buttons["Shift"].tap()
        guard let geo3 = clockGeometry(app) else { XCTFail("no clock card after the tab return"); return }
        let third = observe("in-tab", seconds: 2, geometry: geo3)
        XCTAssertEqual(MotionProbe.episodes(third).count, 0, "a tab return does not replay")

        // a RESUME from the background
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        guard let geo4 = clockGeometry(app) else { XCTFail("no clock card after the resume"); return }
        let fourth = observe("in-resume", seconds: 2, geometry: geo4)
        XCTAssertEqual(MotionProbe.episodes(fourth).count, 0, "a resume does not replay")
    }

    // MARK: - #9 never animates: offline start, a late answer

    /// The start is made with the server unreachable: pending, 'Not confirmed yet', no motion for
    /// 52 s; then the server is back and the answer lands on an event older than 45 s: the heading
    /// flips, nothing is drawn, and the identity is consumed all the same (the driver reads it).
    func testP7OfflineTapInAndALateAnswerNeverAnimate() throws {
        var app = signedInIdle()
        backgroundAndKill(app)
        XCTAssertTrue(Rig.rendezvous("net-down"), "driver: the front is stopped")
        let t0 = Date()
        Rig.mark("tap-launched")
        app = tapLaunch("A_VER")
        waitForRunning(app)
        XCTAssertTrue(app.staticTexts["Not confirmed yet"].waitForExistence(timeout: 10), "pending: 'Not confirmed yet'")
        clearPrompts()
        guard let geo = clockGeometry(app) else { XCTFail("no clock card"); return }
        var pending: [MotionSample] = []
        while Date().timeIntervalSince(t0) < 52 { pending += MotionProbe.record(seconds: 4, geometry: geo).samples }
        MotionProbe.write(MotionProbe.describe(pending), name: "p7-09-offline-frames")
        Rig.mark("offline-last-frame")
        XCTAssertEqual(MotionProbe.episodes(pending).count, 0, "a pending start never animates")
        XCTAssertTrue(pending.allSatisfy { !$0.hidden }, "and the content is never held back")
        XCTAssertTrue(app.staticTexts["Not confirmed yet"].exists, "still pending")
        shot("p7-09-pending")

        XCTAssertTrue(Rig.rendezvous("net-up"), "driver: the front is started again")
        Rig.mark("net-restored")
        let refresh = app.buttons["Refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5), "the Refresh button")
        refresh.tap()
        Rig.mark("refresh-pressed")
        let late = observe("late", seconds: 8, geometry: geo)
        XCTAssertTrue(app.staticTexts["Shift in progress"].waitForExistence(timeout: 10), "the late answer is a confirmation in words")
        XCTAssertEqual(MotionProbe.episodes(late).count, 0, "an answer for an event older than 45 s is not celebrated")
        XCTAssertTrue(late.allSatisfy { !$0.hidden }, "and the content is never held back")
        shot("p7-09-late-ack")
    }

    /// A refused start (the zone was deactivated after the phone cached it): a BLOCKED row. Never drawn,
    /// and nothing is consumed (the driver reads the preference).
    func testP7BlockedRowNeverAnimates() throws {
        var app = signedInIdle()
        XCTAssertTrue(Rig.rendezvous("zone-deactivated"), "driver: Dachboden is deactivated")
        backgroundAndKill(app)
        app = tapLaunch("A_DEACT")
        waitForRunning(app)
        XCTAssertTrue(app.staticTexts["Not confirmed yet"].waitForExistence(timeout: 10), "'Not confirmed yet' on a refused start")
        XCTAssertTrue(line(app, "This location was removed. Ask your admin.").waitForExistence(timeout: Rig.timeout), "the blocked sentence")
        clearPrompts()
        guard let geo = clockGeometry(app) else { XCTFail("no clock card"); return }
        let first = observe("blocked", seconds: 6, geometry: geo)
        XCTAssertEqual(MotionProbe.episodes(first).count, 0, "a blocked row never animates")
        XCTAssertTrue(first.allSatisfy { !$0.hidden }, "and the content is never held back")
        let refresh = app.buttons["Refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        refresh.tap()
        let second = observe("blocked-refresh", seconds: 5, geometry: geo)
        XCTAssertEqual(MotionProbe.episodes(second).count, 0, "nor after a Refresh the server refuses again")
        XCTAssertTrue(app.staticTexts["Not confirmed yet"].exists, "still not confirmed")
        shot("p7-09-blocked")
    }

    // MARK: - #10 an online tap-out: once, on the receipt (and the 'saved on this phone' line before it)

    func testP7OnlineTapOutPlaysOnceOnTheReceipt() throws {
        var app = signedInIdle()
        backgroundAndKill(app)
        app = tapLaunch("A_VER")
        waitForRunning(app)
        clearPrompts()
        XCTAssertTrue(app.staticTexts["Shift in progress"].waitForExistence(timeout: Rig.timeout))
        sleep(2)
        XCTAssertTrue(Rig.rendezvous("hold-close-7s"), "driver: POST /shifts/close answers after 7 s")
        Rig.mark("tap-launched")
        app = tapLaunch("A_DEACT")
        waitForIdle(app)
        XCTAssertTrue(receiptHeading(app).waitForExistence(timeout: Rig.timeout), "the receipt is up at once")
        let early = ["Sent", "Sending…", "Saved on this phone · not yet confirmed"].filter { app.staticTexts[$0].exists }
        XCTAssertFalse(early.contains("Sent"), "not 'Sent' before the answer")
        // the line once the 2 s in-flight grace is over and nothing is recorded: the matrix's sentence
        XCTAssertTrue(app.staticTexts["Saved on this phone · not yet confirmed"].waitForExistence(timeout: 6),
                      "the line says 'Saved on this phone · not yet confirmed' while the answer is outstanding")
        shot("p7-10-saved-on-this-phone")
        note("p7-10-line-before-answer", "first seen: \(early.joined(separator: " + ")); then: Saved on this phone · not yet confirmed")
        guard let geo = receiptGeometry(app) else { XCTFail("no receipt geometry"); return }
        let first = observe("out", seconds: 6, geometry: geo, keepPNGs: true)
        XCTAssertFalse(first.first?.hidden ?? true, "before the answer the receipt's text is shown")
        XCTAssertEqual(MotionProbe.episodes(first).count, 1, "ONE ring-then-check on the receipt")
        XCTAssertTrue(app.staticTexts["Sent"].waitForExistence(timeout: 10), "and then the line says 'Sent'")
        shot("p7-10-after-ack")

        // a second launch, a tab return and a resume: the receipt is offered again (< 2 min), the check is not
        app.terminate()
        app = Rig.launch()
        waitForIdle(app)
        XCTAssertTrue(receiptHeading(app).waitForExistence(timeout: Rig.timeout), "the receipt is offered again on the relaunch")
        guard let geo2 = receiptGeometry(app) else { XCTFail("no receipt geometry after relaunch"); return }
        let second = observe("out-relaunch", seconds: 2.5, geometry: geo2)
        XCTAssertEqual(MotionProbe.episodes(second).count, 0, "the second launch does not replay")

        app.tabBars.buttons["Materials"].tap()
        sleep(1)
        app.tabBars.buttons["Shift"].tap()
        guard let geo3 = receiptGeometry(app) else { XCTFail("no receipt after the tab return"); return }
        let third = observe("out-tab", seconds: 2, geometry: geo3)
        XCTAssertEqual(MotionProbe.episodes(third).count, 0, "a tab return does not replay")
    }

    // MARK: - #11 Reduce Motion

    func testP7ReduceMotionPlaysNothingAndConsumesTheIdentity() throws {
        XCTAssertTrue(UIAccessibility.isReduceMotionEnabled, "Reduce Motion is ON on this device (the driver set it)")
        var app = signedInIdle()
        backgroundAndKill(app)
        XCTAssertTrue(Rig.rendezvous("hold-open-8s"), "driver: POST /shifts/open answers after 8 s")
        Rig.mark("tap-launched")
        app = tapLaunch("A_VER")
        waitForRunning(app)
        clearPrompts()
        guard let geo = clockGeometry(app) else { XCTFail("no clock card with a head line"); return }
        let samples = observe("reduce", seconds: 9, geometry: geo, keepPNGs: true)
        XCTAssertTrue(app.staticTexts["Shift in progress"].waitForExistence(timeout: 10), "the answer still lands: 'Shift in progress'")
        XCTAssertEqual(MotionProbe.episodes(samples).count, 0, "Reduce Motion: no ring-then-check")
        XCTAssertTrue(samples.allSatisfy { !$0.hidden }, "and the content is never held back")
        shot("p7-11-reduce-motion")
    }
}
