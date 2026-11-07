import AppKit

// Menu-bar-only app: no Dock icon, no main window.
// Top-level code isn't treated as main-actor code by the Swift 6 compiler, so say so explicitly.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()      // stays alive because run() blocks until quit
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
