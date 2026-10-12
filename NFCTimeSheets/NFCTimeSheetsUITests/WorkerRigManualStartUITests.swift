//
//  WorkerRigManualStartUITests.swift
//  NFCTimeSheetsUITests
//
//  P2 (TASK-365.3, decision-81) DRIVEN: "Start without a tag" picks a ZONE and asks the server
//  first. Every walk is one small test. What the PHONE shows is asserted here; what the SERVER
//  holds and what went over the WIRE is asserted by ops/ios-rig/walk.sh (psql + the front's
//  JSONL log), because a UI test can see neither. Where a walk needs server state flipped
//  between two taps, the test stops at a named rendezvous and the driver flips it.
//
//      ops/ios-rig/walk.sh p2-online-verified          one walk, all its assertions
//      ops/ios-rig/walk.sh p2                          every P2 walk
//
//  A test is meaningless without its driver's flips and queries: a green xcodebuild on its own
//  proves the phone half only, and says so in the driver's report.
//

import XCTest

final class WorkerRigManualStartUITests: XCTestCase {
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

    private func launchSignedIn() -> XCUIApplication {
        let app = Rig.launch()
        ensureSignedIn(app, as: "A")
        waitForIdle(app)
        return app
    }

    private func openSheet(_ app: XCUIApplication) {
        let start = idleScreen(app)
        XCTAssertTrue(start.waitForExistence(timeout: Rig.timeout))
        start.tap()
        XCTAssertTrue(app.navigationBars["Start without a tag"].waitForExistence(timeout: Rig.timeout),
                      "the 'Start without a tag' sheet is up")
    }

    /// The Zone picker's row (the stock menu Picker: ONE button whose label carries the title
    /// and the current choice).
    private func pickerRow(_ app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", "Choose a zone")
        let candidates = [
            app.buttons.matching(predicate).firstMatch,
            app.cells.containing(predicate).firstMatch,
            app.staticTexts["Choose a zone"],
        ]
        _ = candidates[0].waitForExistence(timeout: Rig.timeout)
        return candidates.first(where: { $0.exists && $0.isHittable }) ?? candidates[0]
    }

    /// Opens the menu and returns the option buttons whose label contains " · ", in on-screen order.
    private func menuOptions(_ app: XCUIApplication) -> [String] {
        pickerRow(app).tap()
        let first = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", " · ")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: Rig.timeout), "the picker menu lists zones")
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", " · ")).allElementsBoundByIndex
        return rows.filter { $0.exists }.sorted { $0.frame.minY < $1.frame.minY }.map(\.label)
    }

    private func pick(_ app: XCUIApplication, _ label: String) {
        let option = app.buttons[label]
        XCTAssertTrue(option.waitForExistence(timeout: Rig.timeout), "the menu offers '\(label)'")
        option.tap()
    }

    private func pickZone(_ app: XCUIApplication, _ label: String) {
        pickerRow(app).tap()
        pick(app, label)
    }

    private func tapStart(_ app: XCUIApplication) {
        let start = app.buttons["Start"]
        XCTAssertTrue(start.waitForExistence(timeout: Rig.timeout))
        XCTAssertTrue(start.isEnabled, "a zone is picked, so Start is enabled")
        start.tap()
    }

    private func confirmStart(_ app: XCUIApplication) {
        let confirm = app.buttons["Start shift"]
        XCTAssertTrue(confirm.waitForExistence(timeout: Rig.timeout), "the confirmation dialog's 'Start shift'")
        confirm.tap()
    }

    private func cancelSheet(_ app: XCUIApplication) {
        let cancel = app.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 5) { cancel.tap() }
    }

    private func assertNoLocalRow(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        waitForIdle(app, file: file, line: line)
        XCTAssertTrue(app.staticTexts["No completed shifts yet."].exists,
                      "no shift row of any kind is on the idle screen", file: file, line: line)
        openHistory(app)
        XCTAssertTrue(app.staticTexts["No shifts yet."].waitForExistence(timeout: Rig.timeout),
                      "History holds no local row either: nothing was written on this phone",
                      file: file, line: line)
        app.tabBars.buttons["Shift"].tap()
    }

    // MARK: - #2 empty state

    /// The roster call is refused by the front (503) BEFORE the first launch, so the phone has
    /// no cached zone and no cached building: "fresh, offline" for everything the picker needs.
    func testEmptyZoneListShowsTheRefreshSentenceAndAsksNothing() throws {
        let app = launchSignedIn()
        Rig.mark("sheet-opening")
        openSheet(app)
        Rig.mark("sheet-opened")
        sleep(2)
        dumpHierarchy(app, "p2-02-hierarchy")
        shot("p2-02-empty-state")
        let sentence = anyElement(app, containing: "No zones are available. Please refresh first")
        XCTAssertTrue(sentence.waitForExistence(timeout: Rig.timeout),
                      "an empty cache says so, in words, instead of drawing an empty wheel")
        XCTAssertTrue(anyElement(app, containing: "contact the office").exists,
                      "and tells the worker what to do if the zone is still missing")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Choose a zone")).firstMatch.exists,
                       "there is no picker above a live Start button")
        XCTAssertFalse(app.buttons["Start"].isEnabled, "nothing can be started from an empty list")
        shot("p2-02-empty-state")
        Rig.mark("sheet-checked")
        cancelSheet(app)
    }

    // MARK: - #3 sorted rows, none selected, Start disabled until picked, dialog names the label

    func testPickerRowsAreSortedNothingPreselectedAndTheDialogNamesTheZone() throws {
        let app = launchSignedIn()
        openSheet(app)
        XCTAssertTrue(pickerRow(app).exists, "the Zone picker is drawn")
        XCTAssertFalse(app.buttons["Start"].isEnabled, "nothing is preselected: Start is disabled")
        shot("p2-03-sheet-nothing-selected")

        let options = menuOptions(app)
        shot("p2-03-menu-open")
        XCTAssertEqual(options, [
            "Rig Haus Alpha · Dachboden",
            "Rig Haus Alpha · Keller",
            "Rig Haus Alpha · Stiege 1",
            "Rig Haus Beta · Haupteingang",
        ], "rows are 'Building · Zone', sorted building then zone, unverified included, no building row")
        XCTAssertFalse(options.contains { !$0.contains(" · ") }, "no bare building is ever offered")

        pick(app, "Rig Haus Alpha · Stiege 1")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Rig Haus Alpha · Stiege 1")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the picked zone is what the row now shows")
        XCTAssertTrue(app.buttons["Start"].isEnabled, "picked: Start is enabled")
        tapStart(app)
        let title = anyElement(app, containing: "Start a shift at Rig Haus Alpha · Stiege 1?")
        XCTAssertTrue(title.waitForExistence(timeout: Rig.timeout),
                      "the confirmation dialog names the zone label ('Building · Zone')")
        shot("p2-03-confirm-dialog")
        // Back out: nothing may be started by looking.
        let cancel = app.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 3) { cancel.tap() }
        cancelSheet(app)
    }

    // MARK: - #4 online start of a verified zone

    func testOnlineStartOfAVerifiedZoneOpensAnAcknowledgedShift() throws {
        let app = launchSignedIn()
        openSheet(app)
        pickZone(app, "Rig Haus Alpha · Stiege 1")
        tapStart(app)
        confirmStart(app)
        Rig.mark("confirmed")
        waitForRunning(app)
        XCTAssertTrue(app.staticTexts["Rig Haus Alpha"].waitForExistence(timeout: Rig.timeout),
                      "the running screen names the zone's BUILDING")
        // 'Not confirmed yet' must never flash while the server answers at once (2 s grace).
        var flashed = false
        let until = Date().addingTimeInterval(4.5)
        while Date() < until {
            if app.staticTexts["Not confirmed yet"].exists { flashed = true }
            usleep(150_000)
        }
        XCTAssertFalse(flashed, "an acknowledged manual start never says 'Not confirmed yet'")
        XCTAssertTrue(app.staticTexts["Shift in progress"].exists, "heading 'Shift in progress'")
        XCTAssertTrue(app.staticTexts["Running"].exists, "word under the clock 'Running'")
        shot("p2-04-running-online")
        // "'Manual' pill later": finish it WITH THE TAG (a plain tap-out at the same zone, so the
        // pill can only come from the manual START), and look at Recent.
        sleep(2)
        backgroundAndKill(app)
        let again = Rig.launch(tap: Rig.zone("A_VER"))
        waitForIdle(again)
        XCTAssertTrue(again.staticTexts["Manual"].waitForExistence(timeout: Rig.timeout),
                      "the finished row carries the 'Manual' pill although it was closed by a tag")
        shot("p2-04-manual-pill-after-tag-close")
    }

    // MARK: - #5 unverified zone

    func testUnverifiedZoneIsRefusedInlineAndWritesNothing() throws {
        let app = launchSignedIn()
        openSheet(app)
        pickZone(app, "Rig Haus Alpha · Keller")
        tapStart(app)
        confirmStart(app)
        let refusal = anyElement(app, containing: "hasn't been activated yet")
        XCTAssertTrue(refusal.waitForExistence(timeout: Rig.timeout),
                      "the server's refusal is shown INSIDE the sheet, in the worker's words")
        XCTAssertTrue(anyElement(app, containing: "No shift was started").exists)
        XCTAssertTrue(app.navigationBars["Start without a tag"].exists, "the sheet stays open")
        XCTAssertTrue(app.buttons["Start"].isEnabled, "and Start is usable again")
        shot("p2-05-unverified-inline")
        cancelSheet(app)
        assertNoLocalRow(app)
    }

    // MARK: - #6 another shift open on the server (a second device holds it)

    func testOpenShiftOnTheServerIsAnsweredInlineWithNoRow() throws {
        let app = launchSignedIn()
        openSheet(app)
        pickZone(app, "Rig Haus Alpha · Stiege 1")
        // The driver now gives worker A an open shift "from another device".
        XCTAssertTrue(Rig.rendezvous("open-elsewhere"), "driver flip: open shift on the server")
        tapStart(app)
        confirmStart(app)
        let refusal = anyElement(app, containing: "Another shift is still running")
        XCTAssertTrue(refusal.waitForExistence(timeout: Rig.timeout),
                      "409 shift_already_open is shown inline")
        XCTAssertTrue(app.navigationBars["Start without a tag"].exists, "the sheet stays open")
        shot("p2-06-409-inline")
        cancelSheet(app)
        assertNoLocalRow(app)
    }

    // MARK: - #7 zone deactivated after the phone cached it

    func testZoneDeactivatedAfterCachingIsRefusedInlineWithNoRow() throws {
        let app = launchSignedIn()
        openSheet(app)
        pickZone(app, "Rig Haus Alpha · Dachboden")
        XCTAssertTrue(Rig.rendezvous("zone-deactivated"), "driver flip: Dachboden deactivated")
        tapStart(app)
        confirmStart(app)
        let refusal = anyElement(app, containing: "This location was removed")
        XCTAssertTrue(refusal.waitForExistence(timeout: Rig.timeout),
                      "422 unknown_location is shown inline: 'This location was removed. Ask your admin.'")
        XCTAssertTrue(app.navigationBars["Start without a tag"].exists, "the sheet stays open")
        shot("p2-07-removed-inline")
        cancelSheet(app)
        assertNoLocalRow(app)
    }

    // MARK: - #8 server down: queued locally, ONE server row after recovery

    /// One test, two rendezvous: the driver stops the API (the front then answers 502) before
    /// Start, and starts it again before the pull. The sheet closes, a running screen is up,
    /// the row is queued; once the server is back, the shipping pull-to-refresh delivers it.
    func testServerDownStartIsQueuedLocallyThenDeliveredOnPullToRefresh() throws {
        let app = launchSignedIn()
        openSheet(app)
        pickZone(app, "Rig Haus Alpha · Stiege 1")
        XCTAssertTrue(Rig.rendezvous("server-stopped"), "driver flip: API stopped")
        tapStart(app)
        confirmStart(app)
        waitForRunning(app)
        XCTAssertFalse(app.navigationBars["Start without a tag"].exists, "the sheet closed")
        XCTAssertTrue(app.staticTexts["Not confirmed yet"].waitForExistence(timeout: 8),
                      "after the 2 s grace the heading says the start is not confirmed")
        XCTAssertTrue(app.staticTexts["Time recorded on this phone"].exists)
        shot("p2-08-queued-while-down")
        XCTAssertTrue(Rig.rendezvous("server-back"), "driver flip: API started again")
        // The shipping gesture first. On the RUNNING screen this reaches refresh() (roster, flags)
        // but the walk observed the push never following it (see the driver's report); the
        // Refresh button under the clock is the other shipping way, so it is tried second and
        // WHICH ONE delivered is recorded for the driver instead of being asserted away.
        Rig.mark("pull")
        pullToRefresh(app)
        var deliveredBy = "none"
        if app.staticTexts["Shift in progress"].waitForExistence(timeout: 12) {
            deliveredBy = "pull"
        } else {
            shot("p2-08-after-pull-not-delivered")
            let refresh = app.buttons["Refresh"]
            if refresh.exists {
                Rig.mark("refresh-button")
                refresh.tap()
                if app.staticTexts["Shift in progress"].waitForExistence(timeout: Rig.timeout) { deliveredBy = "button" }
            }
        }
        Rig.mark("delivered-by-\(deliveredBy)")
        XCTAssertNotEqual(deliveredBy, "none", "after the server is back the queued start is delivered")
        XCTAssertTrue(app.staticTexts["Shift in progress"].exists, "the heading flips to 'Shift in progress'")
        XCTAssertFalse(app.staticTexts["Not confirmed yet"].exists)
        shot("p2-08-delivered-after-pull")
    }

    // MARK: - #10 mock armed

    func testMockArmedManualStartWorksWithNoServer() throws {
        let app = launchSignedIn()
        XCTAssertTrue(Rig.rendezvous("net-down"), "driver flip: the whole network path is down")
        // The DEBUG Simulate section is below the fold of a lazy list.
        let mock = app.buttons["Mock: the server accepts a manual start"]
        var swipes = 0
        while !mock.exists, swipes < 8 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(mock.waitForExistence(timeout: Rig.timeout), "the debug mock button is on the idle list")
        mock.tap()
        for _ in 0..<swipes { app.swipeDown() }
        openSheet(app)
        pickZone(app, "Musterhaus Wien 3 (mock) · Haupteingang (mock)")
        tapStart(app)
        confirmStart(app)
        waitForRunning(app)
        let sheetGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                  object: app.navigationBars["Start without a tag"])
        XCTAssertEqual(XCTWaiter().wait(for: [sheetGone], timeout: 8), .completed, "the sheet closed")
        shot("p2-10-mock-running")
    }

    // MARK: - #11 stop without a tag

    func testFinishWithoutATagClosesTheTapStartedShiftManually() throws {
        // Started by a tap: the DEBUG hook injects exactly the id a tag's URL carries.
        let app = Rig.launch(tap: Rig.zone("A_VER"))
        ensureSignedIn(app, as: "A")
        waitForRunning(app)
        let finish = app.buttons["Finish shift without a tag"]
        var swipes = 0
        while !finish.isHittable, swipes < 6 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(finish.waitForExistence(timeout: Rig.timeout))
        finish.tap()
        let dialog = anyElement(app, containing: "Finish your shift at Rig Haus Alpha now?")
        XCTAssertTrue(dialog.waitForExistence(timeout: Rig.timeout), "the confirmation names the building")
        app.buttons["Finish now"].tap()
        waitForIdle(app)
        XCTAssertFalse(runningHeading(app).exists)
        XCTAssertTrue(app.staticTexts["Manual"].waitForExistence(timeout: Rig.timeout),
                      "the finished row carries the 'Manual' pill")
        shot("p2-11-manual-stop")
    }
}
