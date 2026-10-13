//
//  WorkerRigMyHoursUITests.swift
//  NFCTimeSheetsUITests
//
//  P7 (TASK-365.8, decision-83) DRIVEN: "My hours", the read-only server list of the worker's last
//  60 days, against the rig's REAL GET /shifts/mine. The rows are put on the SERVER by the driver
//  (ops/ios-rig/walk.sh p7-hours-*) before the phone signs in - the phone has never written them,
//  which is the point of the screen: History cannot show them, this does.
//
//  The phone's zone on this Mac is Europe/Vienna too, so these walks cannot tell "Vienna" from "the
//  phone's zone"; what they do pin is that the SERVER's UTC instants arrive as Vienna wall-clock
//  time (22:30 for 20:30 UTC) and that the date is the Vienna date of the start. The other-zone
//  cases are my-hours-check.swift's (device zone set to Los Angeles, Auckland, UTC).
//

import XCTest

final class WorkerRigMyHoursUITests: XCTestCase {
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

    /// Signs A in and returns the app on whatever the first screen is (a server-side open shift is
    /// adopted, so it may be the running screen: the tab bar is what is waited for).
    private func signedIn() -> XCUIApplication {
        let app = Rig.launch()
        ensureSignedIn(app, as: "A")
        XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: Rig.timeout), "signed in: the tab bar")
        sleep(2)
        dismissSystemAlerts()
        return app
    }

    /// More > My hours. The screen asks the server on every entry.
    private func openMyHours(_ app: XCUIApplication) {
        if app.navigationBars["My hours"].exists { return }
        app.tabBars.buttons["More"].tap()
        let row = app.buttons["My hours"]
        XCTAssertTrue(row.waitForExistence(timeout: Rig.timeout), "More offers 'My hours'")
        row.tap()
        XCTAssertTrue(app.navigationBars["My hours"].waitForExistence(timeout: Rig.timeout), "My hours is pushed")
    }

    private func closeMyHours(_ app: XCUIApplication) {
        let back = app.navigationBars["My hours"].buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5), "the back button")
        back.tap()
        XCTAssertTrue(app.buttons["My hours"].waitForExistence(timeout: Rig.timeout), "back on More")
    }

    private func rows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@ AND label CONTAINS[c] %@", "Date:", "Start:"))
    }

    /// The row whose label holds `fragment` (a date, usually), waited for.
    private func row(_ app: XCUIApplication, containing fragment: String) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS[c] %@ AND label CONTAINS[c] %@", "Start:", fragment)).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: Rig.timeout), "a row with '\(fragment)'")
        return element
    }

    private func screenText(_ app: XCUIApplication) -> String {
        app.staticTexts.allElementsBoundByIndex.filter { $0.exists }.map(\.label).joined(separator: " | ")
    }

    private func note(_ name: String, _ text: String) {
        guard let dir = Rig.value("TS_RIG_SHOTS") else { return }
        try? text.write(toFile: "\(dir)/\(name).txt", atomically: true, encoding: .utf8)
    }

    // MARK: - #12 rows

    /// Seeded by the driver for worker A (Vienna wall-clock times, CEST):
    ///   8 Oct 06:00-14:30 Alpha, tapped                      -> Closed, 8h 30m
    ///   9 Oct 22:30-10 Oct 01:15 Beta, manual, corrected     -> Manual + Corrected, 2h 45m (UTC 20:30)
    ///  11 Oct 07:00-15:00 Alpha, auto-closed, unconfirmed    -> Auto-closed, 8h 0m
    ///  an OPEN shift at Beta, started two hours ago           -> In progress, 'No end yet', no duration
    ///  a shift 70 days old (outside the window) and one of worker B: NOT listed.
    func testP7MyHoursRowsAreTheServersList() throws {
        let app = signedIn()
        openMyHours(app)
        XCTAssertTrue(app.staticTexts["Your shifts from the last 60 days, as stored on the server."].waitForExistence(timeout: Rig.timeout),
                      "the window sentence")
        XCTAssertTrue(row(app, containing: "8 Oct 2026").waitForExistence(timeout: Rig.timeout))
        note("p7-12-rows", screenText(app))
        shot("p7-12-my-hours")

        let closed = row(app, containing: "8 Oct 2026")
        for part in ["Rig Haus Alpha", "Closed", "Date: 8 Oct 2026", "Start: 06:00", "End: 14:30", "Duration: 8h 30m"] {
            XCTAssertTrue(closed.label.contains(part), "closed row has '\(part)': \(closed.label)")
        }
        XCTAssertFalse(closed.label.contains("Manual"), "a tapped shift is not 'Manual': \(closed.label)")

        let manual = row(app, containing: "9 Oct 2026")
        for part in ["Rig Haus Beta", "Manual", "Corrected", "Date: 9 Oct 2026", "Start: 22:30", "End: 01:15", "Duration: 2h 45m"] {
            XCTAssertTrue(manual.label.contains(part), "manual row has '\(part)': \(manual.label)")
        }
        XCTAssertFalse(manual.label.contains("20:30"), "Vienna wall-clock, not UTC: \(manual.label)")

        let auto = row(app, containing: "11 Oct 2026")
        for part in ["Rig Haus Alpha", "Auto-closed", "Start: 07:00", "End: 15:00", "Duration: 8h 0m"] {
            XCTAssertTrue(auto.label.contains(part), "auto-closed row has '\(part)': \(auto.label)")
        }

        let open = row(app, containing: "No end yet")
        XCTAssertTrue(open.label.contains("Rig Haus Beta"), "the open row names its building: \(open.label)")
        XCTAssertTrue(open.label.contains("In progress"), "the open row says 'In progress': \(open.label)")
        XCTAssertFalse(open.label.contains("Duration"), "and has NO duration: \(open.label)")
        XCTAssertFalse(open.label.contains("End:"), "and no end time: \(open.label)")
        note("p7-12-open-row", open.label)

        XCTAssertFalse(app.staticTexts["Unknown location"].exists, "no 'Unknown location'")
        XCTAssertEqual(rows(app).count, 4, "exactly the four rows inside the window and of THIS worker (not the 70-day-old one, not B's)")
        XCTAssertFalse(anyText(app, containing: "09:11"), "worker B's shift is not listed")
        XCTAssertFalse(anyText(app, containing: "total", caseInsensitive: true) || anyText(app, containing: "€"), "no total, no amount")
    }

    private func anyText(_ app: XCUIApplication, containing text: String, caseInsensitive: Bool = false) -> Bool {
        app.descendants(matching: .any).matching(NSPredicate(format: caseInsensitive ? "label CONTAINS[c] %@" : "label CONTAINS %@", text)).count > 0
    }

    // MARK: - #13 empty

    func testP7MyHoursEmptyList() throws {
        let app = signedIn()
        openMyHours(app)
        XCTAssertTrue(app.staticTexts["No shifts in this period."].waitForExistence(timeout: Rig.timeout), "the empty sentence")
        XCTAssertEqual(rows(app).count, 0, "no rows")
        XCTAssertFalse(app.buttons["Refresh"].exists, "an empty list is not a failure: no Refresh")
        shot("p7-13-empty")
    }

    // MARK: - #13 server down, a server error, a rejected session

    func testP7MyHoursOfflineGenericErrorAndSignedOut() throws {
        let app = signedIn()
        let offline = "No connection. Your hours can't be loaded right now."
        let generic = "Your hours could not be loaded."

        // 1. the server is unreachable (connection refused: status 0)
        XCTAssertTrue(Rig.rendezvous("net-down"), "driver: the front is stopped")
        openMyHours(app)
        XCTAssertTrue(app.staticTexts[offline].waitForExistence(timeout: Rig.timeout), "the offline sentence")
        XCTAssertTrue(app.buttons["Refresh"].exists, "with Refresh")
        XCTAssertFalse(app.staticTexts[generic].exists, "and not the generic one")
        shot("p7-13-offline")
        XCTAssertTrue(Rig.rendezvous("net-up"), "driver: the front is started again")
        app.buttons["Refresh"].tap()
        XCTAssertTrue(row(app, containing: "8 Oct 2026").exists, "after Refresh the rows are there")
        XCTAssertFalse(app.staticTexts[offline].exists, "and the sentence is gone")
        shot("p7-13-after-refresh")

        // 2. a server error (500): the generic sentence
        closeMyHours(app)
        XCTAssertTrue(Rig.rendezvous("fault-500-mine"), "driver: GET /shifts/mine answers 500")
        openMyHours(app)
        XCTAssertTrue(app.staticTexts[generic].waitForExistence(timeout: Rig.timeout), "the generic sentence")
        XCTAssertTrue(app.buttons["Refresh"].exists, "with Refresh")
        XCTAssertFalse(app.staticTexts[offline].exists, "and not the offline one")
        shot("p7-13-generic")
        XCTAssertTrue(Rig.rendezvous("fault-clear"), "driver: faults cleared")
        app.buttons["Refresh"].tap()
        XCTAssertTrue(row(app, containing: "8 Oct 2026").exists, "after Refresh the rows are there")

        // 3. the session is rejected (401): nothing is painted on the way out
        closeMyHours(app)
        XCTAssertTrue(Rig.rendezvous("revoke-A"), "driver: A's session rows are deleted")
        // not openMyHours(): the 401 can sign the worker out before the pushed screen is ever seen
        let row = app.buttons["My hours"]
        XCTAssertTrue(row.waitForExistence(timeout: Rig.timeout), "More offers 'My hours'")
        row.tap()
        var painted = false
        let until = Date().addingTimeInterval(Rig.timeout)
        while Date() < until, !app.textFields["Access code"].exists {
            if app.staticTexts[offline].exists || app.staticTexts[generic].exists { painted = true }
            usleep(100_000)
        }
        XCTAssertFalse(painted, "a 401 paints neither failure sentence")
        XCTAssertTrue(app.textFields["Access code"].exists, "the worker is signed out (the code form)")
        shot("p7-13-signed-out")
    }

    // MARK: - #14 an admin correction

    func testP7MyHoursShowsAnAdminCorrection() throws {
        let app = signedIn()
        openMyHours(app)
        let before = row(app, containing: "11 Oct 2026")
        XCTAssertTrue(before.label.contains("Auto-closed"), "before: 'Auto-closed': \(before.label)")
        XCTAssertFalse(before.label.contains("Corrected"), "and not 'Corrected': \(before.label)")
        XCTAssertTrue(before.label.contains("End: 15:00"), "before: the 8-hour guess 15:00: \(before.label)")
        note("p7-14-before", before.label)
        shot("p7-14-before")

        closeMyHours(app)
        XCTAssertTrue(Rig.rendezvous("admin-correct"), "driver: corrected_at set, end_time 14:20, by SQL (the admin's resolve)")
        openMyHours(app)
        let after = row(app, containing: "11 Oct 2026")
        XCTAssertTrue(after.label.contains("Corrected"), "after: 'Corrected': \(after.label)")
        XCTAssertFalse(after.label.contains("Auto-closed"), "no longer 'Auto-closed': \(after.label)")
        XCTAssertTrue(after.label.contains("End: 14:20"), "the corrected end 14:20: \(after.label)")
        XCTAssertTrue(after.label.contains("Duration: 7h 20m"), "and its duration: \(after.label)")
        note("p7-14-after", after.label)
        shot("p7-14-after")
    }
}
