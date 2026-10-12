//
//  WorkerRigSharedPhoneUITests.swift
//  NFCTimeSheetsUITests
//
//  P3 (TASK-365.4) DRIVEN: two workers on one phone. Worker A is the one who leaves a shift
//  open, worker B is the colleague who is handed the phone. What each screen shows is asserted
//  here; the server's rows are asserted by ops/ios-rig/walk.sh p3.
//
//  THE BADGE IS NOT RELIABLY OBSERVABLE HERE, and this file does not pretend otherwise. The
//  app icon's accessibility label on this Simulator never carries a badge (label and value
//  read "NFCTimeSheets" / "" with a shift running and the permission granted), and the
//  static home grid showed no badge in 17 screenshots over ~40 s, although one frame of the
//  launch animation did draw a red "1" on the icon. So the walks below record what the icon
//  said (marks.txt) and a picture of the home screen, and assert NOTHING about the badge.
//  Pending and delivered reminders are not observable from a UI test either
//  (UNUserNotificationCenter has no out-of-process reader). The criteria that name the badge
//  or the reminders therefore stay open; what IS asserted is everything else they say.
//

import UIKit
import XCTest

final class WorkerRigSharedPhoneUITests: XCTestCase {
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

    private static var homeShots = 0

    /// "<label>, <value>" of the app's home-screen icon, whatever Springboard calls it. Goes Home
    /// and comes back, so the app is in the foreground again afterwards.
    private func appIconLabel(_ app: XCUIApplication) -> String {
        XCUIDevice.shared.press(.home)
        // Springboard draws a badge a moment after the app resigns: read it too early and a
        // badge that IS set reads as 0 (found on the first run: the badge appeared in the
        // picture taken as the app was re-activated).
        sleep(3)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // The icon is called by the bundle's display name ("NFCTimeSheets"); a badge shows up
        // either in its label ("NFCTimeSheets, 1 notification") or in its value.
        let icon = springboard.icons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", "NFCTimeSheets", "NFCTimeSheets,")).firstMatch
        let found = icon.waitForExistence(timeout: 8)
        Self.homeShots += 1
        shot("p3-home-screen-\(Self.homeShots)")
        let label = found ? "\(icon.label), \((icon.value as? String) ?? "")" : "NO-ICON-FOUND"
        if let dir = Rig.value("TS_RIG_SHOTS") {
            try? springboard.debugDescription.write(toFile: "\(dir)/springboard-hierarchy-\(Self.homeShots).txt", atomically: true, encoding: .utf8)
        }
        app.activate()
        return label
    }

    /// The numeric badge from the icon label ("NFC TimeSheets, 1 notification" -> 1; no
    /// badge -> 0).
    private func badge(_ app: XCUIApplication) -> Int {
        let label = appIconLabel(app)
        let digits = label.split(separator: ",").dropFirst().joined().filter(\.isNumber)
        Rig.mark("icon-label-\(label.filter { $0.isLetter || $0.isNumber || $0 == " " }.replacingOccurrences(of: " ", with: "_"))")
        return Int(digits) ?? 0
    }

    /// The notifications permission alert is SpringBoard's, so the app's interruption monitor
    /// only sees it when the test touches the app: answer it directly.
    private func allowNotificationsIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 6) {
            allow.tap()
            Rig.mark("notifications-allowed")
        } else {
            Rig.mark("notifications-alert-not-found")
        }
    }

    private func signOut(_ app: XCUIApplication) {
        app.tabBars.buttons["More"].tap()
        signOutFromMore(app)
        XCTAssertTrue(app.textFields["Access code"].waitForExistence(timeout: Rig.timeout), "the sign-in screen")
    }

    private func finishWithoutTag(_ app: XCUIApplication) {
        let finish = app.buttons["Finish shift without a tag"]
        var swipes = 0
        while !finish.isHittable, swipes < 8 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(finish.waitForExistence(timeout: Rig.timeout))
        finish.tap()
        let confirm = app.buttons["Finish now"]
        XCTAssertTrue(confirm.waitForExistence(timeout: Rig.timeout))
        confirm.tap()
    }

    /// Worker A taps in at Stiege 1 (the DEBUG hook), the notification permission is answered,
    /// and A signs out WITHOUT finishing: the phone is now "handed to a colleague".
    @discardableResult
    private func aStartsAShiftAndSignsOut() -> XCUIApplication {
        let app = Rig.launch(tap: Rig.zone("A_VER"))
        ensureSignedIn(app, as: "A")
        waitForRunning(app)
        allowNotificationsIfAsked()
        XCTAssertTrue(app.staticTexts["Shift in progress"].waitForExistence(timeout: Rig.timeout))
        sleep(2)
        signOut(app)
        return app
    }

    // MARK: - #1 sign-out tears down the badge

    func testP3SignOutTearsDownTheBadgeAndKeepsTheShift() throws {
        let app = Rig.launch(tap: Rig.zone("A_VER"))
        ensureSignedIn(app, as: "A")
        waitForRunning(app)
        allowNotificationsIfAsked()
        XCTAssertTrue(app.staticTexts["Shift in progress"].waitForExistence(timeout: Rig.timeout))
        sleep(2)
        let before = badge(app)          // observed, not asserted (see the header)
        Rig.mark("badge-before-signout-\(before)")
        waitForRunning(app)
        signOut(app)
        shot("p3-01-signin-after-signout")
        sleep(2)
        let after = badge(app)
        Rig.mark("badge-after-signout-\(after)")   // observed, not asserted (see the header)
    }

    // MARK: - #2 B signs in: nothing of A's

    func testP3BSignsInAndSeesNothingOfAs() throws {
        let app = aStartsAShiftAndSignsOut()
        XCTAssertTrue(ensureSignedIn(app, as: "B"))
        waitForIdle(app)
        XCTAssertFalse(runningHeading(app).exists, "B gets the idle Shift screen, not A's running screen")
        XCTAssertEqual(app.tabBars.buttons.count, 3, "three tabs, always (TASK-365.9): Shift, Materials, More - History is never one")
        XCTAssertTrue(app.staticTexts["No completed shifts yet."].waitForExistence(timeout: Rig.timeout),
                      "Recent holds none of A's rows")
        openHistory(app)
        XCTAssertTrue(app.staticTexts["No shifts yet."].waitForExistence(timeout: Rig.timeout), "History holds none of A's rows")
        XCTAssertTrue(anyElement(app, containing: "0.0 h").exists, "and the totals are B's: 0.0 h")
        app.tabBars.buttons["Materials"].tap()
        XCTAssertTrue(app.staticTexts["Materials"].waitForExistence(timeout: Rig.timeout) || app.navigationBars["Materials"].exists)
        XCTAssertFalse(anyElement(app, containing: "For Rig Haus Alpha").exists,
                       "Materials does not offer A's building as B's request context")
        shot("p3-02-b-materials")
        Rig.mark("badge-for-b-\(badge(app))")      // observed, not asserted (see the header)
    }

    // MARK: - #3 B taps the same place as A's open row

    func testP3BTapsTheSamePlaceAsAsOpenRow() throws {
        let app = aStartsAShiftAndSignsOut()
        XCTAssertTrue(ensureSignedIn(app, as: "B"))
        waitForIdle(app)
        sleep(2)
        backgroundAndKill(app)
        let tapped = Rig.launch(tap: Rig.zone("A_VER"))
        waitForRunning(tapped)
        XCTAssertTrue(tapped.staticTexts["Shift in progress"].waitForExistence(timeout: Rig.timeout),
                      "B gets B's OWN running shift")
        XCTAssertFalse(anyElement(tapped, containing: "Finished your open shift").exists, "no switch card")
        XCTAssertFalse(anyElement(tapped, containing: "unfinished shift").exists, "and nothing is flagged for resolution")
        shot("p3-03-b-own-shift")
    }

    // MARK: - #4 B taps elsewhere

    func testP3BTapsAnotherBuilding() throws {
        let app = aStartsAShiftAndSignsOut()
        XCTAssertTrue(ensureSignedIn(app, as: "B"))
        waitForIdle(app)
        sleep(2)
        backgroundAndKill(app)
        let tapped = Rig.launch(tap: Rig.zone("B_VER"))
        waitForRunning(tapped)
        XCTAssertTrue(tapped.staticTexts["Rig Haus Beta"].waitForExistence(timeout: Rig.timeout), "B's shift is at Beta")
        XCTAssertFalse(anyElement(tapped, containing: "Finished your open shift").exists, "no switch card")
        XCTAssertFalse(anyElement(tapped, containing: "unfinished shift").exists, "no auto-closed row to resolve")
        shot("p3-04-b-elsewhere")
    }

    // MARK: - #5 A returns

    func testP3AReturnsAndHerShiftIsThereToClose() throws {
        let app = aStartsAShiftAndSignsOut()
        XCTAssertTrue(ensureSignedIn(app, as: "B"))
        waitForIdle(app)
        signOut(app)
        // a new single-use code for A (the first was spent): the driver writes it
        XCTAssertTrue(Rig.rendezvous("new-code-A"), "driver: a fresh code for A")
        XCTAssertTrue(ensureSignedIn(app, as: "A"))
        waitForRunning(app)
        XCTAssertTrue(app.staticTexts["Shift in progress"].waitForExistence(timeout: Rig.timeout),
                      "A's running screen is back: the local row was kept")
        sleep(3)
        Rig.mark("badge-after-return-\(badge(app))")   // observed, not asserted (see the header)
        shot("p3-05-a-returns")
        // a tag tap at A's own zone closes A's row
        let again = Rig.launch(tap: Rig.zone("A_VER"))
        waitForIdle(again)
        XCTAssertTrue(again.staticTexts["Rig Haus Alpha"].waitForExistence(timeout: Rig.timeout), "A's finished row is in Recent")
        shot("p3-05-a-closed")
    }

    // MARK: - #6 session rejected mid-shift

    func testP3SessionRevokedMidShiftDropsToSignedOut() throws {
        let app = Rig.launch(tap: Rig.zone("A_VER"))
        ensureSignedIn(app, as: "A")
        waitForRunning(app)
        allowNotificationsIfAsked()
        sleep(3)
        Rig.mark("badge-before-revoke-\(badge(app))")  // observed, not asserted (see the header)
        XCTAssertTrue(Rig.rendezvous("revoke-A"), "driver flip: worker A's sessions deleted on the server")
        // "trigger any request": the Refresh the worker has (pull) - or coming back to the app
        XCUIDevice.shared.press(.home)
        sleep(1)
        app.activate()
        XCTAssertTrue(app.textFields["Access code"].waitForExistence(timeout: Rig.timeout),
                      "the next request is a 401 and the app drops to the sign-in screen")
        XCTAssertTrue(anyElement(app, containing: "Your session ended").waitForExistence(timeout: 5), "with the reason")
        shot("p3-06-session-ended")
        sleep(2)
        Rig.mark("badge-after-revoke-\(badge(app))")   // observed, not asserted (see the header)
    }

    // MARK: - #7 cached A, the server answers B

    func testP3WorkerReplacedWithoutSignedOut() throws {
        // A has one finished shift on the phone (a row B must not see)
        var app = Rig.launch(tap: Rig.zone("A_VER"))
        ensureSignedIn(app, as: "A")
        waitForRunning(app)
        allowNotificationsIfAsked()
        sleep(2)
        finishWithoutTag(app)
        waitForIdle(app)
        XCTAssertTrue(app.staticTexts["Rig Haus Alpha"].waitForExistence(timeout: Rig.timeout), "A's row is in Recent")
        sleep(2)
        backgroundAndKill(app)
        XCTAssertTrue(Rig.rendezvous("fault-session-b"), "driver: GET /auth/session will answer 'Bernd Rig' after 4 s")
        app = Rig.launch()
        // first the cached identity is on screen (A's rows), then the server's answer replaces it
        let sawA = app.staticTexts["Rig Haus Alpha"].waitForExistence(timeout: 3)
        Rig.mark(sawA ? "cached-a-rows-visible" : "cached-a-rows-not-seen")
        shot("p3-07-cached-a")
        // The TabView is rebuilt for the new identity (.id(worker.id)), which also puts the
        // selection back on the Log tab: so keep opening Settings until the server's answer
        // (after the 4 s delay) is what it shows.
        var replaced = false
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, !replaced {
            if app.tabBars.buttons["More"].exists { app.tabBars.buttons["More"].tap() }
            replaced = anyElement(app, containing: "Bernd Rig").waitForExistence(timeout: 2)
        }
        XCTAssertTrue(replaced, "the server's answer replaces the cached worker (no signed-out in between)")
        app.tabBars.buttons["Shift"].tap()
        waitForIdle(app)
        XCTAssertTrue(app.staticTexts["No completed shifts yet."].waitForExistence(timeout: Rig.timeout),
                      "none of A's rows: Recent is empty for B")
        shot("p3-07-replaced-b")
        openHistory(app)
        XCTAssertTrue(app.staticTexts["No shifts yet."].waitForExistence(timeout: Rig.timeout), "nor in History")
    }

    // MARK: - #8 swipe-delete as B

    func testP3SwipeDeleteAsBOnlyRemovesBsRows() throws {
        // A leaves a FINISHED row on the phone, then B works a shift of their own.
        var app = Rig.launch(tap: Rig.zone("A_VER"))
        ensureSignedIn(app, as: "A")
        waitForRunning(app)
        allowNotificationsIfAsked()
        sleep(2)
        finishWithoutTag(app)
        waitForIdle(app)
        sleep(3)
        signOut(app)
        XCTAssertTrue(ensureSignedIn(app, as: "B"))
        waitForIdle(app)
        sleep(4)
        backgroundAndKill(app)
        app = Rig.launch(tap: Rig.zone("B_VER"))
        waitForRunning(app)
        sleep(2)
        finishWithoutTag(app)
        waitForIdle(app)
        openHistory(app)
        let bRow = app.staticTexts["Rig Haus Beta"]
        XCTAssertTrue(bRow.waitForExistence(timeout: Rig.timeout), "History lists B's row (Rig Haus Beta)")
        XCTAssertFalse(app.staticTexts["Rig Haus Alpha"].exists,
                       "and ONLY B's row: A's finished row (Rig Haus Alpha) is not listed")
        shot("p3-08-history-b")
        bRow.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "swipe reveals Delete on B's row")
        delete.tap()
        XCTAssertTrue(app.staticTexts["No shifts yet."].waitForExistence(timeout: Rig.timeout), "B's row is gone")
        // A's row is still on the phone for A
        signOut(app)
        XCTAssertTrue(Rig.rendezvous("new-code-A"), "driver: a fresh code for A")
        XCTAssertTrue(ensureSignedIn(app, as: "A"))
        waitForIdle(app)
        openHistory(app)
        XCTAssertTrue(app.staticTexts["Rig Haus Alpha"].waitForExistence(timeout: Rig.timeout),
                      "A's own finished row survived B's delete")
        shot("p3-08-history-a")
    }

    // MARK: - P6 #10: another account's unsent row counts on B's screen, never in B's lists

    func testP6DeviceWideCountsAndWorkerScopedLists() throws {
        var app = Rig.launch()
        ensureSignedIn(app, as: "A")
        waitForIdle(app)
        sleep(3)
        XCTAssertTrue(Rig.rendezvous("net-down"), "driver flip: front stopped")
        backgroundAndKill(app)
        app = Rig.launch(tap: Rig.zone("A_VER"))
        waitForRunning(app)
        finishWithoutTag(app)
        waitForIdle(app)
        sleep(3)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "still on this phone")).firstMatch
                        .waitForExistence(timeout: Rig.timeout), "A's unsent row is waiting")
        signOut(app)
        XCTAssertTrue(Rig.rendezvous("net-up"), "driver flip: front started")
        XCTAssertTrue(ensureSignedIn(app, as: "B"))
        waitForIdle(app)
        sleep(4)
        let any = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "on this phone")).firstMatch
        let blocked = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "your office")).firstMatch
        XCTAssertTrue(any.exists || blocked.exists,
                      "B's counts include A's row (as blocked: wrong account, or still waiting)")
        Rig.mark(blocked.exists ? "b-sees-blocked-row" : "b-sees-waiting-row")
        shot("p6-10-b-counts")
        XCTAssertTrue(app.staticTexts["No completed shifts yet."].exists, "but B's Recent list holds none of A's rows")
        openHistory(app)
        XCTAssertTrue(app.staticTexts["No shifts yet."].waitForExistence(timeout: Rig.timeout), "nor B's History")
    }
}
