//
//  FinishReportedCardUITests.swift
//  NFCTimeSheetsUITests
//
//  A CARD THAT WAS WRITTEN AND REPORTED BUT NEVER MADE A ZONE, DRIVEN THROUGH THE REAL VIEWS
//  (decision-76). On the staging server, 2026-10-07, a card sat as a reported tag with no
//  zone and every tap of it answered 422 tag_unbound: the only place that ever called
//  resolve-zone was the Write screen's in-memory zone step, gone once the operator left it.
//
//  WHAT THIS WALKS, and what it asserts at each stop:
//
//   1. Test a tag -> scan a card that classifies as `tag_reported` -> the finish form appears
//      -> name + building -> Create zone -> the SAME scan verified it: "Verified. This door
//      is now a clock-in target." (resolve-zone, then verify, in one visit).
//   2. The same with the building skipped -> a zone exists, it is NOT verified, and the
//      building picker is offered.
//   3. Write a tag -> create a zone with a building -> the screen says one test is still
//      needed and offers "Activate this card", which opens Test a tag with THAT zone already
//      selected (no NFC sheet is opened for the operator).
//   4. Write a tag -> create a zone without a building -> no test hint, "Assign a building"
//      opens the same screen on the building picker.
//
//  THE ONLY FIXTURES ARE THE RADIO AND THE NETWORK. A simulator has no NFC and this stub has
//  no database, so each walk starts from a DEBUG "Mock:" button that arms OperatorMocks; every
//  control tapped after that (Create zone, Activate this card, ...) is a control a Release
//  build also draws. Same split as WriteTagRestartUITests, and for the same reason.
//
//  RUNNING IT (hand-run, NOT part of checks/run.sh, same as the other UI tests). Loopback
//  only; nothing here reaches staging:
//
//      node NFCTimeSheets/checks/write-tag-uitest-stub.mjs --port 8082
//      node demo/tls-front.mjs --cert <dir with ca.pem server.pem server.key> --port 8444 \
//           --upstream 127.0.0.1:8082
//      xcrun simctl keychain booted add-root-cert <dir>/ca.pem
//
//      xcodebuild test -project NFCTimeSheets/NFCTimeSheets.xcodeproj -scheme NFCTimeSheets \
//        -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
//        TS_API_HOST=127.0.0.1:8444 TS_TAG_HOST=127.0.0.1:8444 CODE_SIGNING_ALLOWED=NO \
//        -only-testing:NFCTimeSheetsUITests/FinishReportedCardUITests
//

import XCTest

final class FinishReportedCardUITests: XCTestCase {
    private let timeout: TimeInterval = 20

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - 1 and 2: Test a tag finishes a reported card

    func testReportedCardWithABuildingIsCreatedAndVerifiedByTheSameScan() throws {
        let app = XCUIApplication()
        app.launch()
        openOperatorScreen(app, "Test a tag")

        tapMock(app, "Mock: scan a card - reported, not a zone yet")

        let create = app.buttons["Create zone"]
        scrollToTop(app, until: create)
        XCTAssertTrue(create.waitForExistence(timeout: timeout),
                      "THE FIX: a card that classifies as tag_reported offers the zone step "
                      + "(before decision-76 it printed a sentence and offered nothing)")
        XCTAssertFalse(create.isEnabled, "no zone name yet, so Create zone is disabled")

        typeZoneName(app, "Stiege 2")
        pickBuilding(app, "Musterhaus Wien 3")
        XCTAssertTrue(create.isEnabled, "a name is enough to create it")
        create.tap()

        XCTAssertTrue(app.staticTexts["Verified. This door is now a clock-in target."]
                        .waitForExistence(timeout: timeout),
                      "with a building, the scan that found the card is its test scan: ONE visit "
                      + "leaves a zone workers can clock in on (decision-76 §2)")
        XCTAssertTrue(app.staticTexts["Zone created: Stiege 2."].exists,
                      "and the screen says a zone was created")
        XCTAssertTrue(app.buttons["Scan the card"].exists,
                      "the ordinary zone page is what follows: the card can still be re-scanned")
    }

    func testSkippingTheBuildingCreatesTheZoneButDoesNotVerifyIt() throws {
        let app = XCUIApplication()
        app.launch()
        openOperatorScreen(app, "Test a tag")

        tapMock(app, "Mock: scan a card - reported, not a zone yet")
        scrollToTop(app, until: app.buttons["Create zone"])
        XCTAssertTrue(app.buttons["Create zone"].waitForExistence(timeout: timeout))
        typeZoneName(app, "Stiege 2")
        // The picker rests on "Skip for now": no building chosen.
        app.buttons["Create zone"].tap()

        XCTAssertTrue(app.staticTexts["Zone created: Stiege 2. No building yet - bind it in Test a tag."]
                        .waitForExistence(timeout: timeout),
                      "the zone exists and says it still has no building")
        XCTAssertFalse(app.staticTexts["Verified. This door is now a clock-in target."].exists,
                       "a zone without a building is NEVER verified here: nothing resolves it yet")
        XCTAssertTrue(app.buttons["Put this zone in that building"].waitForExistence(timeout: timeout),
                      "the existing unbound-zone page offers the building picker")
    }

    // MARK: - 3 and 4: Write a tag points at the test that is still owed

    func testWriteScreenOffersTheTestForTheZoneItJustCreated() throws {
        let app = XCUIApplication()
        app.launch()
        openOperatorScreen(app, "Write a tag")

        tapMock(app, "Mock: write, then pick a building")
        let create = app.buttons["Create zone"]
        XCTAssertTrue(create.waitForExistence(timeout: timeout))
        create.tap()

        let hint = app.staticTexts.containing(
            NSPredicate(format: "label BEGINSWITH %@", "The card is written. One test is still needed")).firstMatch
        XCTAssertTrue(hint.waitForExistence(timeout: timeout),
                      "a zone created WITH a building still needs its test scan (decision-47); "
                      + "the screen must say so, or the first worker's tap is refused and the "
                      + "zone looks broken")
        let activate = app.buttons["Activate this card"]
        XCTAssertTrue(activate.exists, "and offers the way straight into that test")
        activate.tap()

        XCTAssertTrue(app.navigationBars["Test a tag"].waitForExistence(timeout: timeout),
                      "Test a tag is pushed")
        XCTAssertTrue(app.buttons["Scan the card"].waitForExistence(timeout: timeout),
                      "with the new zone already selected: it is bound, so it is ready to scan")
    }

    func testUnboundZoneOffersTheBuildingPickerInsteadOfATest() throws {
        let app = XCUIApplication()
        app.launch()
        openOperatorScreen(app, "Write a tag")

        tapMock(app, "Mock: write, then skip the building")
        XCTAssertTrue(app.buttons["Create zone"].waitForExistence(timeout: timeout))
        app.buttons["Create zone"].tap()

        let assign = app.buttons["Assign a building"]
        XCTAssertTrue(assign.waitForExistence(timeout: timeout),
                      "an unbound zone has nothing to test yet, so the button leads to the building")
        XCTAssertFalse(app.staticTexts.containing(
            NSPredicate(format: "label BEGINSWITH %@", "The card is written. One test is still needed")).firstMatch.exists,
                       "and the 'one test is still needed' hint is not shown for it")
        assign.tap()
        XCTAssertTrue(app.buttons["Put this zone in that building"].waitForExistence(timeout: timeout),
                      "Test a tag opens on the unbound zone's building picker")
    }

    // MARK: - helpers

    /// Through the gate (decision-54 §4), against the stub: any 5-digit code is accepted and
    /// the credential is not what this file tests. Tolerant of an operator session left over
    /// from the previous test in the same simulator (cookies persist across launches).
    private func openOperatorScreen(_ app: XCUIApplication, _ destination: String) {
        // The door is the version line (TASK-365.13): five taps, no visible operator row.
        openOperatorGate(app, timeout: timeout)

        let code = app.textFields["Access code"]
        if code.waitForExistence(timeout: 4) {
            code.tap()
            code.typeText("73142")
            app.buttons["Sign in with code"].tap()
        }

        let link = app.buttons[destination]
        XCTAssertTrue(link.waitForExistence(timeout: timeout),
                      "signed in as an operator, so '\(destination)' is on screen")
        link.tap()
        XCTAssertTrue(app.navigationBars[destination].waitForExistence(timeout: timeout),
                      "\(destination) is pushed")
    }

    /// The DEBUG Simulate section sits at the bottom of a Form, and a lazy list does not
    /// instantiate rows below the fold, so scroll until the button exists.
    private func tapMock(_ app: XCUIApplication, _ label: String) {
        let button = app.buttons[label]
        var swipes = 0
        while !button.exists && swipes < 10 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(button.waitForExistence(timeout: timeout),
                      "the debug Simulate control '\(label)' is present (run this on a DEBUG build)")
        button.tap()
    }

    /// The mock button is at the bottom of the list and the finish form is at the top; a lazy
    /// list does not draw rows off screen, so go back up before looking for the form.
    private func scrollToTop(_ app: XCUIApplication, until element: XCUIElement) {
        var swipes = 0
        while !element.exists && swipes < 10 {
            app.swipeDown()
            swipes += 1
        }
    }

    private func typeZoneName(_ app: XCUIApplication, _ name: String) {
        let field = app.textFields["Zone name"]
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        field.tap()
        field.typeText(name)
        // The keyboard covers the building picker and the Create zone button below the
        // field, and a tap on a covered control is silently swallowed.
        let ret = app.keyboards.buttons.matching(NSPredicate(format: "label ==[c] %@", "return")).firstMatch
        if ret.waitForExistence(timeout: 3) { ret.tap() }
    }

    /// The stock menu Picker: tap the row, then the option. The row is exposed as ONE button
    /// whose label carries the title and the current choice, and its inner static text is not
    /// hittable on its own, so look for the button first. The dump on failure is what makes a
    /// differently-shaped OS build diagnosable without another round of guessing.
    private func pickBuilding(_ app: XCUIApplication, _ name: String) {
        let byLabel = NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Building", "Skip for now")
        let candidates: [XCUIElement] = [
            app.buttons.matching(byLabel).firstMatch,
            app.cells.containing(byLabel).firstMatch,
            app.staticTexts["Skip for now"],
        ]
        _ = candidates[0].waitForExistence(timeout: timeout)
        guard let row = candidates.first(where: { $0.exists && $0.isHittable }) else {
            XCTFail("the building picker row is not tappable. Hierarchy:\n\(app.debugDescription)")
            return
        }
        row.tap()
        let option = app.buttons[name]
        XCTAssertTrue(option.waitForExistence(timeout: timeout), "the picker lists '\(name)'")
        option.tap()
    }
}
