//
//  WorkerRigScheduleUITests.swift
//  NFCTimeSheetsUITests
//
//  P4 (TASK-365.5, decision-80) DRIVEN: the worker's PLANNED assignments, read from the rig's
//  real GET /me/schedule. The plan for worker A is shaped by the driver (`rig.sh schedule-set
//  none|one|cross|multi`); load failures are the real thing where the rig can make it real
//  (connection refused = status 0, a revoked session = a real 401) and a front-injected
//  answer where it cannot (a server WITHOUT the route answers 404: the front answers 404 for
//  that path - the status the app sees is the status on the wire).
//
//  What each walk counts on the wire (how many GET /me/schedule a trigger costs) is asserted
//  by the driver from the marks these tests write; this file asserts what the phone SHOWS.
//

import XCTest

final class WorkerRigScheduleUITests: XCTestCase {
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

    private func signedIn() -> XCUIApplication {
        let app = Rig.launch()
        ensureSignedIn(app, as: "A")
        waitForIdle(app)
        return app
    }

    private func summaryButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Next planned assignment")).firstMatch
    }

    /// Expands the collapsed row ("View").
    private func expand(_ app: XCUIApplication) {
        let button = summaryButton(app)
        var swipes = 0
        while !button.exists, swipes < 6 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(button.waitForExistence(timeout: Rig.timeout), "the 'Next planned assignment' row is on screen")
        if !app.staticTexts["My schedule"].exists { button.tap() }
        XCTAssertTrue(app.staticTexts["My schedule"].waitForExistence(timeout: Rig.timeout), "the 'My schedule' card")
    }

    private func line(_ app: XCUIApplication, _ fragment: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    private func bounceTab(_ app: XCUIApplication) {
        app.tabBars.buttons["More"].tap()
        sleep(1)
        app.tabBars.buttons["Shift"].tap()
    }

    // MARK: - idle

    func testP4IdleCollapsedRowShowsTheNextAssignmentInViennaTime() throws {
        let app = signedIn()
        let button = summaryButton(app)
        XCTAssertTrue(button.waitForExistence(timeout: Rig.timeout), "'Next planned assignment' row")
        XCTAssertTrue(button.label.contains("View"), "with the View action spelled in words")
        XCTAssertTrue(app.staticTexts["Rig Haus Alpha"].waitForExistence(timeout: Rig.timeout), "the building under it")
        XCTAssertTrue(line(app, " · 08:00–12:00").waitForExistence(timeout: 5),
                      "the time line is 'date · 08:00–12:00' (Vienna time, same-day form)")
        shot("p4-02-idle-collapsed")
    }

    func testP4ExpandShowsTheCardCaptionAndFirstAssignmentWithNoToggleForOne() throws {
        let app = signedIn()
        expand(app)
        XCTAssertTrue(app.staticTexts["Planned · Clock in separately"].exists, "the caption")
        XCTAssertTrue(app.staticTexts["Rig Haus Alpha"].exists, "the assignment's building")
        XCTAssertTrue(line(app, " · 08:00–12:00").exists, "and its time")
        XCTAssertFalse(app.buttons["All upcoming assignments"].exists, "one assignment: no toggle")
        XCTAssertTrue(app.buttons["Refresh assignments"].exists, "the refresh control, labelled in words")
        shot("p4-03-expanded-one")
    }

    func testP4ExpandMultiHasTheToggleAndListsAllWithNotes() throws {
        let app = signedIn()
        expand(app)
        let toggle = app.buttons["All upcoming assignments"]
        XCTAssertTrue(toggle.waitForExistence(timeout: Rig.timeout), "more than one assignment: the toggle is there")
        XCTAssertTrue(app.staticTexts["Schluessel beim Portier"].exists, "the first assignment's note is shown in full")
        XCTAssertFalse(app.staticTexts["Fenster putzen"].exists, "the later assignment's note is not shown yet")
        toggle.tap()
        XCTAssertTrue(app.staticTexts["Fenster putzen"].waitForExistence(timeout: 5), "the toggle lists the later ones with their notes")
        XCTAssertTrue(app.staticTexts["Rig Haus Beta"].exists, "the second building is listed")
        XCTAssertTrue(app.buttons["Show less"].exists, "and the toggle now says Show less")
        shot("p4-03-expanded-all")
    }

    func testP4CrossMidnightUsesTheLongForm() throws {
        let app = signedIn()
        XCTAssertTrue(app.staticTexts["Rig Haus Alpha"].waitForExistence(timeout: Rig.timeout))
        let long = line(app, ", 22:00 – ")
        XCTAssertTrue(long.waitForExistence(timeout: 5), "'d, 22:00 – d+1, 02:00'")
        XCTAssertTrue(long.label.contains(", 02:00"), "ends at 02:00 on the next day: \(long.label)")
        XCTAssertFalse(long.label.contains(" · "), "never the compact same-day form")
        // the two dates differ
        try? long.label.write(toFile: (Rig.value("TS_RIG_SHOTS") ?? "/dev/null") + "/p4-04-cross-midnight-line.txt",
                              atomically: true, encoding: .utf8)
        shot("p4-04-cross-midnight")
    }

    func testP4EmptyShowsNothingCollapsedAndTheSentenceExpanded() throws {
        let app = signedIn()
        XCTAssertTrue(summaryButton(app).waitForExistence(timeout: Rig.timeout))
        sleep(2)
        XCTAssertFalse(app.staticTexts["Rig Haus Alpha"].exists, "collapsed: nothing under the label")
        XCTAssertFalse(line(app, "08:00").exists, "no time line either")
        shot("p4-05-empty-collapsed")
        expand(app)
        XCTAssertTrue(app.staticTexts["No assignments planned for the next 31 days."].waitForExistence(timeout: 5),
                      "expanded: the 31-day sentence")
        shot("p4-05-empty-expanded")
    }

    // MARK: - failures

    func testP4OfflineShowsTheConnectionSentenceAndTryAgainRefetches() throws {
        let app = signedIn()
        XCTAssertTrue(app.staticTexts["Rig Haus Alpha"].waitForExistence(timeout: Rig.timeout), "loaded while the server is up")
        XCTAssertTrue(Rig.rendezvous("net-down"), "driver flip: front stopped (connection refused: status 0)")
        bounceTab(app)                       // the tab's appearance is the trigger
        sleep(3)
        XCTAssertFalse(app.staticTexts["Rig Haus Alpha"].exists, "collapsed: nothing under the label when the load failed")
        expand(app)
        XCTAssertTrue(app.staticTexts["Could not load assignments without a connection."].waitForExistence(timeout: Rig.timeout),
                      "expanded: 'without a connection'")
        XCTAssertTrue(app.buttons["Try again"].exists, "with Try again")
        shot("p4-06-offline")
        XCTAssertTrue(Rig.rendezvous("net-up"), "driver flip: front started")
        Rig.mark("try-again")
        app.buttons["Try again"].tap()
        XCTAssertTrue(app.staticTexts["Rig Haus Alpha"].waitForExistence(timeout: Rig.timeout),
                      "Try again re-fetches and the assignment is back")
        Rig.mark("try-again-done")
        shot("p4-06-offline-recovered")
    }

    func testP4RouteMissingShowsTheGenericErrorAndTryAgain() throws {
        let app = signedIn()
        sleep(2)
        XCTAssertFalse(app.staticTexts["Rig Haus Alpha"].exists, "collapsed: nothing under the label")
        expand(app)
        XCTAssertTrue(app.staticTexts["Could not load assignments."].waitForExistence(timeout: Rig.timeout),
                      "expanded: the generic sentence (NOT 'without a connection')")
        XCTAssertFalse(app.staticTexts["Could not load assignments without a connection."].exists)
        XCTAssertTrue(app.buttons["Try again"].exists)
        shot("p4-07-route-missing")
        XCTAssertTrue(Rig.rendezvous("fault-clear"), "driver: the route answers again")
        app.buttons["Try again"].tap()
        XCTAssertTrue(app.staticTexts["Rig Haus Alpha"].waitForExistence(timeout: Rig.timeout), "Try again shows the assignment")
    }

    func testP4SessionRevokedSignsOutAndRendersNoScheduleError() throws {
        let app = signedIn()
        XCTAssertTrue(app.staticTexts["Rig Haus Alpha"].waitForExistence(timeout: Rig.timeout))
        XCTAssertTrue(Rig.rendezvous("revoke-A"), "driver flip: A's sessions deleted")
        bounceTab(app)                       // GET /me/schedule -> 401
        XCTAssertTrue(app.textFields["Access code"].waitForExistence(timeout: Rig.timeout), "the app signs out")
        XCTAssertFalse(anyElement(app, containing: "Could not load assignments").exists, "and renders no schedule error")
        shot("p4-08-401-signed-out")
    }

    // MARK: - running screen

    func testP4RunningScreenShowsTheRowBeforeTheHelpCardAndSurvivesTheMinuteTick() throws {
        let app = Rig.launch(tap: Rig.zone("A_VER"))
        ensureSignedIn(app, as: "A")
        waitForRunning(app)
        var swipes = 0
        while !summaryButton(app).exists, swipes < 8 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(summaryButton(app).waitForExistence(timeout: Rig.timeout), "the same row on the running screen")
        // The help sentence is behind its "Shift help" button now (TASK-365.11): the plan still sits before it.
        let help = anyElement(app, containing: "Shift help")
        while !help.exists, swipes < 12 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(help.exists, "the 'Shift help' button is on screen")
        XCTAssertLessThan(summaryButton(app).frame.minY, help.frame.minY, "the schedule row sits before the help button")
        summaryButton(app).tap()
        XCTAssertTrue(app.staticTexts["My schedule"].waitForExistence(timeout: 5))
        shot("p4-09-running-expanded")
        // The running screen redraws once a minute: the card must stay open across a tick.
        sleep(66)
        XCTAssertTrue(app.staticTexts["My schedule"].exists, "expanding does not collapse after the minute tick")
        shot("p4-09-running-after-tick")
    }

    // MARK: - triggers

    func testP4EachResumeTriggerCostsOneFetch() throws {
        let app = signedIn()
        XCTAssertTrue(app.staticTexts["Rig Haus Alpha"].waitForExistence(timeout: Rig.timeout))
        sleep(2)
        Rig.mark("tab-0")
        bounceTab(app)
        sleep(3)
        Rig.mark("tab-1")
        XCUIDevice.shared.press(.home)
        sleep(1)
        Rig.mark("fg-0")
        app.activate()
        sleep(4)
        Rig.mark("fg-1")
        shot("p4-10-after-triggers")
    }

    func testP4StaleSlowAnswerDoesNotOverwriteANewerOne() throws {
        let app = signedIn()
        XCTAssertTrue(app.staticTexts["Rig Haus Alpha"].waitForExistence(timeout: Rig.timeout))
        XCTAssertTrue(line(app, " · 08:00–12:00").exists, "plan 'one' is on screen")
        // fetch #1: the server answers 'one' NOW, the front holds that answer for 8 s
        XCTAssertTrue(Rig.rendezvous("sched-hold-slow"), "driver: answers are held 8 s")
        bounceTab(app)
        sleep(1)
        // the plan changes and the hold is lifted; fetch #2 answers 'cross' at once
        XCTAssertTrue(Rig.rendezvous("sched-fast-cross"), "driver: plan = cross, no hold")
        bounceTab(app)
        XCTAssertTrue(line(app, ", 22:00 – ").waitForExistence(timeout: Rig.timeout), "the newer answer (cross-midnight) is shown")
        shot("p4-10-newer-shown")
        sleep(10)                            // the stale 'one' answer lands during this wait
        XCTAssertTrue(line(app, ", 22:00 – ").exists, "the stale slow answer did not overwrite the newer one")
        XCTAssertFalse(line(app, " · 08:00–12:00").exists)
        shot("p4-10-after-stale")
    }

    func testP4LeavingTheTabMidRequestPaintsNoOfflineSentence() throws {
        let app = signedIn()
        XCTAssertTrue(app.staticTexts["Rig Haus Alpha"].waitForExistence(timeout: Rig.timeout))
        XCTAssertTrue(Rig.rendezvous("sched-hold-slow"), "driver: answers are held 8 s")
        bounceTab(app)                       // request in flight ...
        app.tabBars.buttons["Materials"].tap() // ... leave the tab
        sleep(1)
        app.tabBars.buttons["Shift"].tap()     // come back: a newer load supersedes (cancels) the old one
        expand(app)
        var offlineSeen = false
        let until = Date().addingTimeInterval(14)
        while Date() < until {
            if app.staticTexts["Could not load assignments without a connection."].exists { offlineSeen = true }
            usleep(200_000)
        }
        XCTAssertFalse(offlineSeen, "a cancelled request never paints the offline sentence")
        XCTAssertTrue(app.staticTexts["Rig Haus Alpha"].exists, "and the schedule loads")
        shot("p4-11-cancel")
    }

    // MARK: - identity

    func testP4BNeverSeesAsAssignmentAndStartsLoading() throws {
        let app = signedIn()
        XCTAssertTrue(app.staticTexts["Rig Haus Alpha"].waitForExistence(timeout: Rig.timeout), "A's assignment is shown")
        app.tabBars.buttons["More"].tap()
        signOutFromMore(app)
        XCTAssertTrue(app.textFields["Access code"].waitForExistence(timeout: Rig.timeout))
        XCTAssertTrue(Rig.rendezvous("sched-hold-6s"), "driver: answers are held 6 s")
        XCTAssertTrue(ensureSignedIn(app, as: "B"))
        // B's store starts in Loading: the expanded card says so while the held answer is in flight
        let button = summaryButton(app)
        XCTAssertTrue(button.waitForExistence(timeout: Rig.timeout))
        button.tap()
        // Asked first and fast: the held answer arrives 6 s after B's sign-in.
        let loading = app.staticTexts["Loading assignments …"].waitForExistence(timeout: 3)
        let leaked = app.staticTexts["Rig Haus Alpha"].exists
        shot("p4-12-b-loading")
        XCTAssertTrue(loading, "B's store starts Loading")
        XCTAssertFalse(leaked, "A's assignment is never shown to B")
        XCTAssertTrue(app.staticTexts["No assignments planned for the next 31 days."].waitForExistence(timeout: 12),
                      "B has no plan: the empty sentence follows")
        XCTAssertFalse(app.staticTexts["Rig Haus Alpha"].exists)
        shot("p4-12-b-empty")
    }

    // MARK: - refresh icon, decoupling

    func testP4RefreshIconRefetches() throws {
        let app = signedIn()
        expand(app)
        sleep(2)
        let icon = app.buttons["Refresh assignments"]
        XCTAssertTrue(icon.exists, "VoiceOver reads the refresh icon as 'Refresh assignments'")
        Rig.mark("icon-0")
        icon.tap()
        sleep(3)
        Rig.mark("icon-1")
        XCTAssertTrue(app.staticTexts["Rig Haus Alpha"].exists, "the card still shows the assignment")
        shot("p4-13-refresh-icon")
    }

    func testP4FailingScheduleLeavesClockInAndSyncUntouched() throws {
        var app = signedIn()
        sleep(3)
        backgroundAndKill(app)
        app = Rig.launch(tap: Rig.zone("A_VER"))
        waitForRunning(app)
        XCTAssertTrue(app.staticTexts["Shift in progress"].waitForExistence(timeout: Rig.timeout),
                      "the clock-in is acknowledged although the schedule request fails")
        XCTAssertFalse(app.staticTexts["Not confirmed yet"].exists)
        var swipes = 0
        while !summaryButton(app).exists, swipes < 8 { app.swipeUp(); swipes += 1 }
        summaryButton(app).tap()
        XCTAssertTrue(app.staticTexts["Could not load assignments."].waitForExistence(timeout: Rig.timeout),
                      "the schedule card carries the failure")
        shot("p4-14-running-with-failed-schedule")
        let finish = app.buttons["Finish shift without a tag"]
        swipes = 0
        while !finish.isHittable, swipes < 8 { app.swipeUp(); swipes += 1 }
        finish.tap()
        app.buttons["Finish now"].tap()
        waitForIdle(app)
        XCTAssertTrue(app.staticTexts["Manual"].waitForExistence(timeout: Rig.timeout), "the finish was recorded and delivered")
    }
}
