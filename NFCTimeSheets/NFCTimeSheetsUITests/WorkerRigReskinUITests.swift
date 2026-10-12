//
//  WorkerRigReskinUITests.swift
//  NFCTimeSheetsUITests
//
//  THE "BLUE HOUR" SCREEN WALKS (TASK-365.9 / .10 / .11, iOS B1-B3) on the worker rig. Where the
//  other WorkerRig* classes walk BEHAVIOUR (what a tap does to the server's rows), this one walks
//  PRESENTATION: it puts the worker's screens in front of the camera in one language, one
//  appearance and one text size and writes a PNG of each. Nothing here asserts a server row; the
//  assertions are the structural ones a screenshot cannot make (three tabs, the History row only
//  while idle, the heading words, that a button is a button).
//
//  THE THREE AXES come from outside the test, so one source walks every combination:
//
//      TS_RIG_LANG   en | de          the app's language (launch argument; the sign-in is always
//                                     done in English first - its form labels are English)
//      TS_RIG_TAG    light-en-m ...   the screenshot prefix: <TS_RIG_SHOTS>/<tag>-<step>.png
//      appearance    xcrun simctl ui <udid> appearance light|dark          (the driver)
//      text size     xcrun simctl ui <udid> content_size <category>        (the driver)
//
//  ops/ios-rig/reskin-walk.sh sets the last two and runs these in order. A test on its own works
//  too (rig.sh test WorkerRigReskinUITests/testIdleAndMore TS_RIG_TAG=x TS_RIG_LANG=de).
//
//  A START IS ALWAYS THE REAL UI: "Start without a tag", a zone, Start, Start shift - in English,
//  because the picker's rows and the dialog's buttons are asserted by label - so the screens are
//  photographed without the DEBUG tap hook's yellow banner above them.
//

import XCTest

final class WorkerRigReskinUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "notifications") { alert in
            for label in ["Allow", "Allow While Using App", "OK", "Erlauben", "Beim Verwenden der App erlauben"]
            where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
    }

    // MARK: - the axes

    private var language: String { Rig.value("TS_RIG_LANG") ?? "en" }
    private var locale: String { language == "de" ? "de_AT" : "en_GB" }
    private var tag: String { Rig.value("TS_RIG_TAG") ?? "walk" }

    /// The words the structural assertions use, per language (Android's German, verbatim).
    private struct Words {
        let shift, materials, more, history, myHours: String
    }
    private var words: Words {
        language == "de"
            ? Words(shift: "Schicht", materials: "Material", more: "Mehr", history: "Verlauf", myHours: "Meine Stunden")
            : Words(shift: "Shift", materials: "Materials", more: "More", history: "History", myHours: "My hours")
    }

    private func snap(_ step: String) { shot("\(tag)-\(step)") }

    // MARK: - launching

    /// A signed-in phone in the walk's language. The session persists across launches, so this
    /// does not touch the sign-in form (testSignInOnce did, in English).
    private func launch(tap: String? = nil) -> XCUIApplication {
        let app = Rig.launch(tap: tap, language: language, locale: locale)
        XCTAssertTrue(app.tabBars.buttons[words.shift].waitForExistence(timeout: Rig.timeout),
                      "a signed-in phone: the '\(words.shift)' tab (run testSignInOnce first)")
        return app
    }

    /// Always English: the manual start's picker rows and dialog buttons are asserted by label.
    private func startShiftManuallyInEnglish() {
        let app = Rig.launch()
        XCTAssertTrue(app.tabBars.buttons["Shift"].waitForExistence(timeout: Rig.timeout), "signed in (testSignInOnce)")
        // A shift finished in the last two minutes (the previous step) is offered as a receipt first,
        // and the receipt REPLACES the start card: Continue brings it back.
        if app.buttons["Continue"].waitForExistence(timeout: 4) { app.buttons["Continue"].tap() }
        let start = idleScreen(app)
        XCTAssertTrue(start.waitForExistence(timeout: Rig.timeout), "'Start without a tag' is on the idle screen")
        start.tap()
        XCTAssertTrue(app.navigationBars["Start without a tag"].waitForExistence(timeout: Rig.timeout))
        let pickerRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Choose a zone")).firstMatch
        XCTAssertTrue(pickerRow.waitForExistence(timeout: Rig.timeout), "the zone picker")
        pickerRow.tap()
        let option = app.buttons["Rig Haus Alpha · Stiege 1"]
        XCTAssertTrue(option.waitForExistence(timeout: Rig.timeout), "the menu offers Stiege 1")
        option.tap()
        let go = app.buttons["Start"]
        XCTAssertTrue(go.waitForExistence(timeout: Rig.timeout) && go.isEnabled)
        go.tap()
        let confirm = app.buttons["Start shift"]
        XCTAssertTrue(confirm.waitForExistence(timeout: Rig.timeout), "the confirmation dialog")
        confirm.tap()
        XCTAssertTrue(app.buttons["Finish shift without a tag"].waitForExistence(timeout: Rig.timeout)
                        || anyElement(app, containing: "Finish shift without a tag").waitForExistence(timeout: 5),
                      "the running screen is up")
        sleep(3)                       // let the open be acknowledged before the app is put away
        backgroundAndKill(app)
    }

    /// Always English, like the start. Leaves the finished row on the phone (and its receipt offered
    /// for two minutes) and puts the app away properly.
    private func finishShiftManuallyInEnglish(killAfter: Bool = true) -> XCUIApplication {
        let app = Rig.launch()
        let finish = app.buttons["Finish shift without a tag"]
        XCTAssertTrue(finish.waitForExistence(timeout: Rig.timeout), "the running screen's quiet finish")
        var swipes = 0
        while !finish.isHittable, swipes < 8 { app.swipeUp(); swipes += 1 }
        finish.tap()
        let now = app.buttons["Finish now"]
        XCTAssertTrue(now.waitForExistence(timeout: Rig.timeout), "the confirmation dialog")
        now.tap()
        XCTAssertTrue(app.buttons["Scan a tag"].waitForExistence(timeout: Rig.timeout)
                        || app.buttons["Continue"].waitForExistence(timeout: 5),
                      "back on the idle screen (the receipt or the start card)")
        if killAfter { sleep(3); backgroundAndKill(app) }
        return app
    }

    // MARK: - sign in (English, once per rig session)

    func testSignInOnce() throws {
        let app = Rig.launch()
        XCTAssertTrue(ensureSignedIn(app, as: "A") || app.tabBars.buttons["Shift"].exists, "worker A is signed in")
        sleep(2)
        dismissSystemAlerts()
        backgroundAndKill(app)
    }

    // MARK: - B2: the idle screen

    private struct IdleWords {
        let heading, ready, scan, manual, recent, noPush, shiftFinished, cont: String
    }
    private var idleWords: IdleWords {
        language == "de"
            ? IdleWords(heading: "Ihr Arbeitstag", ready: "Bereit für die Schicht?", scan: "Tag scannen",
                        manual: "Ohne Tag starten", recent: "Zuletzt", noPush: "Diese App hat kein Push.",
                        shiftFinished: "Schicht beendet", cont: "Weiter")
            : IdleWords(heading: "Your working day", ready: "Ready for your shift?", scan: "Scan a tag",
                        manual: "Start without a tag", recent: "Recent", noPush: "This app has no push.",
                        shiftFinished: "Shift finished", cont: "Continue")
    }

    private func scrollToBottom(_ app: XCUIApplication, steps: Int = 6) {
        for _ in 0..<steps { app.swipeUp() }
    }

    /// Idle with no receipt: the day heading first, then ONE start block; the start question, the
    /// hint, one filled button and a quiet manual start; no Refresh button; no navigation bar.
    func testB2IdleStartCard() throws {
        let app = launch()
        let w = idleWords
        XCTAssertTrue(app.staticTexts[w.heading].waitForExistence(timeout: Rig.timeout), "the day heading '\(w.heading)'")
        // A shift finished in the last two minutes (the previous step) is offered as a receipt first.
        if app.buttons[w.cont].waitForExistence(timeout: 3) { app.buttons[w.cont].tap() }
        XCTAssertTrue(app.staticTexts[w.heading].isHittable || app.staticTexts[w.heading].exists)
        XCTAssertTrue(app.navigationBars.allElementsBoundByIndex.allSatisfy { $0.staticTexts.count == 0 },
                      "the idle screen's navigation bar carries no title (the heading is the first row)")
        XCTAssertTrue(app.staticTexts[w.ready].exists, "the start question '\(w.ready)'")
        XCTAssertTrue(app.buttons[w.scan].exists, "the one filled button '\(w.scan)'")
        XCTAssertTrue(app.buttons[w.manual].exists, "the quiet manual start '\(w.manual)'")
        XCTAssertGreaterThanOrEqual(app.buttons[w.scan].frame.height, 56, "the primary button is at least 56 pt tall: \(app.buttons[w.scan].frame.height)")
        XCTAssertTrue(app.buttons[w.scan].frame.minY < app.buttons[w.manual].frame.minY, "scan above manual")
        XCTAssertFalse(app.buttons["Refresh"].exists || app.buttons["Aktualisieren"].exists, "no Refresh button on the idle list")
        snap("b2-01-idle-top")
        scrollToBottom(app)
        snap("b2-02-idle-bottom")
    }

    /// A finished shift: the receipt takes the start card's place; Continue brings the start card back
    /// and the finished row shows as a card with the range as its dominant line.
    func testB2ReceiptThenRecentCard() throws {
        startShiftManuallyInEnglish()
        _ = finishShiftManuallyInEnglish()
        let app = launch()                       // within two minutes: the receipt is still offered
        let w = idleWords
        XCTAssertTrue(app.staticTexts[w.heading].waitForExistence(timeout: Rig.timeout))
        XCTAssertTrue(app.staticTexts[w.shiftFinished].waitForExistence(timeout: Rig.timeout), "the receipt '\(w.shiftFinished)'")
        XCTAssertFalse(app.staticTexts[w.ready].exists, "the receipt REPLACES the start card")
        sleep(3)                                 // the ring-then-check finishes on its own
        snap("b2-03-idle-receipt")
        let cont = app.buttons[w.cont]
        XCTAssertTrue(cont.waitForExistence(timeout: Rig.timeout), "Continue")
        XCTAssertGreaterThanOrEqual(cont.frame.height, 56, "Continue is the shared primary button")
        cont.tap()
        XCTAssertTrue(app.staticTexts[w.ready].waitForExistence(timeout: Rig.timeout), "Continue brings the start card back")
        XCTAssertTrue(app.staticTexts[w.recent].exists || anyElement(app, containing: w.recent).exists, "Recent lists the finished row")
        snap("b2-04-idle-after-continue")
        scrollToBottom(app)
        snap("b2-05-idle-recent-card")
        XCTAssertTrue(anyElement(app, containing: "Rig Haus Alpha").exists, "the row names the building")
    }

    /// Offline finish: the row says it is WAITING for a connection and when it last tried - never
    /// 'Sending...' - and the delivery row is there; back online it says Sent.
    func testB2UnsentRowSaysWaiting() throws {
        startShiftManuallyInEnglish()
        let app = Rig.launch()
        let finish = app.buttons["Finish shift without a tag"]
        XCTAssertTrue(finish.waitForExistence(timeout: Rig.timeout))
        XCTAssertTrue(Rig.rendezvous("net-down"), "driver flip: front stopped")
        var swipes = 0
        while !finish.isHittable, swipes < 8 { app.swipeUp(); swipes += 1 }
        finish.tap()
        app.buttons["Finish now"].tap()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: Rig.timeout), "the receipt is up")
        sleep(3)
        snap("b2-06-offline-receipt")
        app.buttons["Continue"].tap()
        scrollToBottom(app)
        XCTAssertTrue(anyElement(app, containing: "Waiting for a connection").waitForExistence(timeout: Rig.timeout),
                      "the unsent row says 'Waiting for a connection'")
        XCTAssertFalse(anyElement(app, containing: "Sending").exists, "never 'Sending…'")
        XCTAssertTrue(anyElement(app, containing: "Last tried").exists || anyElement(app, containing: "Not attempted yet").exists,
                      "and when it last tried, or that it has not")
        snap("b2-07-offline-row")
        XCTAssertTrue(Rig.rendezvous("net-up"), "driver flip: front started")
        backgroundAndKill(app)
    }

    // MARK: - B1: three tabs, More, History

    /// Idle: the bottom bar is three destinations; More offers History (a row, not a tab) and it opens.
    func testB1IdleTabsMoreAndHistory() throws {
        let app = launch()
        sleep(2)
        snap("b1-01-shift-tab")
        XCTAssertEqual(app.tabBars.buttons.count, 3, "three tabs, always")
        for name in [words.shift, words.materials, words.more] {
            XCTAssertTrue(app.tabBars.buttons[name].exists, "the '\(name)' tab")
        }
        XCTAssertFalse(app.tabBars.buttons[words.history].exists, "History is never a tab")

        app.tabBars.buttons[words.materials].tap()
        sleep(1)
        snap("b1-02-materials-tab")

        app.tabBars.buttons[words.more].tap()
        let row = app.buttons[words.history]
        XCTAssertTrue(row.waitForExistence(timeout: Rig.timeout), "More offers a '\(words.history)' row while no shift is open")
        XCTAssertTrue(app.buttons[words.myHours].exists, "and keeps 'My hours' beside it")
        snap("b1-03-more-with-history")
        row.tap()
        XCTAssertTrue(app.navigationBars[words.history].waitForExistence(timeout: Rig.timeout),
                      "History is pushed under More (one navigation bar, not two)")
        XCTAssertEqual(app.navigationBars.count, 1, "no second navigation bar inside the pushed History")
        sleep(1)
        snap("b1-04-history-pushed")
    }

    /// Running: still three tabs, and More no longer offers History.
    func testB1RunningStillThreeTabsAndNoHistoryRow() throws {
        startShiftManuallyInEnglish()
        let app = launch()
        sleep(2)
        snap("b1-05-running-tabs")
        XCTAssertEqual(app.tabBars.buttons.count, 3, "three tabs while a shift runs")
        app.tabBars.buttons[words.more].tap()
        sleep(1)
        XCTAssertTrue(app.buttons[words.myHours].waitForExistence(timeout: Rig.timeout), "My hours is still there")
        XCTAssertFalse(app.buttons[words.history].exists, "History is not offered while a shift runs")
        snap("b1-06-more-without-history")
        backgroundAndKill(app)
        _ = finishShiftManuallyInEnglish()
    }
}
