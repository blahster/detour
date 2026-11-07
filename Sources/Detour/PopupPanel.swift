import AppKit
import Combine
import SwiftUI

/// Replaces NSPopover so the position is exact: centred under the status icon with its top
/// edge 4 pt below the menu bar, and resized in place (top fixed) when the content changes.
/// Idle cost: nothing. Event monitors exist only while the panel is open.
@MainActor
final class PopupPanel: NSObject {
    var onVisibilityChange: ((Bool) -> Void)?

    private let panel: NSPanel
    private let host: NSHostingView<PopoverView>
    private weak var button: NSStatusBarButton?
    private var monitors: [Any] = []
    private var sink: AnyCancellable?

    var isShown: Bool { panel.isVisible }

    init(model: PlayerModel, button: NSStatusBarButton) {
        self.button = button
        host = NSHostingView(rootView: PopoverView(model: model))
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.separatorColor.cgColor

        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor),
            host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect

        // Content height changes with state (idle / choosing / playing / notice).
        sink = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.reposition() }
        }
    }

    func toggle() { isShown ? hide() : show() }

    func show() {
        guard !isShown else { return }
        reposition()
        panel.orderFrontRegardless()
        installMonitors()
        onVisibilityChange?(true)
    }

    func hide() {
        guard isShown else { return }
        panel.orderOut(nil)
        removeMonitors()
        onVisibilityChange?(false)
    }

    // MARK: - Placement

    private func reposition() {
        guard isShown || panel.frame.height > 0 else { return }
        guard let anchor = button?.window?.frame else { return }
        host.layoutSubtreeIfNeeded()
        let size = NSSize(width: 320, height: max(host.fittingSize.height, 60))

        let screenFrame = (NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main)?.frame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = anchor.midX - size.width / 2
        x = min(max(x, screenFrame.minX + 8), screenFrame.maxX - size.width - 8)
        let top = anchor.minY - 4                    // anchor is the menu bar button's window

        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height),
                       display: true)
        panel.invalidateShadow()
    }

    // MARK: - Dismissal

    private func installMonitors() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
                                                     handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }) { monitors.append(m) }

        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown],
                                                    handler: { [weak self] event in
            MainActor.assumeIsolated { () -> NSEvent? in
                guard let self else { return event }
                if event.type == .keyDown {
                    if event.keyCode == 53 { self.hide(); return nil }      // Esc
                    return event
                }
                // Clicks inside the panel, or on the status icon (which toggles), are not "outside".
                if event.window === self.panel || event.window === self.button?.window { return event }
                self.hide()
                return event
            }
        }) { monitors.append(m) }
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }
}
