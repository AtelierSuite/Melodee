import XCTest

/// Walks Melodee through one scene and saves what it shows. Values come in through
/// `TEST_RUNNER_`-prefixed environment variables on xcodebuild.
///
/// `CAPTURE_STEPS` is a list of steps separated by `|`:
///
///     launch              relaunches the app, past onboarding and tips
///     portrait, landscape turns the device
///     tap:<label>         taps the first hittable element whose label contains <label>,
///                         or is exactly it when written as tap:=<label>
///     press:<label>       long-presses it, for context menus
///     back                taps the navigation bar's back button
///     bar                 taps the now playing bar
///     wait:<seconds>      leaves the app to settle
///     shot:<name>         saves the screen to `CAPTURE_OUT_DIR/<name>.png`
final class DriverTests: XCTestCase {

    var application: XCUIApplication!
    var outDirectory: URL!

    @MainActor
    func testScene() throws {
        let environment = ProcessInfo.processInfo.environment
        application = XCUIApplication(bundleIdentifier: try XCTUnwrap(environment["CAPTURE_BUNDLE_ID"]))
        outDirectory = URL(fileURLWithPath: try XCTUnwrap(environment["CAPTURE_OUT_DIR"]))
        let steps = try XCTUnwrap(environment["CAPTURE_STEPS"]).split(separator: "|").map(String.init)
        for step in steps {
            try perform(step)
        }
    }

    @MainActor
    func perform(_ step: String) throws {
        let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
        let argument = parts.count > 1 ? parts[1] : ""
        switch parts[0] {
        case "launch":
            application.terminate()
            application.launchArguments = [
                "-LastOnboardedVersion", "999.0",
                "-SelectedLibrarySource", "local",
                "-com.apple.TipKit.HideAllTips", "1"
            ]
            application.launch()
            sleep(3)
        case "portrait": XCUIDevice.shared.orientation = .portrait
        case "landscape": XCUIDevice.shared.orientation = .landscapeLeft
        case "tap": try element(labelled: argument).tap()
        case "press": try element(labelled: argument).press(forDuration: 1.2)
        case "back":
            let back = application.navigationBars.buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 10), "no back button")
            back.tap()
        case "bar":
            // The bar has no label of its own, so it is tapped where it sits above the home indicator.
            let window = application.windows.firstMatch
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.0))
                .withOffset(CGVector(dx: 0, dy: -70)).tap()
        case "wait": sleep(UInt32(argument) ?? 1)
        case "shot":
            let screenshot = XCUIScreen.main.screenshot()
            try FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: outDirectory.appendingPathComponent("\(argument).png"))
        default:
            XCTFail("unknown step \(step)")
        }
        sleep(1)
    }

    /// Rows often fold their texts into one label, so the label need not start with `label`.
    /// A label written as `=<label>` has to match exactly.
    @MainActor
    func element(labelled label: String) throws -> XCUIElement {
        let predicate = label.hasPrefix("=")
            ? NSPredicate(format: "label == %@", String(label.dropFirst()))
            : NSPredicate(format: "label CONTAINS %@", label)
        let matches = application.descendants(matching: .any).matching(predicate)
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 20), "nothing labelled \(label)")
        // The topmost, so a button in the list wins over its namesake in the now playing bar.
        return matches.allElementsBoundByIndex.filter(\.isHittable).min { $0.frame.minY < $1.frame.minY }
            ?? matches.firstMatch
    }
}
