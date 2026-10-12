//
//  WorkerRigReskinUITests.swift
//  NFCTimeSheetsUITests
//
//  THE "BLUE HOUR" SCREEN WALKS (TASK-365.9 / .10 / .11 / .12 / .13, iOS B1-B5) on the worker rig. Where the
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
        dismissReceiptIfShown(app, shifted: "Shift finished", cont: "Continue")
        let start = app.buttons["Start without a tag"]
        var swipes = 0
        while !start.isHittable, swipes < 14 { app.swipeUp(); swipes += 1 }
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
        XCTAssertTrue(app.staticTexts["Your working day"].waitForExistence(timeout: Rig.timeout),
                      "back on the idle screen (heading 'Your working day'; the receipt or the start card below it)")
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

    private func scrollToTop(_ app: XCUIApplication, steps: Int = 4) {
        for _ in 0..<steps { app.swipeDown() }
    }

    /// The receipt of a shift finished in the last two minutes REPLACES the start card; at the largest text
    /// sizes its Continue button is below the fold of the lazy list, so it is scrolled to before it is tapped.
    private func dismissReceiptIfShown(_ app: XCUIApplication, shifted: String, cont: String) {
        guard app.staticTexts[shifted].waitForExistence(timeout: 4) else { return }
        let button = app.buttons[cont]
        var swipes = 0
        while !button.isHittable, swipes < 10 { app.swipeUp(); swipes += 1 }
        if button.exists { button.tap() }
        scrollToTop(app)
    }

    /// Idle with no receipt: the day heading first, then ONE start block; the start question, the
    /// hint, one filled button and a quiet manual start; no Refresh button; no navigation bar.
    func testB2IdleStartCard() throws {
        let app = launch()
        let w = idleWords
        XCTAssertTrue(app.staticTexts[w.heading].waitForExistence(timeout: Rig.timeout), "the day heading '\(w.heading)'")
        // A shift finished in the last two minutes (the previous step) is offered as a receipt first.
        dismissReceiptIfShown(app, shifted: w.shiftFinished, cont: w.cont)
        XCTAssertTrue(app.staticTexts[w.heading].isHittable || app.staticTexts[w.heading].exists)
        XCTAssertTrue(app.navigationBars.allElementsBoundByIndex.allSatisfy { $0.staticTexts.count == 0 },
                      "the idle screen's navigation bar carries no title (the heading is the first row)")
        XCTAssertTrue(app.staticTexts[w.ready].exists, "the start question '\(w.ready)'")
        XCTAssertTrue(app.buttons[w.scan].exists, "the one filled button '\(w.scan)'")
        XCTAssertTrue(app.buttons[w.manual].exists, "the quiet manual start '\(w.manual)'")
        XCTAssertGreaterThanOrEqual(app.buttons[w.scan].frame.height, 56, "the primary button is at least 56 pt tall: \(app.buttons[w.scan].frame.height)")
        XCTAssertTrue(app.buttons[w.scan].frame.minY < app.buttons[w.manual].frame.minY, "scan above manual")
        XCTAssertFalse(app.buttons["Refresh"].exists || app.buttons["Aktualisieren"].exists, "no Refresh button on the idle list")
        scrollToTop(app)
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
        var swipes = 0
        while !cont.exists, swipes < 10 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(cont.waitForExistence(timeout: Rig.timeout), "Continue")
        XCTAssertGreaterThanOrEqual(cont.frame.height, 56, "Continue is the shared primary button")
        cont.tap()
        scrollToTop(app)
        XCTAssertTrue(app.staticTexts[w.ready].waitForExistence(timeout: Rig.timeout), "Continue brings the start card back")
        snap("b2-04-idle-after-continue")
        // At the largest text sizes the start card alone is a screen: scroll until the Recent header is drawn.
        var scrolled = 0
        while !app.staticTexts[w.recent].exists, scrolled < 12 { app.swipeUp(); scrolled += 1 }
        XCTAssertTrue(app.staticTexts[w.recent].exists, "Recent lists the finished row")
        // The row is a few swipes below its header at the largest sizes.
        var below = 0
        while !app.staticTexts["Rig Haus Alpha"].exists, below < 8 { app.swipeUp(); below += 1 }
        XCTAssertTrue(app.staticTexts["Rig Haus Alpha"].exists, "the row names the building")
        snap("b2-05-idle-recent-card")
    }

    /// A finished row whose close is IN FLIGHT and unanswered (the front holds POST /shifts/close): it is
    /// neither refused nor delivered, so it carries no failure sentence - it says it is WAITING for a
    /// connection and when it last tried, never "Sending...". (A row that FAILED says the failure instead:
    /// Android's markFailed always leaves a sentence, and so does this port.)
    ///
    /// The finish is done in English; the phone is put away mid-request and relaunched in the WALK's
    /// language, where the same row is still unsent (the relaunch's own push is held by the same fault).
    func testB2UnsentRowSaysWaiting() throws {
        startShiftManuallyInEnglish()
        let app0 = Rig.launch()
        let finish = app0.buttons["Finish shift without a tag"]
        XCTAssertTrue(finish.waitForExistence(timeout: Rig.timeout))
        XCTAssertTrue(Rig.rendezvous("hold-close"), "driver flip: POST /shifts/close is held for 30 s")
        var swipes = 0
        while !finish.isHittable, swipes < 8 { app0.swipeUp(); swipes += 1 }
        finish.tap()
        app0.buttons["Finish now"].tap()
        XCTAssertTrue(app0.staticTexts["Shift finished"].waitForExistence(timeout: Rig.timeout), "the receipt is up")
        sleep(1)
        backgroundAndKill(app0)

        let app = launch()                       // the walk's language; the receipt is still offered (< 2 min)
        let w = idleWords
        XCTAssertTrue(app.staticTexts[w.heading].waitForExistence(timeout: Rig.timeout))
        dismissReceiptIfShown(app, shifted: w.shiftFinished, cont: w.cont)
        sleep(3)                                 // past the delivery grace
        let waitingText = language == "de" ? "Wartet auf Verbindung" : "Waiting for a connection"
        let waiting = anyElement(app, containing: waitingText)
        var scrolled = 0
        while !(waiting.exists && waiting.isHittable), scrolled < 10 { app.swipeUp(); scrolled += 1 }
        snap("b2-07-waiting-row")
        XCTAssertTrue(waiting.exists, "the unsent row says '\(waitingText)'")
        XCTAssertFalse(anyElement(app, containing: language == "de" ? "Wird gesendet" : "Sending").exists, "never 'Sending…'")
        XCTAssertTrue(anyElement(app, containing: language == "de" ? "Zuletzt versucht" : "Last tried").exists, "and when it last tried")
        XCTAssertTrue(Rig.rendezvous("fault-clear"), "driver flip: faults cleared")
        sleep(2)
        backgroundAndKill(app)
    }

    // MARK: - B3: the running screen

    private struct RunWords {
        let heading, scan, finish, help, helpSentence: String
    }
    private var runWords: RunWords {
        language == "de"
            ? RunWords(heading: "Schicht läuft", scan: "Tag scannen", finish: "Schicht ohne Tag beenden",
                       help: "Hilfe zur Schicht", helpSentence: "Etwas stimmt nicht?")
            : RunWords(heading: "Shift in progress", scan: "Scan a tag", finish: "Finish shift without a tag",
                       help: "Shift help", helpSentence: "Something wrong?")
    }

    /// A running shift on the fixed dark-blue field: the quiet heading, the typographic time with no
    /// card, ONE filled scan button, a quiet finish, the plan, and the help behind its button.
    func testB3RunningField() throws {
        startShiftManuallyInEnglish()
        let app = launch()
        let w = runWords
        XCTAssertTrue(app.staticTexts[w.heading].waitForExistence(timeout: Rig.timeout), "the quiet state heading '\(w.heading)'")
        XCTAssertTrue(app.staticTexts["Rig Haus Alpha"].exists, "the building")
        sleep(3)                                  // past the confirmation ring-then-check, digits settled
        snap("b3-01-running-top")
        let scan = app.buttons[w.scan]
        XCTAssertTrue(scan.exists, "the one filled button '\(w.scan)'")
        XCTAssertGreaterThanOrEqual(scan.frame.height, 56, "the primary button is at least 56 pt tall: \(scan.frame.height)")
        XCTAssertTrue(app.buttons[w.finish].exists, "finishing without a tag is a button, quiet")
        XCTAssertFalse(anyElement(app, containing: w.helpSentence).exists, "the help sentence is not printed on the screen")
        // the help is behind its button
        let help = app.buttons[w.help]
        var swipes = 0
        while !help.isHittable, swipes < 10 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(help.waitForExistence(timeout: Rig.timeout), "the help button '\(w.help)'")
        snap("b3-02-running-bottom-help-closed")
        help.tap()
        XCTAssertTrue(anyElement(app, containing: w.helpSentence).waitForExistence(timeout: Rig.timeout),
                      "tapping it shows the unchanged help sentence")
        sleep(1)
        snap("b3-03-running-help-open")
        backgroundAndKill(app)
        _ = finishShiftManuallyInEnglish()
    }

    /// An UNACKNOWLEDGED start (the server is unreachable): the same field with the pending heading, the
    /// notice line and Refresh, the delivery row on the field and its details sheet - which must read in
    /// the phone's own appearance, not the field's.
    func testB3PendingAndDeliverySheet() throws {
        let app0 = launch()
        XCTAssertTrue(app0.staticTexts[idleWords.heading].waitForExistence(timeout: Rig.timeout), "idle first")
        XCTAssertTrue(Rig.rendezvous("net-down"), "driver flip: front stopped")
        backgroundAndKill(app0)
        startShiftManuallyInEnglish()             // offline: the start is queued on the phone
        let app = launch()
        let w = runWords
        let pending = language == "de" ? "Noch nicht bestätigt" : "Not confirmed yet"
        XCTAssertTrue(app.staticTexts[w.heading].waitForExistence(timeout: Rig.timeout)
                        || app.staticTexts[pending].waitForExistence(timeout: Rig.timeout), "the running screen is up")
        XCTAssertTrue(app.staticTexts[pending].waitForExistence(timeout: 8), "past the 2 s grace: '\(pending)'")
        snap("b3-06-pending-top")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", language == "de" ? "Telefon" : "on this phone")).firstMatch
        var swipes = 0
        while !row.exists, swipes < 8 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(row.waitForExistence(timeout: Rig.timeout), "the 'still on this phone' delivery row")
        XCTAssertGreaterThanOrEqual(row.frame.height, 44, "tappable: at least 44 pt tall")
        snap("b3-07-pending-delivery-row")
        row.tap()
        XCTAssertTrue(app.buttons[language == "de" ? "Schließen" : "Close"].waitForExistence(timeout: Rig.timeout), "the details sheet")
        sleep(1)
        snap("b3-08-delivery-sheet-on-field")
        app.buttons[language == "de" ? "Schließen" : "Close"].tap()
        XCTAssertTrue(Rig.rendezvous("net-up"), "driver flip: front started")
        backgroundAndKill(app)
        _ = finishShiftManuallyInEnglish()
    }

    /// OVERDUE: a shift past 8 h (the driver opens one "from another device" 9 hours ago and the phone
    /// adopts it). Neutral error field with red ink, the words still say it, no ticking number.
    func testB3OverdueNeutralField() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts[idleWords.heading].waitForExistence(timeout: Rig.timeout), "idle first")
        XCTAssertTrue(Rig.rendezvous("open-elsewhere"), "driver: a 9 h old open shift for this worker on the server")
        pullToRefresh(app)
        let over = language == "de" ? "Über 8 Stunden" : "Over 8 hours"
        XCTAssertTrue(app.staticTexts[over].waitForExistence(timeout: Rig.timeout), "the overdue heading '\(over)'")
        // The first clock-in asks for notifications (the permission moment): answer it, so the shots are of the screen.
        sleep(2)
        dismissSystemAlerts()
        sleep(1)
        snap("b3-04-overdue")
        let help = app.buttons[runWords.help]
        var swipes = 0
        while !help.isHittable, swipes < 10 { app.swipeUp(); swipes += 1 }
        snap("b3-05-overdue-bottom")
    }

    // MARK: - B4: Materials

    private struct MaterialsWords {
        let heading, ask, field, example, send, saved, noPush, details, longSentence, dismiss, waiting: String
    }
    private var materialsWords: MaterialsWords {
        language == "de"
            ? MaterialsWords(heading: "Material", ask: "Etwas anfordern", field: "Was brauchen Sie?",
                             example: "Zum Beispiel: 2 Mopps, Glasreiniger", send: "Anfrage senden",
                             saved: "Anfrage gespeichert. Sie wird gesendet, sobald Sie online sind.",
                             noPush: "Status hier prüfen. Keine Push-Mitteilungen.", details: "So erhalten Sie Rückmeldung",
                             longSentence: "Ihr Telefon meldet sich nicht von selbst", dismiss: "Ausblenden",
                             waiting: "Wartet auf die Verwaltung")
            : MaterialsWords(heading: "Materials", ask: "Ask for something", field: "What do you need?",
                             example: "For example: 2 mops, glass cleaner", send: "Send request",
                             saved: "Request saved. It will be sent as soon as you're online.",
                             noPush: "Check updates here. No push notifications.", details: "How updates work",
                             longSentence: "your phone will not notify you", dismiss: "Dismiss",
                             waiting: "Waiting for the office")
    }

    /// The idle phone, Materials tab: a flat composer (heading and mark, the field, the VISIBLE example, ONE
    /// filled button that starts disabled), ONE short no-push line and the long explanation behind its
    /// button - never printed. Then a request is typed and sent: the saved line is visible and the row says
    /// what it is WAITING for in the walk's language (it used to arrive in English on a German phone).
    func testB4MaterialsComposerAndDialog() throws {
        let app = launch()
        let w = materialsWords
        app.tabBars.buttons[words.materials].tap()
        XCTAssertTrue(app.staticTexts[w.heading].waitForExistence(timeout: Rig.timeout), "the page heading '\(w.heading)'")
        XCTAssertTrue(app.staticTexts[w.ask].exists, "the composer heading '\(w.ask)'")
        let field = app.textFields[w.field]
        XCTAssertTrue(field.waitForExistence(timeout: Rig.timeout), "the field '\(w.field)'")
        XCTAssertTrue(app.staticTexts[w.example].exists, "the example is VISIBLE under the field: '\(w.example)'")
        let send = app.buttons[w.send]
        XCTAssertTrue(send.exists && !send.isEnabled, "the one filled button starts disabled (nothing typed)")
        XCTAssertGreaterThanOrEqual(send.frame.height, 56, "Send is the shared primary button, at least 56 pt tall: \(send.frame.height)")
        XCTAssertTrue(app.staticTexts[w.noPush].exists, "the short no-push line is always visible: '\(w.noPush)'")
        XCTAssertFalse(anyElement(app, containing: w.longSentence).exists, "the long explanation is NOT printed on the screen")
        let details = app.buttons[w.details]
        XCTAssertTrue(details.exists, "the explanation button '\(w.details)'")
        XCTAssertGreaterThanOrEqual(details.frame.height, 48, "the quiet button is at least 48 pt tall: \(details.frame.height)")
        snap("b4-01-materials-composer")

        details.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: Rig.timeout), "the dialog opens")
        XCTAssertTrue(anyElement(app, containing: w.longSentence).waitForExistence(timeout: 3), "the dialog holds the long explanation")
        sleep(1)
        snap("b4-02-no-push-dialog")
        alert.buttons[w.dismiss].tap()
        XCTAssertTrue(field.waitForExistence(timeout: Rig.timeout))

        field.tap()
        field.typeText("2 Mopps")
        XCTAssertTrue(app.buttons[w.send].isEnabled, "typing enables Send")
        sleep(1)
        snap("b4-03-typed")
        // Send is scrolled TOWARDS, measured against what the keyboard leaves: at the largest text sizes it is
        // BEHIND the keyboard, which is below the fold as far as a thumb is concerned (up brings a button from
        // below, down brings one back).
        let sendButton = app.buttons[w.send]
        func visibleBottom() -> CGFloat {
            let keyboard = app.keyboards.firstMatch
            return keyboard.exists ? keyboard.frame.minY : app.windows.firstMatch.frame.height
        }
        // A drag down the right-hand margin: a swipe from the middle of the screen can start INSIDE the
        // focused field, which keeps the gesture for itself and never scrolls the list.
        func drag(from: CGFloat, to: CGFloat) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: from))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: to)))
        }
        var swipes = 0
        while !(sendButton.isHittable && sendButton.frame.maxY <= visibleBottom()), swipes < 10 {
            if sendButton.frame.midY > visibleBottom() { drag(from: 0.45, to: 0.12) } else { drag(from: 0.12, to: 0.45) }
            swipes += 1
        }
        if !sendButton.isHittable { snap("b4-03b-send-not-reachable") }
        XCTAssertTrue(sendButton.isHittable, "Send is reachable: exists \(sendButton.exists), frame \(sendButton.frame), window \(app.windows.firstMatch.frame)")
        sendButton.tap()
        XCTAssertTrue(anyElement(app, containing: w.saved).waitForExistence(timeout: Rig.timeout),
                      "the saved line is VISIBLE, not only announced: '\(w.saved)'")
        sleep(2)                                   // the push is acknowledged: the row now carries the server's word
        snap("b4-04-saved-and-listed")
        var below = 0
        while !anyElement(app, containing: w.waiting).exists, below < 6 { app.swipeUp(); below += 1 }
        XCTAssertTrue(anyElement(app, containing: w.waiting).waitForExistence(timeout: Rig.timeout),
                      "the sent row says '\(w.waiting)' in the walk's language")
        snap("b4-05-requests")
    }

    /// A RUNNING shift: the composer carries the building ("For <building>") and the dialog is the other
    /// explanation (the one that says the request is sent with it). Still the same one short line.
    func testB4MaterialsForTheBuilding() throws {
        startShiftManuallyInEnglish()
        let app = launch()
        let w = materialsWords
        app.tabBars.buttons[words.materials].tap()
        XCTAssertTrue(app.staticTexts[w.heading].waitForExistence(timeout: Rig.timeout))
        let forBuilding = language == "de" ? "Für Rig Haus Alpha" : "For Rig Haus Alpha"
        XCTAssertTrue(anyElement(app, containing: forBuilding).waitForExistence(timeout: Rig.timeout),
                      "the building is CONTEXT under the field: '\(forBuilding)'")
        snap("b4-06-materials-with-building")
        app.buttons[w.details].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: Rig.timeout), "the dialog opens")
        let sentWith = language == "de" ? "Wird mit dem Objekt gesendet" : "Sent with the building"
        XCTAssertTrue(anyElement(app, containing: sentWith).waitForExistence(timeout: 3),
                      "the building variant of the explanation: '\(sentWith)'")
        sleep(1)
        snap("b4-07-no-push-dialog-with-building")
        app.alerts.firstMatch.buttons[w.dismiss].tap()
        backgroundAndKill(app)
        _ = finishShiftManuallyInEnglish()
    }

    // MARK: - B5: More, sign out, the version line

    private struct MoreWords {
        let heading, signOut, cancel, consequence, newCode, adminSentence, operatorRow, operatorTitle, installed: String
    }
    private var moreWords: MoreWords {
        language == "de"
            ? MoreWords(heading: "Einstellungen", signOut: "Abmelden", cancel: "Abbrechen",
                        consequence: "bleiben am Server", newCode: "neuen Anmeldecode",
                        adminSentence: "von Ihrer Verwaltung im Web", operatorRow: "Karten schreiben oder prüfen",
                        operatorTitle: "Betreiber", installed: "Installiert:")
            : MoreWords(heading: "Settings", signOut: "Sign out", cancel: "Cancel",
                        consequence: "stay on the server", newCode: "NEW code",
                        adminSentence: "managed by your admin", operatorRow: "Write or test tags",
                        operatorTitle: "Operator", installed: "Installed:")
    }

    /// Brings `element` into view on a ScrollView that is longer than the screen (the largest text sizes).
    private func scrollTo(_ element: XCUIElement, _ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        var swipes = 0
        while !element.isHittable, swipes < 8 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(element.isHittable, "\(element) is on screen", file: file, line: line)
    }

    /// More, idle: the heading, ONE identity card (initials circle + name, My hours, History), no admin
    /// sentence, no operator row anywhere, Sign out as a quiet text button and the version line last. Sign out
    /// ASKS: the dialog states the consequences and Cancel leaves the worker signed in.
    func testB5MoreIdentityCardAndSignOutDialog() throws {
        let app = launch()
        let w = moreWords
        app.tabBars.buttons[words.more].tap()
        XCTAssertTrue(app.staticTexts[w.heading].waitForExistence(timeout: Rig.timeout), "the heading '\(w.heading)'")
        XCTAssertTrue(anyElement(app, containing: "Anna Rig").exists, "the identity card names the worker")
        let myHours = app.buttons[words.myHours], history = app.buttons[words.history]
        XCTAssertTrue(myHours.exists && history.exists, "the card holds '\(words.myHours)' and '\(words.history)'")
        XCTAssertGreaterThanOrEqual(myHours.frame.height, 44, "a card row is a real target: \(myHours.frame.height)")
        XCTAssertLessThan(myHours.frame.minY, history.frame.minY, "My hours above History")
        XCTAssertFalse(anyElement(app, containing: w.adminSentence).exists, "the 'managed by your admin on the web' sentence is gone")
        XCTAssertFalse(app.buttons[w.operatorRow].exists || app.staticTexts[w.operatorRow].exists, "no visible operator row")
        XCTAssertFalse(app.pickers.firstMatch.exists, "no language picker (blocked on the E1-E3 tasks)")
        let signOut = app.buttons[w.signOut]
        XCTAssertTrue(signOut.exists, "Sign out")
        let version = app.buttons["version-line"]
        scrollTo(version, app)
        XCTAssertTrue(version.label.contains(w.installed), "the version line says '\(w.installed)': \(version.label)")
        XCTAssertGreaterThanOrEqual(version.frame.height, 44, "the version line is a real target: \(version.frame.height)")
        XCTAssertGreaterThan(version.frame.minY, signOut.frame.minY, "the version line is last, after Sign out")
        app.swipeDown()
        snap("b5-01-more")

        // Sign out ASKS: one press opens an alert with the consequences; Cancel closes it WITHOUT signing out.
        signOut.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: Rig.timeout), "one press opens an alert")
        XCTAssertTrue(anyElement(app, containing: w.consequence).waitForExistence(timeout: 3), "it states the consequences")
        XCTAssertTrue(anyElement(app, containing: w.newCode).exists, "...including that signing back in needs a new code")
        XCTAssertTrue(alert.buttons[w.signOut].exists && alert.buttons[w.cancel].exists, "Sign out and Cancel, both visible")
        sleep(1)
        snap("b5-02-signout-dialog")
        alert.buttons[w.cancel].tap()
        XCTAssertTrue(app.tabBars.buttons[words.shift].waitForExistence(timeout: Rig.timeout), "Cancel leaves the worker signed in")
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 2), "...and the alert is gone")
        XCTAssertTrue(app.staticTexts[w.heading].exists, "...on More")
    }

    /// The version line is the operator door: five taps - not four, and no time window - push the operator
    /// gate, which REPLACES the worker's scaffold (no tab bar); Back returns to More, signed in, and the
    /// counter starts again.
    func testB5VersionLineFiveTapsOpenTheOperatorGate() throws {
        let app = launch()
        let w = moreWords
        app.tabBars.buttons[words.more].tap()
        XCTAssertTrue(app.staticTexts[w.heading].waitForExistence(timeout: Rig.timeout))
        let version = app.buttons["version-line"]
        scrollTo(version, app)
        func operatorIsUp() -> Bool { app.navigationBars[w.operatorTitle].waitForExistence(timeout: 3) }

        version.tap(); version.tap()
        sleep(12)                              // no time window: two taps, a pause, two more
        version.tap(); version.tap()
        XCTAssertFalse(operatorIsUp(), "four taps open nothing, whatever the pause between them")
        XCTAssertTrue(app.tabBars.buttons[words.shift].isHittable, "the worker's tab bar is still there after four taps")
        snap("b5-03-four-taps")
        version.tap()
        XCTAssertTrue(operatorIsUp(), "the fifth tap opens the operator gate")
        XCTAssertFalse(app.tabBars.buttons[words.shift].isHittable, "the operator screen replaces the worker scaffold: no tab bar")
        sleep(1)
        snap("b5-04-operator-gate-no-tab-bar")

        app.navigationBars.buttons.element(boundBy: 0).tap()                // Back
        XCTAssertTrue(app.tabBars.buttons[words.more].waitForExistence(timeout: Rig.timeout), "Back restores the tab bar")
        XCTAssertTrue(app.staticTexts[w.heading].exists, "...and More: the worker never signed out")
        scrollTo(version, app)
        for _ in 0..<4 { version.tap() }
        XCTAssertFalse(operatorIsUp(), "the counter was reset by the fifth tap: four more taps open nothing")
        version.tap()
        XCTAssertTrue(operatorIsUp(), "...and the fifth of the new sequence opens it again")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.tabBars.buttons[words.more].waitForExistence(timeout: Rig.timeout))
    }

    /// The seeded operator signs in through the gate's shared code form (English labels: run this in an English
    /// combination) and walks into "Write a tag" and "Test a tag": the worker's tab bar stays hidden ALL THE WAY
    /// DOWN, not only on the gate's own screen (Android: the scaffold is replaced, the bar is not composed).
    func testB5OperatorToolsKeepTheTabBarHidden() throws {
        let app = launch()
        let w = moreWords
        app.tabBars.buttons[words.more].tap()
        XCTAssertTrue(app.staticTexts[w.heading].waitForExistence(timeout: Rig.timeout))
        openOperatorGate(app)
        XCTAssertTrue(app.navigationBars[w.operatorTitle].waitForExistence(timeout: Rig.timeout), "the gate")
        let code = app.textFields["Access code"]
        if code.waitForExistence(timeout: 4) {
            XCTAssertTrue(Rig.rendezvous("new-code-O"), "driver flip: a fresh enrolment code for the seeded operator")
            code.tap()
            code.typeText(Rig.code("O"))
            let submit = app.buttons["Sign in with code"]
            XCTAssertTrue(submit.waitForExistence(timeout: 5) && submit.isEnabled)
            submit.tap()
        }
        let write = app.buttons["Write a tag"], test = app.buttons["Test a tag"]
        XCTAssertTrue(write.waitForExistence(timeout: Rig.timeout) && test.exists, "the operator's two actions")
        XCTAssertFalse(app.tabBars.buttons[words.shift].isHittable, "no worker tab bar on the operator home")
        snap("b5-07-operator-actions")
        write.tap()
        XCTAssertTrue(app.navigationBars["Write a tag"].waitForExistence(timeout: Rig.timeout))
        XCTAssertFalse(app.tabBars.buttons[words.shift].isHittable, "no worker tab bar on Write a tag either")
        sleep(1)
        snap("b5-08-write-a-tag-no-tab-bar")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(test.waitForExistence(timeout: Rig.timeout))
        test.tap()
        XCTAssertTrue(app.navigationBars["Test a tag"].waitForExistence(timeout: Rig.timeout))
        XCTAssertFalse(app.tabBars.buttons[words.shift].isHittable, "...nor on Test a tag")
        sleep(1)
        snap("b5-09-test-a-tag-no-tab-bar")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.tabBars.buttons[words.more].waitForExistence(timeout: Rig.timeout), "Back, Back: More with its tab bar")
        XCTAssertTrue(app.staticTexts[w.heading].exists, "...and the worker still signed in")
    }

    /// THE SIGNED-OUT SCREEN: no operator row and no operator sentence, the version line last, five taps open
    /// the same gate (with its own counter). The phone is signed in again in English at the end (a fresh code
    /// from the driver), so the walk's later steps still have a worker.
    func testB5SignedOutVersionLineAndGate() throws {
        let app = launch()
        let w = moreWords
        app.tabBars.buttons[words.more].tap()
        XCTAssertTrue(app.staticTexts[w.heading].waitForExistence(timeout: Rig.timeout))
        signOutFromMore(app)
        XCTAssertTrue(app.staticTexts["NFC TimeSheets"].waitForExistence(timeout: Rig.timeout), "the sign-in screen")
        let version = app.buttons["version-line"]
        // The sign-in Form is lazy: at the largest text sizes its last row exists only once it is scrolled to.
        var found = 0
        while !version.exists, found < 10 { app.swipeUp(); found += 1 }
        XCTAssertTrue(version.waitForExistence(timeout: 3), "the sign-in screen has the version line")
        XCTAssertFalse(app.buttons[w.operatorRow].exists, "no visible operator row on the sign-in screen")
        XCTAssertFalse(anyElement(app, containing: language == "de" ? "Betreiber? Tags" : "Operator? Write or test tags").exists,
                       "...and no operator sentence")
        scrollTo(version, app)
        XCTAssertTrue(version.label.contains(w.installed), "the version line says '\(w.installed)': \(version.label)")
        snap("b5-05-signed-out-version-line")
        for _ in 0..<4 { version.tap() }
        XCTAssertFalse(app.navigationBars[w.operatorTitle].waitForExistence(timeout: 3), "four taps open nothing")
        version.tap()
        XCTAssertTrue(app.navigationBars[w.operatorTitle].waitForExistence(timeout: Rig.timeout), "the fifth tap opens the operator gate")
        sleep(1)
        snap("b5-06-signed-out-operator-gate")

        // Put the worker back (English: the sign-in form's labels are asserted by label).
        backgroundAndKill(app)
        XCTAssertTrue(Rig.rendezvous("new-code-A"), "driver flip: a fresh code for worker A")
        let again = Rig.launch()
        XCTAssertTrue(ensureSignedIn(again, as: "A"), "worker A is signed in again")
        sleep(2)
        dismissSystemAlerts()
        backgroundAndKill(again)
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
