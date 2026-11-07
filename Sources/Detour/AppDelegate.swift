import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popup: PopupPanel!
    private let model = PlayerModel()
    private let pad = DropPad()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }

        button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Detour")
        button.target = self
        button.action = #selector(togglePopup)

        // Dropping straight onto the icon works, but dragging that far up trips Mission Control.
        let drop = DropView(frame: button.bounds)
        drop.autoresizingMask = [.width, .height]
        drop.onDrop = { [weak self] text in self?.model.handleDrop(text) }
        drop.onClick = { [weak self] in self?.togglePopup() }
        drop.onHighlight = { [weak button] on in button?.highlight(on) }
        button.addSubview(drop)

        popup = PopupPanel(model: model, button: button)
        popup.onVisibilityChange = { [weak self] visible in self?.model.setPopoverVisible(visible) }

        // The drop pad sits just under the icon whenever text is being dragged.
        pad.anchor = { [weak button] in button?.window?.frame }
        pad.onShow = { [weak self] in self?.popup.hide() }
        pad.onDrop = { [weak self] text in self?.model.handleDrop(text) }
        pad.start()

        model.onNeedsAttention = { [weak self] in self?.popup.show() }
    }

    @objc private func togglePopup() { popup.toggle() }
}
