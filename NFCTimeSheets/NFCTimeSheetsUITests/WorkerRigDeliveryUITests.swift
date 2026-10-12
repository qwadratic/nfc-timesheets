//
//  WorkerRigDeliveryUITests.swift
//  NFCTimeSheetsUITests
//
//  P5 (TASK-365.6, "Not confirmed yet") and P6 (TASK-365.7, delivery status) DRIVEN against the
//  rig's real server. The phone half is here; the server half (rows, wire) is the driver's
//  (ops/ios-rig/walk.sh p5 / p6). Server state is flipped at named rendezvous points:
//
//    net-down / net-up        the TLS front is stopped / started: the phone's connection is
//                             REFUSED, which the app reads as status 0 ("No connection ...")
//    server-stop / server-start   the API is stopped: the front answers 502
//
//  Taps are the DEBUG-only `--ts-demo-tap <zone uuid>` launch argument (a simulator has no NFC
//  radio); everything after it is shipping code. The worker is signed in through the real form.
//

import UIKit
import XCTest

final class WorkerRigDeliveryUITests: XCTestCase {
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

    /// Signs A in (server must be up) and returns the running app on the idle screen.
    private func signedInIdle(_ worker: String = "A") -> XCUIApplication {
        let app = Rig.launch()
        ensureSignedIn(app, as: worker)
        waitForIdle(app)
        sleep(2)
        return app
    }

    private func finishWithoutTag(_ app: XCUIApplication) {
        let finish = app.buttons["Finish shift without a tag"]
        var swipes = 0
        while !finish.isHittable, swipes < 8 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(finish.waitForExistence(timeout: Rig.timeout))
        finish.tap()
        let confirm = app.buttons["Finish now"]
        XCTAssertTrue(confirm.waitForExistence(timeout: Rig.timeout), "the confirmation dialog")
        confirm.tap()
    }

    private func deliveryRow(_ app: XCUIApplication, _ fragment: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", fragment)).firstMatch
    }

    /// Everything the delivery sheet says, as one string (for the wording assertions).
    private func sheetText(_ app: XCUIApplication) -> String {
        app.staticTexts.allElementsBoundByIndex.filter { $0.exists }.map(\.label).joined(separator: " | ")
    }

    private func assertWording(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let lower = text.lowercased()
        XCTAssertFalse(lower.contains("force"), "never promises or mentions force-stopping: \(text)", file: file, line: line)
        // "automatic" is allowed ONLY inside the one sentence the task mandates.
        let stripped = lower.replacingOccurrences(of: "automatic delivery is not currently active", with: "")
        XCTAssertFalse(stripped.contains("automatic"), "never says 'automatically' elsewhere: \(text)", file: file, line: line)
    }

    /// The clock advances: two pictures of the clock card a few seconds apart differ.
    private func clockAdvances(_ app: XCUIApplication) -> Bool {
        let card = app.otherElements.matching(NSPredicate(format: "label CONTAINS[c] %@", "recorded on this phone")).firstMatch
        guard card.waitForExistence(timeout: 5) else { return false }
        let frame = card.frame
        func crop() -> Data? {
            let shot = XCUIScreen.main.screenshot()
            let scale = shot.image.scale
            let rect = CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale)
            guard let cg = shot.image.cgImage?.cropping(to: rect) else { return nil }
            return UIImage(cgImage: cg).pngData()
        }
        let first = crop()
        sleep(3)
        let second = crop()
        return first != nil && second != nil && first != second
    }

    // MARK: - P5 #1: running, online

    func testP5OnlineTapStartNeverFlashesNotConfirmed() throws {
        let app = Rig.launch(tap: Rig.zone("A_VER"))
        ensureSignedIn(app, as: "A")
        waitForRunning(app)
        var flashed = false
        let until = Date().addingTimeInterval(5)
        while Date() < until {
            if app.staticTexts["Not confirmed yet"].exists { flashed = true }
            usleep(100_000)
        }
        XCTAssertFalse(flashed, "an acknowledged tap never says 'Not confirmed yet' (2 s grace)")
        XCTAssertTrue(app.staticTexts["Clocked in"].exists, "heading 'Clocked in'")
        XCTAssertTrue(app.staticTexts["Running"].exists)
        XCTAssertFalse(app.buttons["Refresh"].exists, "no notice, so no Refresh button")
        shot("p5-01-running-online")
    }

    // MARK: - P5 #2 #3 #6: unreachable server, then recovery

    /// The whole offline story in one screen: unreachable server, tap-start, what the heading,
    /// word and notice say, that the clock counts and every control works, the accessibility
    /// label, then recovery through the Refresh button.
    func testP5UnreachableServerThenRecovery() throws {
        // sign in with the server up, then take the network away and tap
        var app = signedInIdle()
        backgroundAndKill(app)
        XCTAssertTrue(Rig.rendezvous("net-down"), "driver flip: the front is stopped")
        app = Rig.launch(tap: Rig.zone("A_VER"))
        waitForRunning(app)
        // 'Not confirmed yet' appears after ~2 s (or at once on a sync error)
        XCTAssertTrue(app.staticTexts["Not confirmed yet"].waitForExistence(timeout: 10),
                      "heading 'Not confirmed yet' after the grace")
        XCTAssertTrue(app.staticTexts["Time recorded on this phone"].exists, "word under the clock")
        XCTAssertTrue(anyElement(app, containing: "No connection - will send when you're back online.").exists,
                      "the notice in the worker's words")
        XCTAssertTrue(app.buttons["Refresh"].exists, "with a Refresh button")
        shot("p5-02-unreachable")

        // VoiceOver reads the accessibility label: the clock card is ONE element, Refresh another.
        let spoken = app.otherElements.matching(NSPredicate(format: "label CONTAINS[c] %@", "recorded on this phone for")).firstMatch
        XCTAssertTrue(spoken.exists, "the clock card carries the spoken label")
        XCTAssertTrue(spoken.label.contains("Rig Haus Alpha"), "it names the building")
        XCTAssertTrue(spoken.label.contains("Not confirmed by the office yet."), "and says the start is not confirmed")
        XCTAssertTrue(app.buttons["Refresh"].exists && app.buttons["Refresh"].isHittable,
                      "Refresh is its own control, not part of the clock element")
        Rig.mark("spoken-label")
        try? spoken.label.write(toFile: (Rig.value("TS_RIG_SHOTS") ?? "/dev/null") + "/p5-06-spoken-label.txt",
                                atomically: true, encoding: .utf8)

        XCTAssertTrue(clockAdvances(app), "the clock keeps counting from the local start")
        XCTAssertTrue(app.buttons["Finish shift without a tag"].exists || {
            app.swipeUp(); return app.buttons["Finish shift without a tag"].exists }(), "Stop is usable")
        XCTAssertTrue(app.buttons["Scan a tag"].exists, "Scan is usable")
        XCTAssertTrue(app.tabBars.buttons["Materials"].isHittable && app.tabBars.buttons["More"].isHittable,
                      "the tabs are usable")

        // recovery
        XCTAssertTrue(Rig.rendezvous("net-up"), "driver flip: the front is started again")
        app.swipeDown()
        let refresh = app.buttons["Refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        Rig.mark("refresh-pressed")
        refresh.tap()
        XCTAssertTrue(app.staticTexts["Clocked in"].waitForExistence(timeout: Rig.timeout),
                      "after Refresh the heading flips to 'Clocked in'")
        XCTAssertFalse(app.buttons["Refresh"].exists, "the notice disappears")
        XCTAssertFalse(app.staticTexts["Not confirmed yet"].exists)
        shot("p5-03-recovered")
    }

    // MARK: - P5 #4: a refusal

    func testP5RefusedTapShowsTheRowsSentence() throws {
        // signed in first (zone A_UNV is unverified in the seed), then tap it
        var app = signedInIdle()
        backgroundAndKill(app)
        app = Rig.launch(tap: Rig.zone("A_UNV"))
        waitForRunning(app)
        XCTAssertTrue(app.staticTexts["Not confirmed yet"].waitForExistence(timeout: 10),
                      "heading 'Not confirmed yet' on a refused start")
        XCTAssertTrue(anyElement(app, containing: "hasn't been activated yet").waitForExistence(timeout: Rig.timeout),
                      "the notice shows the row's own sentence")
        XCTAssertTrue(app.buttons["Refresh"].exists)
        shot("p5-04-refused")
    }

    /// The same, with a TERMINAL refusal (unknown_location: the zone was deactivated after the
    /// phone cached it). That row is BLOCKED: nobody is retrying it, so its icon is red.
    func testP5BlockedRefusalShowsTheSentenceAndTheRedIcon() throws {
        var app = signedInIdle()
        XCTAssertTrue(Rig.rendezvous("zone-deactivated"), "driver flip: Dachboden deactivated")
        backgroundAndKill(app)
        app = Rig.launch(tap: Rig.zone("A_DEACT"))
        waitForRunning(app)
        XCTAssertTrue(app.staticTexts["Not confirmed yet"].waitForExistence(timeout: 10))
        XCTAssertTrue(anyElement(app, containing: "This location was removed. Ask your admin.").waitForExistence(timeout: Rig.timeout),
                      "the notice shows the blocked row's sentence")
        XCTAssertTrue(app.buttons["Refresh"].exists)
        shot("p5-04-blocked-refusal")   // the red octagon beside the sentence is a picture, not a label
    }

    // MARK: - P5 overdue (what can be produced: a 9 h old OPEN shift adopted from the server)

    func testP5OverdueShiftIsShownAsOverEightHours() throws {
        let app = Rig.launch()
        ensureSignedIn(app, as: "A")
        // the driver gave A an open shift started 9 h ago ("another device"); refresh adopts it
        XCTAssertTrue(app.navigationBars["Shift running"].waitForExistence(timeout: Rig.timeout),
                      "the server's open shift is adopted and shown")
        XCTAssertTrue(app.staticTexts["Over 8 hours"].waitForExistence(timeout: 5), "heading 'Over 8 hours'")
        XCTAssertFalse(app.staticTexts["Not confirmed yet"].exists)
        XCTAssertTrue(anyElement(app, containing: "passed 8 hours and was closed automatically").exists)
        shot("p5-05-overdue")
    }

    // MARK: - P6 #2: nothing unsent

    func testP6EmptyQueueDrawsNoRowsAndNoSheet() throws {
        let app = signedInIdle()
        sleep(3)
        XCTAssertFalse(deliveryRow(app, "on this phone").exists, "no 'still on this phone' row")
        XCTAssertFalse(deliveryRow(app, "your office").exists, "no 'needs your office' row")
        XCTAssertFalse(app.staticTexts["Delivery"].exists, "no sheet")
        shot("p6-02-empty-queue")
    }

    // MARK: - P6 #3 #4 #5 #9: waiting, attempted, recovery

    func testP6WaitingAttemptedThenRecovered() throws {
        var app = signedInIdle()
        backgroundAndKill(app)
        XCTAssertTrue(Rig.rendezvous("net-down"), "driver flip: front stopped")
        app = Rig.launch(tap: Rig.zone("A_VER"))
        waitForRunning(app)
        finishWithoutTag(app)
        waitForIdle(app)
        sleep(3) // past the 2 s in-flight grace
        let row = deliveryRow(app, "still on this phone")
        XCTAssertTrue(row.waitForExistence(timeout: Rig.timeout), "idle shows '1 shift still on this phone'")
        XCTAssertTrue(row.label.hasPrefix("1 "), "count is 1: \(row.label)")
        shot("p6-03-waiting-row")
        row.tap()
        XCTAssertTrue(app.staticTexts["Delivery"].waitForExistence(timeout: Rig.timeout), "the sheet opens")
        XCTAssertTrue(anyElement(app, containing: "Automatic delivery is not currently active").exists,
                      "the waiting sentence")
        XCTAssertTrue(anyElement(app, containing: "Earliest shift start:").exists, "the earliest start")
        let first = sheetText(app)
        try? first.write(toFile: (Rig.value("TS_RIG_SHOTS") ?? "/dev/null") + "/p6-03-sheet-text.txt", atomically: true, encoding: .utf8)
        assertWording(first)
        let attempted = anyElement(app, containing: "Last attempt:").exists
        let notYet = anyElement(app, containing: "No delivery attempt yet.").exists
        Rig.mark(attempted ? "sheet-says-last-attempt" : (notYet ? "sheet-says-no-attempt-yet" : "sheet-says-neither"))
        shot("p6-03-sheet-waiting")
        app.buttons["Close"].tap()

        // P6 #4: pull-to-refresh with the server still down
        Rig.mark("pull-down")
        pullToRefresh(app)
        sleep(3)
        deliveryRow(app, "still on this phone").tap()
        XCTAssertTrue(anyElement(app, containing: "Last attempt:").waitForExistence(timeout: Rig.timeout),
                      "after a pull the sheet shows 'Last attempt: <time>'")
        assertWording(sheetText(app))
        shot("p6-04-sheet-last-attempt")
        app.buttons["Close"].tap()

        // P6 #5: recovery
        XCTAssertTrue(Rig.rendezvous("net-up"), "driver flip: front started")
        Rig.mark("pull-up")
        pullToRefresh(app)
        let gone = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: gone, object: deliveryRow(app, "still on this phone"))
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: Rig.timeout), .completed,
                       "the row disappears once the queue is delivered")
        shot("p6-05-recovered")
    }

    // MARK: - P6 #6 #7: blocked (+ waiting), and the running screen

    func testP6BlockedAndWaitingRowsAndTheRunningScreen() throws {
        var app = signedInIdle()
        // zone_unverified is RETRYABLE (the operator's test scan fixes it later), so that row is
        // WAITING. A BLOCKED row needs a terminal refusal: unknown_location, i.e. a zone that was
        // deactivated after the phone cached it ("zone_unverified-turned-removed").
        XCTAssertTrue(Rig.rendezvous("zone-deactivated"), "driver flip: Dachboden deactivated")
        backgroundAndKill(app)
        // 1. a refused tap (422 unknown_location): the row is BLOCKED; finish it without a tag
        app = Rig.launch(tap: Rig.zone("A_DEACT"))
        waitForRunning(app)
        XCTAssertTrue(app.staticTexts["Not confirmed yet"].waitForExistence(timeout: 10))
        finishWithoutTag(app)
        waitForIdle(app)
        let blocked = deliveryRow(app, "your office")
        XCTAssertTrue(blocked.waitForExistence(timeout: Rig.timeout), "'1 shift needs your office' row")
        XCTAssertTrue(blocked.label.hasPrefix("1 "), "count is 1: \(blocked.label)")
        shot("p6-06-blocked-row")
        blocked.tap()
        XCTAssertTrue(anyElement(app, containing: "remain on this phone and are not sent again").waitForExistence(timeout: Rig.timeout),
                      "the blocked detail")
        XCTAssertTrue(anyElement(app, containing: "Earliest shift start:").exists, "names the earliest start")
        let blockedText = sheetText(app)
        try? blockedText.write(toFile: (Rig.value("TS_RIG_SHOTS") ?? "/dev/null") + "/p6-06-sheet-text.txt", atomically: true, encoding: .utf8)
        assertWording(blockedText)
        shot("p6-06-sheet-blocked")
        app.buttons["Close"].tap()

        // 2. P6 #7: a good start while the blocked row is still on the phone: the running
        //    screen shows the blocked row and NO row for the acknowledged open shift
        backgroundAndKill(app)
        app = Rig.launch(tap: Rig.zone("A_VER"))
        waitForRunning(app)
        sleep(4)
        XCTAssertTrue(app.staticTexts["Clocked in"].exists, "the new shift is acknowledged")
        var swipes = 0
        while !deliveryRow(app, "your office").exists, swipes < 6 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(deliveryRow(app, "your office").exists, "the previous unsent (blocked) row DOES show on the running screen")
        XCTAssertFalse(deliveryRow(app, "still on this phone").exists, "and the acknowledged open shift has no row of its own")
        shot("p6-07-running-with-blocked-row")
        finishWithoutTag(app)
        waitForIdle(app)

        // 3. waiting + blocked: two rows
        XCTAssertTrue(Rig.rendezvous("net-down"), "driver flip: front stopped")
        backgroundAndKill(app)
        app = Rig.launch(tap: Rig.zone("B_VER"))
        waitForRunning(app)
        finishWithoutTag(app)
        waitForIdle(app)
        sleep(3)
        XCTAssertTrue(deliveryRow(app, "still on this phone").waitForExistence(timeout: Rig.timeout), "the waiting row")
        XCTAssertTrue(deliveryRow(app, "your office").exists, "and the blocked row: two rows")
        shot("p6-06-two-rows")
        XCTAssertTrue(Rig.rendezvous("net-up"), "driver flip: front started (cleanup)")
    }

    // MARK: - P6 #8: the sign-in screen

    func testP6SignInScreenShowsTheRowsAndTheSignInSentence() throws {
        var app = signedInIdle()
        backgroundAndKill(app)
        XCTAssertTrue(Rig.rendezvous("net-down"), "driver flip: front stopped")
        app = Rig.launch(tap: Rig.zone("A_VER"))
        waitForRunning(app)
        finishWithoutTag(app)
        waitForIdle(app)
        sleep(3)
        app.tabBars.buttons["More"].tap()
        let signOut = app.buttons["Sign out"]
        XCTAssertTrue(signOut.waitForExistence(timeout: Rig.timeout))
        signOut.tap()
        XCTAssertTrue(app.textFields["Access code"].waitForExistence(timeout: Rig.timeout), "signed out")
        let row = deliveryRow(app, "still on this phone")
        XCTAssertTrue(row.waitForExistence(timeout: Rig.timeout), "the sign-in screen shows the phone's unsent shift")
        shot("p6-08-signin-row")
        row.tap()
        XCTAssertTrue(anyElement(app, containing: "Sign in with the same account so these entries can be delivered.")
                        .waitForExistence(timeout: Rig.timeout), "the sign-in sentence")
        XCTAssertFalse(anyElement(app, containing: "Open the app").exists, "never 'open the app'")
        let text = sheetText(app)
        try? text.write(toFile: (Rig.value("TS_RIG_SHOTS") ?? "/dev/null") + "/p6-08-sheet-text.txt", atomically: true, encoding: .utf8)
        assertWording(text)
        shot("p6-08-signin-sheet")
        app.buttons["Close"].tap()
        XCTAssertTrue(Rig.rendezvous("net-up"), "driver flip: front started (cleanup)")
    }

    // MARK: - P6 #11: Dynamic Type 200%

    func testP6DynamicTypeTwoHundredPercentRowsWrapAndStayTappable() throws {
        var app = signedInIdle()
        backgroundAndKill(app)
        XCTAssertTrue(Rig.rendezvous("net-down"), "driver flip: front stopped")
        app = Rig.launch(tap: Rig.zone("A_VER"))
        waitForRunning(app)
        finishWithoutTag(app)
        waitForIdle(app)
        sleep(3)
        backgroundAndKill(app)
        // Accessibility L (AX2) is 194% of the base size: the "200%" of the matrix.
        app = Rig.launch(args: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        // The idle list is long at this size and lazy: 'Start without a tag' is below the fold.
        XCTAssertTrue(app.navigationBars["TimeSheet"].waitForExistence(timeout: Rig.timeout), "the idle Log screen")
        let row = deliveryRow(app, "still on this phone")
        XCTAssertTrue(row.waitForExistence(timeout: Rig.timeout), "the row is drawn at 200%")
        XCTAssertGreaterThanOrEqual(row.frame.height, 44, "stays at least 44 pt tall: \(row.frame.height)")
        shot("p6-11-dynamic-type-row")
        row.tap()
        XCTAssertTrue(app.staticTexts["Delivery"].waitForExistence(timeout: Rig.timeout))
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: Rig.timeout) && close.isHittable, "Close stays on screen")
        XCTAssertGreaterThanOrEqual(close.frame.height, 44, "and is at least 44 pt tall")
        shot("p6-11-dynamic-type-sheet")
        close.tap()
        XCTAssertTrue(Rig.rendezvous("net-up"), "driver flip: front started (cleanup)")
    }
}
