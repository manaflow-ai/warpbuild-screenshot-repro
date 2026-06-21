import XCTest

// The faithful Warp-vs-Blacksmith discriminator: a real XCUITest that launches
// the host app through testmanagerd and checks it reaches the foreground. This
// is exactly the mechanism ~100 cmux unit/UI tests rely on. Apps stuck
// "Running Background" fail here.
final class ProbeUITests: XCTestCase {
    func testActivateForeground() throws {
        let app = XCUIApplication()
        app.launch()
        app.activate()
        let deadline = Date().addingTimeInterval(20)
        while app.state != .runningForeground && Date() < deadline {
            usleep(200_000)
        }
        XCTAssertEqual(
            app.state, .runningForeground,
            "app did not reach foreground (state=\(app.state.rawValue)); this is the 'Running Background' headless blocker")
    }
}
