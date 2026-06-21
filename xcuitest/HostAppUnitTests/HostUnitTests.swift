import XCTest
import AppKit

// Faithful analog of cmux app-host-unit-tests: an XCTest UNIT test running
// IN-PROCESS inside HostApp.app (TEST_HOST). The ~100 cmux tests that fail on a
// headless runner need the host app to be active/key (first-responder,
// pasteboard, IME marked-text, focus). This asserts that capability directly,
// without any XCUITest separate-runner activation.
final class HostUnitTests: XCTestCase {
    func testHostCanBecomeActiveKey() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)

        // Pump the runloop briefly so WindowServer can settle key/active state.
        let deadline = Date().addingTimeInterval(8)
        while !(app.isActive && window.isKeyWindow) && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2))
        }

        // Also exercise the pasteboard + first-responder paths that headless
        // runners break.
        let pb = NSPasteboard.general
        pb.clearContents()
        let wrote = pb.setString("probe", forType: .string)
        let readBack = pb.string(forType: .string)

        print("host_is_active=\(app.isActive) window_is_key=\(window.isKeyWindow) pb_write=\(wrote) pb_read=\(readBack ?? "nil")")
        XCTAssertTrue(app.isActive, "host app not active (headless GUI session)")
        XCTAssertTrue(window.isKeyWindow, "host window not key (headless GUI session)")
    }
}
