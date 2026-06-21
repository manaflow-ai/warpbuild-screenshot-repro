// Minimal AppKit host app: shows a titled window. XCUITest launches this and
// calls .activate(); the test asserts it reaches .runningForeground.
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 360, height: 240),
        styleMask: [.titled, .closable, .miniaturizable],
        backing: .buffered, defer: false)
    func applicationDidFinishLaunching(_ note: Notification) {
        window.title = "HostApp"
        let label = NSTextField(labelWithString: "probe host")
        label.frame = NSRect(x: 20, y: 100, width: 200, height: 24)
        window.contentView?.addSubview(label)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
