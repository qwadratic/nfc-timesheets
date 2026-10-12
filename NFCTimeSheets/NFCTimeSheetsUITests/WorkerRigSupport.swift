//
//  WorkerRigSupport.swift
//  NFCTimeSheetsUITests
//
//  THE SHARED GROUND OF THE WORKER-RIG UI TESTS (TASK-365.22). Nothing in this file is a
//  fixture of the product: it signs a WORKER in through the real code form - the same
//  CodeSignInSection a worker uses - and offers the handful of helpers every driven walk
//  needs (launch with the DEBUG tap hook, find the idle / running screen, take a picture).
//
//  WHERE THE VALUES COME FROM. Never from this source. `ops/ios-rig/rig.sh test ...` exports
//  them as TEST_RUNNER_TS_RIG_* and Xcode strips the prefix, so the runner sees:
//
//      TS_RIG_CODE_A / TS_RIG_CODE_B   a fresh single-use enrolment code for worker A / B
//      TS_RIG_ZONE_A_VER ...           the seed's zone uuids (the DemoHooks tap takes one)
//      TS_RIG_SHOTS                    a directory the screenshots are written to
//
//  A code that is missing fails the test with a sentence that says how to get one; there is no
//  fallback value, because a hard-coded one would be a credential in the repository and would
//  have expired anyway (15 minutes, single use: decision-63).
//
//  WHAT THIS IS NOT. It is not a mode of the product. The only product hook a test uses is the
//  DEBUG-only `--ts-demo --ts-demo-tap <uuid>` launch argument that already existed (DemoHooks
//  .swift): a simulator has no NFC radio, and that hook injects exactly the id a tag's URL
//  would have produced, so everything after the tap is shipping code. Signing in does NOT use
//  it - it goes through the real form.
//
//  RUNNING: ops/ios-rig/README.md. These tests are NOT part of checks/run.sh (that script is
//  Xcode-free and simulator-free on purpose), same as the other UI tests.
//

import XCTest

enum Rig {
    static let timeout: TimeInterval = 25

    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    static func value(_ key: String) -> String? {
        guard let v = environment[key], !v.isEmpty else { return nil }
        return v
    }

    /// The enrolment code the rig issued for this run. Fails loudly, with the way to get one.
    static func code(_ worker: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        // A code the driver re-issued DURING the test (a worker signs in a second time: the first
        // code was single use) is handed over as <sync>/code_<worker>.txt, which wins.
        if let dir = value("TS_RIG_SYNC"),
           let reissued = try? String(contentsOfFile: "\(dir)/code_\(worker).txt", encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !reissued.isEmpty {
            return reissued
        }
        guard let c = value("TS_RIG_CODE_\(worker)") else {
            XCTFail("no enrolment code for worker \(worker): run this through ops/ios-rig/rig.sh test "
                    + "(which exports TS_RIG_CODE_\(worker)) after `rig.sh new-code \(worker)`",
                    file: file, line: line)
            return ""
        }
        return c
    }

    static func zone(_ key: String) -> String {
        value("TS_RIG_ZONE_\(key)") ?? ""
    }

    /// A value the driver handed over during the test: <TS_RIG_SYNC>/<name>.txt (a zone created
    /// mid-walk, a re-issued code). nil when absent.
    static func syncValue(_ name: String) -> String? {
        guard let dir = value("TS_RIG_SYNC"),
              let text = try? String(contentsOfFile: "\(dir)/\(name).txt", encoding: .utf8)
        else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: rendezvous with the bash driver (walk.sh)
    //
    // A XCUITest cannot shell out, and a walk has to flip SERVER state in the MIDDLE of a
    // screen ("the zone is deactivated after the phone cached it", "stop the server, then
    // tap Start"). So the test announces a named point by writing <TS_RIG_SYNC>/<name>.ready
    // and waits for <name>.go; the driver, which started the test in the background, does the
    // flip between the two. No flip is ever hidden in a test: the driver's log names each one.
    // Without TS_RIG_SYNC (the test run by hand) a rendezvous is a no-op and the walk's own
    // assertions say what is missing.

    private static func syncPath(_ name: String, _ ext: String) -> String? {
        value("TS_RIG_SYNC").map { "\($0)/\(name).\(ext)" }
    }

    @discardableResult
    static func rendezvous(_ name: String, timeout: TimeInterval = 150) -> Bool {
        guard let ready = syncPath(name, "ready"), let go = syncPath(name, "go") else { return false }
        FileManager.default.createFile(atPath: ready, contents: Data("ready".utf8))
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: go) { return true }
            usleep(200_000)
        }
        return false
    }

    /// Appends "<name> <epoch milliseconds>" to <TS_RIG_SYNC>/marks.txt, so the driver can ask
    /// the wire log "what did the app request between these two moments".
    static func mark(_ name: String) {
        guard let dir = value("TS_RIG_SYNC") else { return }
        let line = "\(name) \(Int(Date().timeIntervalSince1970 * 1000))\n"
        let url = URL(fileURLWithPath: dir).appendingPathComponent("marks.txt")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    /// `args`: extra launch arguments. `tap`: a zone uuid to inject through the DEBUG hook.
    static func launch(tap: String? = nil, args: [String] = [], language: String = "en", locale: String = "en_GB",
                       terminateFirst: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        if terminateFirst, app.state != .notRunning { app.terminate() }
        var launch = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale] + args
        if let tap, !tap.isEmpty { launch += ["--ts-demo", "--ts-demo-tap", tap] }
        app.launchArguments = launch
        app.launch()
        return app
    }
}

extension XCTestCase {
    /// The screen a signed-in worker sees with no shift running: the Log tab's idle list.
    func idleScreen(_ app: XCUIApplication) -> XCUIElement {
        let button = app.buttons["Start without a tag"]
        // On a long idle list the button is below the fold of a lazy list: scroll until drawn.
        var swipes = 0
        while !button.exists, swipes < 6, app.navigationBars["TimeSheet"].exists { app.swipeUp(); swipes += 1 }
        return button
    }

    /// What a person does to relaunch: Home first (the app goes to the background, where the
    /// cookie store is flushed to the container), then the app switcher's swipe. Killing the app
    /// while it is still in the foreground loses the session cookie - found while building the
    /// rig: the next launch's first call was a 401 and read as a rejected session.
    func backgroundAndKill(_ app: XCUIApplication) {
        XCUIDevice.shared.press(.home)
        // HTTPCookieStorage writes the cookie jar lazily; a kill inside roughly ten seconds of the
        // sign-in loses it (found on the rig: the relaunch's first call was a 401). A person's
        // swipe-up in the app switcher is never that quick, so the harness waits it out.
        sleep(10)
        app.terminate()
    }

    /// Dismisses a system permission alert (notifications) if one is up, answering ALLOW so the
    /// out-of-app signals (badge, reminders) can actually be observed. Safe to call any time.
    func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "Allow While Using App", "OK"] {
            let button = springboard.alerts.buttons[label]
            if button.exists { button.tap() }
        }
    }

    /// Signs `worker` ("A" or "B") in through the REAL code form, unless that worker is
    /// already signed in on this phone. Ends on the Log tab (idle or running).
    @discardableResult
    func ensureSignedIn(_ app: XCUIApplication, as worker: String) -> Bool {
        let field = app.textFields["Access code"]
        let logTab = app.tabBars.buttons["Log"]
        // Either the sign-in form or the signed-in tab bar appears within a moment of launch.
        let deadline = Date().addingTimeInterval(Rig.timeout)
        while Date() < deadline, !field.exists, !logTab.exists { usleep(250_000) }
        guard field.exists else {
            XCTAssertTrue(logTab.exists, "neither the sign-in form nor the Log tab is on screen")
            return false
        }
        field.tap()
        field.typeText(Rig.code(worker))
        let submit = app.buttons["Sign in with code"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5), "the 'Sign in with code' button is drawn")
        XCTAssertTrue(submit.isEnabled, "five digits are a submittable code (decision-63)")
        submit.tap()
        XCTAssertTrue(logTab.waitForExistence(timeout: Rig.timeout),
                      "after the code is accepted the tab bar with the Log tab is on screen "
                      + "(is the rig up, and is the code fresh? rig.sh new-code \(worker))")
        return true
    }

    /// Waits for the idle list (no shift running) to be on screen.
    /// The idle list's navigation title is "TimeSheet" (the running screen's is "Shift running"),
    /// which stays true however long the list is: a lazy list draws no row below the fold.
    func waitForIdle(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.navigationBars["TimeSheet"].waitForExistence(timeout: Rig.timeout),
                      "the idle Log screen (navigation title 'TimeSheet')", file: file, line: line)
    }

    /// Waits for the running screen (a shift is open).
    func waitForRunning(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.navigationBars["Shift running"].waitForExistence(timeout: Rig.timeout),
                      "the running screen is up ('Shift running')", file: file, line: line)
    }

    /// A PNG of the whole screen into $TS_RIG_SHOTS (and an XCTAttachment, so it also lands in
    /// the .xcresult). `name` is the evidence file's name.
    func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = Rig.value("TS_RIG_SHOTS") {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
            try? screenshot.pngRepresentation.write(to: url)
        }
    }

    /// The accessibility hierarchy as text, into $TS_RIG_SHOTS/<name>.txt - what to read when an
    /// element is not where a walk expects it (an OS build may shape a control differently).
    func dumpHierarchy(_ app: XCUIApplication, _ name: String) {
        guard let dir = Rig.value("TS_RIG_SHOTS") else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).txt")
        try? app.debugDescription.write(to: url, atomically: true, encoding: .utf8)
    }

    /// The first element of any type whose label CONTAINS `text` - the screens draw many
    /// sentences as one static text and the exact wording is asserted separately.
    func anyElement(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    /// The shipping pull-to-refresh gesture on whichever scrolling container is on screen: a
    /// slow drag from near the top of the content to well below it, held a beat at the end so
    /// the control reaches its trigger threshold.
    func pullToRefresh(_ app: XCUIApplication) {
        let list = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.scrollViews.firstMatch
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.6)
}
}
