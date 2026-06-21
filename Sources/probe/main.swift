// Minimal AppKit foreground/GUI-session probe.
//
// It opens a normal window, asks to become the active app, then checks whether
// the OS actually let it. On a runner with a logged-in Aqua/WindowServer
// session this PASSES. On a headless runner (no console login session) the app
// stays in the background and cannot get a key window, so it FAILS with the
// same root cause that makes XCUITest report:
//   "Failed to activate application ... (current state: Running Background)"
//
// No Xcode project, no test host, no third-party deps. Build with one swiftc.

import AppKit
import CoreGraphics
import Foundation

func line(_ s: String) {
    FileHandle.standardOutput.write(Data((s + "\n").utf8))
    // When launched as a .app via LaunchServices (`open`), stdout is detached,
    // so also append to PROBE_OUT for the shell to read back.
    if let out = ProcessInfo.processInfo.environment["PROBE_OUT"] {
        if let h = FileHandle(forWritingAtPath: out) {
            h.seekToEndOfFile(); h.write(Data((s + "\n").utf8)); try? h.close()
        } else {
            try? (s + "\n").data(using: .utf8)?.write(to: URL(fileURLWithPath: out))
        }
    }
}

// Hard watchdog: if we cannot even reach a verdict (e.g. there is no
// WindowServer to connect to and AppKit hangs), fail loudly instead of
// hanging the CI job until its timeout.
Thread.detachNewThread {
    Thread.sleep(forTimeInterval: 25)
    line("RESULT: FAIL (timed out before a verdict; likely no WindowServer/GUI session)")
    exit(3)
}

final class Probe: NSObject, NSApplicationDelegate {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )

    func applicationDidFinishLaunching(_ note: Notification) {
        window.title = "probe"
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Give the window server a beat to settle key/active state.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.verdict() }
    }

    func verdict() {
        let sess = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
        let onConsole = (sess[kCGSessionOnConsoleKey as String] as? Bool) ?? false
        let isActive = NSApp.isActive
        let isKey = window.isKeyWindow

        line("nsapp_is_active=\(isActive)")
        line("window_is_key=\(isKey)")
        line("cgsession_on_console=\(onConsole)")
        line("cgsession_present=\(!sess.isEmpty)")
        line("main_display_id=\(CGMainDisplayID())")

        let ok = isActive && isKey
        if ok {
            line("RESULT: PASS - app reached the foreground with a key window (logged-in GUI session present)")
        } else {
            line("RESULT: FAIL - app could not become active/key (no foreground GUI session)")
            line("         This is the root cause of the XCUITest 'Running Background' activation error")
            line("         and of macOS unit tests that need key-window / pasteboard / IME / focus.")
        }
        exit(ok ? 0 : 1)
    }
}

let probe = Probe()
let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.delegate = probe
app.run()
