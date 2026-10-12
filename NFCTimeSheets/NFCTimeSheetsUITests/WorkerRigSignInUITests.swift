//
//  WorkerRigSignInUITests.swift
//  NFCTimeSheetsUITests
//
//  TASK-365.22 criterion 2: a WORKER signs in through the REAL code form against the rig's
//  loopback server and reaches the idle screen. Also the two small steps the shared-phone
//  walks (P3) are built from: sign out through Settings, and sign in as the other worker.
//
//  Run through the rig (it exports the fresh code and the loopback build settings):
//
//      ops/ios-rig/rig.sh new-code A
//      ops/ios-rig/rig.sh test WorkerRigSignInUITests/testWorkerSignsInThroughTheCodeFormAndReachesIdle
//
//  The test asserts what the PHONE shows. What the SERVER now holds (one worker session, the
//  code redeemed) is asserted by ops/ios-rig/walk.sh with psql, because a UI test cannot and
//  should not talk to the database.
//

import XCTest

final class WorkerRigSignInUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // A first clock-in asks for notification permission; the rig answers Allow so the
        // out-of-app signals (badge, reminders) exist to be observed.
        addUIInterruptionMonitor(withDescription: "notifications") { alert in
            for label in ["Allow", "Allow While Using App", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
    }

    /// Criterion 2: the real form, the real code, the idle screen.
    func testWorkerSignsInThroughTheCodeFormAndReachesIdle() throws {
        let app = Rig.launch()

        // The signed-out screen draws the form the worker uses.
        XCTAssertTrue(app.textFields["Access code"].waitForExistence(timeout: Rig.timeout),
                      "the sign-in screen with the access-code field (a fresh container: rig.sh sim-uninstall)")
        XCTAssertTrue(app.buttons["Sign in with code"].exists)
        XCTAssertFalse(app.buttons["Sign in with code"].isEnabled, "no code typed yet: the submit is disabled")
        shot("signin-01-form")

        XCTAssertTrue(ensureSignedIn(app, as: "A"), "this run signed in through the form")
        waitForIdle(app)
        XCTAssertTrue(app.buttons["Scan a tag"].exists, "the idle screen's primary action")
        XCTAssertEqual(app.tabBars.buttons.count, 3, "three tabs, always (TASK-365.9): Shift, Materials, More")
        XCTAssertFalse(app.tabBars.buttons["History"].exists, "History is never a tab: it is a row under More")
        shot("signin-02-idle")

        // The server's answer to GET /auth/session is what Settings shows, never a local guess.
        app.tabBars.buttons["More"].tap()
        XCTAssertTrue(app.staticTexts["Signed in as Anna Rig"].waitForExistence(timeout: Rig.timeout)
                        || anyElement(app, containing: "Anna Rig").waitForExistence(timeout: 5),
                      "Settings > Signed in as shows the worker the SERVER says holds the session")
        shot("signin-03-settings")
    }

    /// The same, as worker B (a second person on the same phone, P3).
    func testWorkerBSignsInThroughTheCodeFormAndReachesIdle() throws {
        let app = Rig.launch()
        XCTAssertTrue(app.textFields["Access code"].waitForExistence(timeout: Rig.timeout),
                      "signed out (the previous test signed A out)")
        XCTAssertTrue(ensureSignedIn(app, as: "B"))
        waitForIdle(app)
        app.tabBars.buttons["More"].tap()
        XCTAssertTrue(anyElement(app, containing: "Bernd Rig").waitForExistence(timeout: Rig.timeout),
                      "Settings > Signed in as shows Bernd Rig")
        shot("signin-b-settings")
    }

    /// More > Sign out, then the confirmation's Sign out (TASK-365.13): back on the sign-in screen.
    func testSignOutReturnsToTheSignInScreen() throws {
        let app = Rig.launch()
        XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: Rig.timeout),
                      "a worker is signed in (run the sign-in test first)")
        app.tabBars.buttons["More"].tap()
        signOutFromMore(app)
        XCTAssertTrue(app.textFields["Access code"].waitForExistence(timeout: Rig.timeout),
                      "signing out lands on the sign-in screen")
        shot("signout-01-signin")
    }
}
