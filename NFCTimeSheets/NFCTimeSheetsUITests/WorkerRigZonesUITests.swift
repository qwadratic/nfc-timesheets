//
//  WorkerRigZonesUITests.swift
//  NFCTimeSheetsUITests
//
//  P1 (TASK-365.2, decision-43) DRIVEN: a zone card resolves to its BUILDING. The seed has two
//  verified doors in building "Rig Haus Alpha" (Stiege 1, Dachboden) and one in "Rig Haus Beta";
//  taps are the DEBUG `--ts-demo-tap <zone uuid>` hook, the radio is the only thing mocked.
//
//  The server rows and the wire (the building id on a material request, the close's
//  auto_closed flag) are the driver's: ops/ios-rig/walk.sh p1.
//
//  Also here, because it is the same screen and the same cache: two probes that look for a
//  defect found while driving P6 (an OFFLINE manual stop / building switch loses its flag when
//  the open half is delivered). They assert what the product SHOULD do; a red probe is the
//  finding, and the driver prints it as such.
//

import XCTest

final class WorkerRigZonesUITests: XCTestCase {
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

    private func signedInIdle() -> XCUIApplication {
        let app = Rig.launch()
        ensureSignedIn(app, as: "A")
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
        XCTAssertTrue(confirm.waitForExistence(timeout: Rig.timeout))
        confirm.tap()
    }

    // MARK: - a zone created after the phone's roster resolves to its building

    func testP1ZoneCreatedAfterTheRosterResolvesToTheBuildingNameWithoutAPull() throws {
        var app = signedInIdle()
        XCTAssertTrue(Rig.rendezvous("zone-add"), "driver: a NEW verified zone in Rig Haus Alpha, after the phone's roster")
        backgroundAndKill(app)
        guard let zone = Rig.syncValue("zone_NEW") else {
            XCTFail("the driver did not hand over the new zone's id")
            return
        }
        app = Rig.launch(tap: zone)
        waitForRunning(app)
        // never a pull-to-refresh in this test: the name must arrive on its own
        let named = app.staticTexts["Rig Haus Alpha"].waitForExistence(timeout: 15)
        XCTAssertTrue(named, "the running screen names the zone's BUILDING without a manual refresh")
        XCTAssertFalse(app.staticTexts["Unknown location"].exists, "and does not stay on 'Unknown location'")
        shot("p1-new-zone-running")
        finishWithoutTag(app)
        waitForIdle(app)
        XCTAssertTrue(app.staticTexts["Rig Haus Alpha"].waitForExistence(timeout: Rig.timeout), "Recent names the building too")
        openHistory(app)
        XCTAssertTrue(app.staticTexts["Rig Haus Alpha"].waitForExistence(timeout: Rig.timeout), "and so does History")
        shot("p1-new-zone-history")
    }

    // MARK: - same building: the second door closes

    func testP1TapOutAtASecondZoneOfTheSameBuildingClosesTheShift() throws {
        var app = Rig.launch(tap: Rig.zone("A_VER"))
        ensureSignedIn(app, as: "A")
        waitForRunning(app)
        XCTAssertTrue(app.staticTexts["Clocked in"].waitForExistence(timeout: Rig.timeout))
        XCTAssertTrue(app.staticTexts["Rig Haus Alpha"].exists, "the running screen shows the building name")
        shot("p1-same-building-running")
        sleep(3)
        backgroundAndKill(app)
        // the SECOND door of the same building
        app = Rig.launch(tap: Rig.zone("A_DEACT"))
        waitForIdle(app)
        XCTAssertFalse(app.navigationBars["Shift running"].exists, "the shift CLOSED: no new running screen")
        XCTAssertFalse(anyElement(app, containing: "Finished your open shift").exists, "no switch card")
        XCTAssertFalse(anyElement(app, containing: "unfinished shift").exists, "no unresolved banner: it was not a walk-away")
        XCTAssertFalse(app.staticTexts["Auto-closed"].exists, "no 'Auto-closed' pill")
        XCTAssertTrue(app.staticTexts["Rig Haus Alpha"].waitForExistence(timeout: Rig.timeout), "the closed row is in Recent")
        shot("p1-same-building-closed")
    }

    // MARK: - different building: switch card + flagged auto-close

    func testP1TapAtAnotherBuildingSwitchesAndFlagsTheOldRow() throws {
        var app = Rig.launch(tap: Rig.zone("A_VER"))
        ensureSignedIn(app, as: "A")
        waitForRunning(app)
        XCTAssertTrue(app.staticTexts["Clocked in"].waitForExistence(timeout: Rig.timeout))
        sleep(3)
        backgroundAndKill(app)
        app = Rig.launch(tap: Rig.zone("B_VER"))
        waitForRunning(app)
        let card = anyElement(app, containing: "Finished your open shift at Rig Haus Alpha and started at Rig Haus Beta")
        XCTAssertTrue(card.waitForExistence(timeout: Rig.timeout), "the switch notice names BOTH buildings")
        XCTAssertTrue(app.staticTexts["Rig Haus Beta"].exists, "the running screen is at Beta")
        shot("p1-switch-card")
    }

    // MARK: - material request carries the building id

    func testP1MaterialRequestCarriesTheBuildingNotTheZone() throws {
        let app = Rig.launch(tap: Rig.zone("A_VER"))
        ensureSignedIn(app, as: "A")
        waitForRunning(app)
        XCTAssertTrue(app.staticTexts["Clocked in"].waitForExistence(timeout: Rig.timeout))
        app.tabBars.buttons["Materials"].tap()
        let field = app.textFields["What do you need?"]
        XCTAssertTrue(field.waitForExistence(timeout: Rig.timeout), "the request field")
        field.tap()
        field.typeText("Zwei Mopps")
        XCTAssertTrue(anyElement(app, containing: "For Rig Haus Alpha").waitForExistence(timeout: 5),
                      "the form says it is for the BUILDING of the open shift")
        let send = app.buttons["Send request"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        Rig.mark("material-send")
        send.tap()
        XCTAssertTrue(app.staticTexts["Zwei Mopps"].waitForExistence(timeout: Rig.timeout), "the request is listed")
        sleep(3)
        shot("p1-material-sent")
        XCTAssertFalse(anyElement(app, containing: "blocked").exists)
    }

    // MARK: - foreground refetches the roster

    func testP1ComingBackToTheForegroundRefetchesTheRoster() throws {
        let app = signedInIdle()
        Rig.mark("fg-start")
        XCUIDevice.shared.press(.home)
        sleep(2)
        Rig.mark("fg-away")
        app.activate()
        sleep(4)
        Rig.mark("fg-back")
        XCTAssertTrue(app.staticTexts["Your working day"].exists, "back on the idle Shift screen")
    }

    // MARK: - PROBES for a defect: an offline flag must survive delivery

    /// Offline: tap-start, then "Finish shift without a tag", then the server returns. The
    /// close must reach the server as manual (decision-56 section 3: manual_close, corrected).
    func testProbeOfflineManualStopStaysManual() throws {
        var app = signedInIdle()
        backgroundAndKill(app)
        XCTAssertTrue(Rig.rendezvous("net-down"), "driver flip: front stopped")
        app = Rig.launch(tap: Rig.zone("A_VER"))
        waitForRunning(app)
        finishWithoutTag(app)
        waitForIdle(app)
        sleep(2)
        XCTAssertTrue(Rig.rendezvous("net-up"), "driver flip: front started")
        pullToRefresh(app)
        sleep(6)
        shot("probe-offline-manual-stop")
    }

    /// Offline: tap-start at Alpha, then tap at Beta (a walk-away). Delivered later, the old row
    /// must arrive flagged auto_closed so it goes through the resolution screen (decision-10).
    func testProbeOfflineBuildingSwitchStaysFlagged() throws {
        var app = signedInIdle()
        backgroundAndKill(app)
        XCTAssertTrue(Rig.rendezvous("net-down"), "driver flip: front stopped")
        app = Rig.launch(tap: Rig.zone("A_VER"))
        waitForRunning(app)
        sleep(3)
        backgroundAndKill(app)
        app = Rig.launch(tap: Rig.zone("B_VER"))
        waitForRunning(app)
        sleep(2)
        XCTAssertTrue(Rig.rendezvous("net-up"), "driver flip: front started")
        let refresh = app.buttons["Refresh"]
        if refresh.waitForExistence(timeout: 5) { refresh.tap() } else { pullToRefresh(app) }
        sleep(6)
        shot("probe-offline-switch")
    }
}
