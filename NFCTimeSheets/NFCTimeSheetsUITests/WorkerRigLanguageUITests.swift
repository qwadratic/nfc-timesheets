//
//  WorkerRigLanguageUITests.swift
//  NFCTimeSheetsUITests
//
//  THE IN-APP LANGUAGE, DRIVEN (decision-74, TASK-365.14 / .15 / .16). Nothing here reads source and
//  asserts it "should work": each walk taps the real control on the real screens of a real build and
//  looks at what is drawn. The phone's own language is the walk's `TS_RIG_LANG` (a launch argument), so
//  the same source walks "English phone, choose German" and "German phone, choose English" - the second
//  being the one a lookup that quietly falls back to the PROCESS's language would fail.
//
//  Run through the reskin driver, which flips the server where a walk names a rendezvous:
//
//      CLASS=WorkerRigLanguageUITests STEPS="testL1SignedOutSwitchesLiveAndKeepsTheChoice" \
//          ops/ios-rig/reskin-walk.sh light-en-m light-de-m
//
//  The walks leave the phone's choice at "follow the phone" and a worker signed in, so they can be run in
//  any order and repeated. Screenshots: $TS_RIG_SHOTS/<tag>-l<n>-....png (never in the repo).
//

import XCTest

final class WorkerRigLanguageUITests: XCTestCase {
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

    /// The PHONE's language: what `-AppleLanguages` says, i.e. what "follow the phone" resolves to.
    private var phone: String { Rig.value("TS_RIG_LANG") ?? "en" }
    private var other: String { phone == "en" ? "de" : "en" }
    private var tag: String { Rig.value("TS_RIG_TAG") ?? "walk" }
    private func snap(_ step: String) { shot("\(tag)-\(step)") }

    /// The words the walks look for, per language (Localizable.xcstrings, which are Android's verbatim).
    private struct Words {
        let shift, materials, more, settings, signInSubtitle, accessCode, signInButton: String
        let working, running, timeWorked, finish, finishNow: String
        let ask, field, example, send, myHours, signOut, operatorSentence: String
        let languageTitle, system: String
    }
    private static let de = Words(
        shift: "Schicht", materials: "Material", more: "Mehr", settings: "Einstellungen",
        signInSubtitle: "Melden Sie sich an, um Ihre Stunden zu erfassen.", accessCode: "Anmeldecode", signInButton: "Anmelden",
        working: "Ihr Arbeitstag", running: "Schicht läuft", timeWorked: "SEIT BEGINN",
        finish: "Schicht ohne Tag beenden", finishNow: "Jetzt beenden",
        ask: "Etwas anfordern", field: "Was brauchen Sie?", example: "Zum Beispiel: 2 Mopps, Glasreiniger", send: "Anfrage senden",
        myHours: "Meine Stunden", signOut: "Abmelden",
        operatorSentence: "Als Betreiber anmelden, um Karten zu schreiben und zu prüfen.",
        languageTitle: "Sprache", system: "Wie am Telefon")
    private static let en = Words(
        shift: "Shift", materials: "Materials", more: "More", settings: "Settings",
        signInSubtitle: "Sign in to log your hours.", accessCode: "Access code", signInButton: "Sign in with code",
        working: "Your working day", running: "Shift in progress", timeWorked: "TIME WORKED",
        finish: "Finish shift without a tag", finishNow: "Finish now",
        ask: "Ask for something", field: "What do you need?", example: "For example: 2 mops, glass cleaner", send: "Send request",
        myHours: "My hours", signOut: "Sign out",
        operatorSentence: "Sign in as an operator to write and test tags. This never opens a shift.",
        languageTitle: "Language", system: "Use phone language")
    private func words(_ language: String) -> Words { language == "de" ? Self.de : Self.en }

    // MARK: - helpers

    /// A signed-in phone, launched with the phone's language as an argument (the shipping app, no hook).
    private func launch(tap: String? = nil, language: String? = nil) -> XCUIApplication {
        let lang = language ?? phone
        let app = Rig.launch(tap: tap, language: lang, locale: lang == "de" ? "de_AT" : "en_GB")
        return app
    }

    private func pickerButton(_ app: XCUIApplication, _ value: String) -> XCUIElement {
        app.buttons[value.isEmpty ? "language-system" : "language-\(value)"]
    }

    private func waitForPicker(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(pickerButton(app, "de").waitForExistence(timeout: Rig.timeout)
                      && pickerButton(app, "en").exists && pickerButton(app, "").exists,
                      "the language control has its three options", file: file, line: line)
    }

    /// Exactly `value` is the selected option of the language control.
    private func assertSelected(_ app: XCUIApplication, _ value: String, _ note: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        for option in ["de", "en", ""] {
            XCTAssertEqual(pickerButton(app, option).isSelected, option == value,
                           "\(note): '\(option.isEmpty ? "system" : option)' is\(option == value ? "" : " not") the selected option",
                           file: file, line: line)
        }
    }

    private func openMore(_ app: XCUIApplication, in language: String) {
        let w = words(language)
        let tab = app.tabBars.buttons[w.more]
        XCTAssertTrue(tab.waitForExistence(timeout: Rig.timeout), "the '\(w.more)' tab is there (\(language))")
        tab.tap()
        XCTAssertTrue(app.staticTexts[w.settings].waitForExistence(timeout: Rig.timeout), "More's heading '\(w.settings)' (\(language))")
    }

    /// Puts the choice back to "follow the phone" from wherever the control is on screen.
    private func restoreFollowThePhone(_ app: XCUIApplication) {
        let system = pickerButton(app, "")
        if !system.exists { return }
        system.tap()
    }

    // MARK: - sign in (English, once per rig session)

    func testSignInOnce() throws {
        let app = Rig.launch()
        XCTAssertTrue(ensureSignedIn(app, as: "A") || app.tabBars.buttons["Shift"].exists, "worker A is signed in")
        sleep(2)
        dismissSystemAlerts()
        backgroundAndKill(app)
    }

    // MARK: - L1: the signed-out screen, relaunch, sign in

    /// Switch on the signed-out screen (live), keep it across a relaunch and across signing in, and leave
    /// the OS value removed. The tapped option is the phone's OTHER language, so on the German phone this
    /// is the "choose English" direction.
    func testL1SignedOutSwitchesLiveAndKeepsTheChoice() throws {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons[words(phone).shift].waitForExistence(timeout: Rig.timeout),
                      "a signed-in phone (run testSignInOnce first)")
        openMore(app, in: phone)
        signOutFromMore(app)
        XCTAssertTrue(app.staticTexts["NFC TimeSheets"].waitForExistence(timeout: Rig.timeout), "the signed-out screen")
        waitForPicker(app)
        let home = words(phone), away = words(other)
        XCTAssertTrue(app.staticTexts[home.languageTitle].exists, "the title is '\(home.languageTitle)' in the phone's language")
        XCTAssertTrue(app.buttons[home.system].exists, "the third option reads '\(home.system)'")
        XCTAssertTrue(app.staticTexts[home.signInSubtitle].exists, "the screen is in the phone's language")
        assertSelected(app, "", "before any choice")
        snap("l1-01-signed-out-phone-language")

        // LIVE: no relaunch, no navigation - the same screen, the other language.
        pickerButton(app, other).tap()
        XCTAssertTrue(app.staticTexts[away.signInSubtitle].waitForExistence(timeout: 5),
                      "choosing '\(other)' re-words the same screen at once: '\(away.signInSubtitle)'")
        XCTAssertFalse(app.staticTexts[home.signInSubtitle].exists, "...and the phone's language is gone from it")
        XCTAssertTrue(app.staticTexts[away.languageTitle].exists && app.buttons[away.system].exists, "the control itself is re-worded")
        XCTAssertTrue(app.buttons["Deutsch"].exists && app.buttons["English"].exists,
                      "the two language names are the same in both languages (a worker locked in the wrong one can read them)")
        assertSelected(app, other, "after choosing")
        snap("l1-02-signed-out-chosen-\(other)")

        // "Follow the phone" REMOVES the choice and the phone's language is back.
        pickerButton(app, "").tap()
        XCTAssertTrue(app.staticTexts[home.signInSubtitle].waitForExistence(timeout: 5), "follow-the-phone gives the phone's language back")
        assertSelected(app, "", "after follow-the-phone")

        // Choose again and RELAUNCH: the value is the OS's per-app one, so it is still there.
        pickerButton(app, other).tap()
        XCTAssertTrue(app.staticTexts[away.signInSubtitle].waitForExistence(timeout: 5))
        app.terminate()
        let again = launch()
        XCTAssertTrue(again.staticTexts[away.signInSubtitle].waitForExistence(timeout: Rig.timeout),
                      "after a relaunch (the phone's argument still says '\(phone)') the choice '\(other)' is kept")
        waitForPicker(again)
        assertSelected(again, other, "after the relaunch")
        snap("l1-03-relaunched")

        // SIGN IN WHILE IT IS CHOSEN: the choice is device-local and survives signing in. The form's own
        // labels are in the chosen language, so the walk uses those.
        backgroundAndKill(again)
        XCTAssertTrue(Rig.rendezvous("new-code-A"), "driver flip: a fresh code for worker A")
        let signIn = launch()
        let field = signIn.textFields[away.accessCode]
        XCTAssertTrue(field.waitForExistence(timeout: Rig.timeout), "the code field is labelled '\(away.accessCode)'")
        field.tap()
        field.typeText(Rig.code("A"))
        let submit = signIn.buttons[away.signInButton]
        XCTAssertTrue(submit.waitForExistence(timeout: 5) && submit.isEnabled)
        submit.tap()
        XCTAssertTrue(signIn.tabBars.buttons[away.shift].waitForExistence(timeout: Rig.timeout),
                      "signed in, and the tab bar is in the chosen language: '\(away.shift)'")
        dismissSystemAlerts()
        openMore(signIn, in: other)
        assertSelected(signIn, other, "More after signing in")
        snap("l1-04-more-after-sign-in")

        // Leave the phone as found.
        restoreFollowThePhone(signIn)
        XCTAssertTrue(signIn.staticTexts[home.settings].waitForExistence(timeout: 5), "More is back in the phone's language")
        assertSelected(signIn, "", "restored")
        sleep(2)
        backgroundAndKill(signIn)
    }

    // MARK: - L2: with a shift running

    /// A running shift, the switch made from More: the shift is neither closed nor re-opened, the
    /// session is kept, and the running screen is in the new language when the worker comes back.
    func testL2SwitchWithAShiftRunningTouchesNothing() throws {
        let zone = Rig.zone("A_VER")
        XCTAssertFalse(zone.isEmpty, "the rig exports the seed's zone uuids")
        let app = launch(tap: zone)
        let home = words(phone), away = words(other)
        XCTAssertTrue(anyElement(app, containing: home.running).waitForExistence(timeout: Rig.timeout),
                      "the running screen is up in the phone's language ('\(home.running)')")
        sleep(3)                                           // the open is acknowledged
        snap("l2-01-running")
        openMore(app, in: phone)
        pickerButton(app, other).tap()
        XCTAssertTrue(app.staticTexts[away.settings].waitForExistence(timeout: 5), "More is re-worded at once")
        XCTAssertTrue(app.tabBars.buttons[away.shift].exists && app.tabBars.buttons[away.more].exists,
                      "...and so is the tab bar: '\(away.shift)' / '\(away.more)'")
        snap("l2-02-more-switched")
        XCTAssertTrue(Rig.rendezvous("check-open-shift"), "driver check: the switch left exactly one open shift on the server")
        app.tabBars.buttons[away.shift].tap()
        XCTAssertTrue(anyElement(app, containing: away.running).waitForExistence(timeout: 5),
                      "the SAME running screen, in the chosen language: '\(away.running)'")
        XCTAssertTrue(app.staticTexts[away.timeWorked].exists, "the clock's label follows: '\(away.timeWorked)'")
        XCTAssertFalse(app.staticTexts["Anna Rig"].exists || app.staticTexts[home.signInSubtitle].exists,
                       "the worker is still signed in (no sign-in screen)")
        snap("l2-03-running-switched")

        // Finish it (in the chosen language) so the next walk starts idle, and put the choice back.
        let finish = app.buttons[away.finish]
        var swipes = 0
        while !finish.isHittable, swipes < 8 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(finish.waitForExistence(timeout: Rig.timeout), "the quiet finish, in the chosen language")
        finish.tap()
        let now = app.buttons[away.finishNow]
        XCTAssertTrue(now.waitForExistence(timeout: Rig.timeout), "the confirmation dialog, in the chosen language")
        now.tap()
        XCTAssertTrue(app.staticTexts[away.working].waitForExistence(timeout: Rig.timeout), "back on the idle screen")
        openMore(app, in: other)
        restoreFollowThePhone(app)
        XCTAssertTrue(app.staticTexts[home.settings].waitForExistence(timeout: 5))
        sleep(3)
        backgroundAndKill(app)
    }

    // MARK: - L3: with a material draft open

    /// A half-typed request is a draft in a field. Switching language from More must neither send it nor
    /// clear it nor reset the Materials tab.
    func testL3SwitchWithAMaterialDraftOpenKeepsTheDraft() throws {
        let app = launch()
        let home = words(phone), away = words(other)
        XCTAssertTrue(app.tabBars.buttons[home.materials].waitForExistence(timeout: Rig.timeout), "a signed-in phone")
        app.tabBars.buttons[home.materials].tap()
        let field = app.textFields[home.field]
        XCTAssertTrue(field.waitForExistence(timeout: Rig.timeout), "the composer's field '\(home.field)'")
        field.tap()
        field.typeText("2 Mopps")
        XCTAssertEqual(field.value as? String, "2 Mopps", "the draft is typed")
        snap("l3-01-draft")
        // More, WITHOUT sending. The keyboard covers the tab bar, so it is dismissed the way a person does:
        // the list scrolls it away (Materials: scrollDismissesKeyboard(.interactively)).
        var drags = 0
        while app.keyboards.firstMatch.exists, drags < 4 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.25))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.7)))
            drags += 1
        }
        XCTAssertFalse(app.keyboards.firstMatch.exists, "the keyboard is away")
        app.tabBars.buttons[home.more].tap()
        XCTAssertTrue(app.staticTexts[home.settings].waitForExistence(timeout: Rig.timeout))
        pickerButton(app, other).tap()
        XCTAssertTrue(app.staticTexts[away.settings].waitForExistence(timeout: 5), "More is re-worded")
        XCTAssertTrue(Rig.rendezvous("check-no-material-request"), "driver check: switching posted no request")
        app.tabBars.buttons[away.materials].tap()
        let after = app.textFields[away.field]
        XCTAssertTrue(after.waitForExistence(timeout: Rig.timeout), "the composer's field, re-worded: '\(away.field)'")
        XCTAssertEqual(after.value as? String, "2 Mopps", "the half-typed draft is still in the field after the switch")
        XCTAssertTrue(app.staticTexts[away.example].exists, "the example caption follows: '\(away.example)'")
        XCTAssertTrue(app.buttons[away.send].isEnabled, "and Send is still enabled for it (the draft is not empty)")
        snap("l3-02-draft-switched")

        // Clean up: the draft is @State and dies with the process (backgroundAndKill below); the choice goes back.
        XCTAssertFalse(app.keyboards.firstMatch.exists, "coming back to the tab did not raise the keyboard")
        app.tabBars.buttons[away.more].tap()
        restoreFollowThePhone(app)
        XCTAssertTrue(app.staticTexts[home.settings].waitForExistence(timeout: 5))
        sleep(2)
        backgroundAndKill(app)
    }

    // MARK: - L5: iOS Settings is the same value

    private let settingsApp = XCUIApplication(bundleIdentifier: "com.apple.Preferences")

    /// Settings > Apps > NFCTimeSheets, from a cold Settings (a fresh launch, so no earlier page is left open).
    @discardableResult
    private func openAppPageInSettings() -> XCUIElement {
        let settings = settingsApp
        if settings.state != .notRunning { settings.terminate() }
        settings.launch()
        var apps = settings.buttons["Apps"]
        var swipes = 0
        while !apps.isHittable, swipes < 20 { settings.swipeUp(); swipes += 1; apps = settings.buttons["Apps"] }
        XCTAssertTrue(apps.isHittable, "Settings has an Apps row")
        apps.tap()
        let row = settings.buttons["NFCTimeSheets"]
        var more = 0
        while !row.isHittable, more < 15 { settings.swipeUp(); more += 1 }
        XCTAssertTrue(row.waitForExistence(timeout: 5) && row.isHittable, "Settings > Apps lists NFCTimeSheets")
        row.tap()
        let language = settings.buttons["PREFERRED_LANGUAGE"]
        XCTAssertTrue(language.waitForExistence(timeout: Rig.timeout),
                      "the app's own page has a Language row (it declares de and en: the OS per-app setting lists them)")
        return language
    }

    /// The shipping app, launched the way the home screen launches it: NO launch arguments, so the OS's own
    /// state (the per-app value Settings wrote) is all there is.
    private func launchLikeTheHomeScreen() -> XCUIApplication {
        let app = XCUIApplication()
        if app.state != .notRunning { app.terminate() }
        app.launchArguments = []
        app.launch()
        return app
    }

    /// A choice made IN THE APP is what Settings shows ("one value"), and a choice made in Settings is what the app
    /// shows and selects after it is opened again - including "Default", which REMOVES the override.
    func testL5IOSSettingsIsTheSameValue() throws {
        // 1. In the app: start from "follow the phone" whatever an earlier run left, then choose German.
        let app = launch()
        let start = ["de", "en"].first { app.tabBars.buttons[words($0).shift].waitForExistence(timeout: 3) }
        XCTAssertNotNil(start, "a signed-in phone")
        openMore(app, in: start ?? phone)
        pickerButton(app, "").tap()
        XCTAssertTrue(app.staticTexts[words(phone).settings].waitForExistence(timeout: 5), "follow the phone: the phone's language")
        pickerButton(app, "de").tap()
        XCTAssertTrue(app.staticTexts[Self.de.settings].waitForExistence(timeout: 5))
        sleep(1)
        XCUIDevice.shared.press(.home)
        var language = openAppPageInSettings()
        XCTAssertTrue(language.label.contains("German"), "Settings shows what the app chose: '\(language.label)'")
        shot("\(tag)-l5-01-settings-after-in-app-choice")
        language.tap()
        let deutsch = settingsApp.cells["Deutsch"]
        XCTAssertTrue(deutsch.waitForExistence(timeout: 5), "the Language page lists Deutsch")
        XCTAssertTrue(deutsch.isSelected, "...and its checkmark is on Deutsch: the app's choice IS the OS's per-app value")
        shot("\(tag)-l5-02-settings-language-page")

        // 2. In Settings: pick English (the phone's "Default"), then open the app again.
        let english = settingsApp.cells["English"]
        XCTAssertTrue(english.waitForExistence(timeout: 5), "the Language page lists English")
        english.tap()
        sleep(2)
        shot("\(tag)-l5-03-settings-picked-english")
        let reopened = launchLikeTheHomeScreen()
        XCTAssertTrue(reopened.tabBars.buttons[Self.en.shift].waitForExistence(timeout: Rig.timeout),
                      "after Settings chose English the app is in English when it is opened again")
        openMore(reopened, in: "en")
        // The OS's "Default" row removes the override, so the app shows it as FOLLOW THE PHONE; an explicit English
        // would show 'English'. Either way the app and Settings agree - assert that, then record which.
        let selected = ["de", "en", ""].filter { pickerButton(reopened, $0).isSelected }
        XCTAssertEqual(selected.count, 1, "exactly one option is selected: \(selected)")
        XCTAssertNotEqual(selected.first, "de", "German is not the selected option any more")
        shot("\(tag)-l5-04-app-after-settings-english-selected-\(selected.first.map { $0.isEmpty ? "system" : $0 } ?? "none")")

        // 3. In Settings: pick Deutsch. The app opens in German with German selected.
        XCUIDevice.shared.press(.home)
        language = openAppPageInSettings()
        language.tap()
        let deutsch2 = settingsApp.cells["Deutsch"]
        XCTAssertTrue(deutsch2.waitForExistence(timeout: 5))
        deutsch2.tap()
        sleep(2)
        let german = launchLikeTheHomeScreen()
        XCTAssertTrue(german.tabBars.buttons[Self.de.shift].waitForExistence(timeout: Rig.timeout),
                      "after Settings chose Deutsch the app is in German when it is opened again")
        openMore(german, in: "de")
        assertSelected(german, "de", "a language set in iOS Settings shows as the selected option in the app")
        shot("\(tag)-l5-05-app-after-settings-deutsch")

        // 4. Put it back: follow the phone, from the app.
        pickerButton(german, "").tap()
        XCTAssertTrue(german.staticTexts[Self.en.settings].waitForExistence(timeout: 5), "back to the phone's language")
        sleep(2)
        backgroundAndKill(german)
    }

    // MARK: - L4: the operator screens follow

    /// "Live on every screen including operator screens": the version line's five taps push the operator
    /// gate, which is drawn in the chosen language (and never signs the worker out).
    func testL4OperatorScreensFollowTheChoice() throws {
        let app = launch()
        let home = words(phone), away = words(other)
        openMore(app, in: phone)
        pickerButton(app, other).tap()
        XCTAssertTrue(app.staticTexts[away.settings].waitForExistence(timeout: 5))
        openOperatorGate(app)
        XCTAssertTrue(anyElement(app, containing: away.operatorSentence).waitForExistence(timeout: Rig.timeout),
                      "the operator sign-in is in the chosen language: '\(away.operatorSentence)'")
        XCTAssertFalse(anyElement(app, containing: home.operatorSentence).exists, "...and not in the phone's")
        snap("l4-01-operator-gate-switched")
        // Back, and put the choice back.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts[away.settings].waitForExistence(timeout: Rig.timeout), "back on More")
        restoreFollowThePhone(app)
        XCTAssertTrue(app.staticTexts[home.settings].waitForExistence(timeout: 5))
        sleep(2)
        backgroundAndKill(app)
    }
}
