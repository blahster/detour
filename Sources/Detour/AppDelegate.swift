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

        setIcon(playing: false, tooltip: "Detour: drop a song title here")
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
        model.onIconChange = { [weak self] playing, tip in
            self?.setIcon(playing: playing, tooltip: tip ?? "Detour: drop a song title here")
        }
    }

    private func setIcon(playing: Bool, tooltip: String) {
        guard let button = statusItem.button else { return }
        let name = playing ? "waveform" : "music.note"
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: "Detour")
        button.toolTip = tooltip
    }

    @objc private func togglePopup() { popup.toggle() }
}
