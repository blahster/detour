import AppKit

/// While text is being dragged anywhere on screen, shows a small "Drop" pad directly under the
/// menu bar icon. Dragging all the way into the menu bar makes macOS open Mission Control, so
/// the pad gives you a target just below it.
///
/// Cost when idle: two global mouse-event monitors whose handlers return after one cheap check.
@MainActor
final class DropPad {
    var onDrop: ((String) -> Void)?
    var onShow: (() -> Void)?
    /// Screen-coordinate frame of the status item's button window.
    var anchor: (() -> NSRect?)?

    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var seenChangeCount = NSPasteboard(name: .drag).changeCount
    private var hideWork: DispatchWorkItem?

    private let size = NSSize(width: 108, height: 38)
    private var isShown: Bool { panel?.isVisible ?? false }

    func start() {
        guard monitors.isEmpty else { return }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dragged() }
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.released() }
        }) { monitors.append(m) }
    }

    // MARK: - Drag tracking

    private func dragged() {
        if isShown { scheduleHide(); return }

        let pb = NSPasteboard(name: .drag)
        guard pb.changeCount != seenChangeCount else { return }   // same drag we already looked at
        seenChangeCount = pb.changeCount

        // Text drags only. Dragging files or windows shouldn't summon the pad.
        let types = pb.types ?? []
        guard types.contains(.string), !types.contains(.fileURL) else { return }

        show()
        scheduleHide()
    }

    private func released() {
        if isShown { scheduleHide(after: 0.5) }
    }

    // MARK: - Panel

    private func show() {
        guard let a = anchor?() else { return }
        let p = panel ?? makePanel()
        panel = p

        let screenFrame = (NSScreen.screens.first { $0.frame.intersects(a) } ?? NSScreen.main)?.frame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = a.midX - size.width / 2
        x = min(max(x, screenFrame.minX + 8), screenFrame.maxX - size.width - 8)
        p.setFrame(NSRect(x: x, y: a.minY - 4 - size.height, width: size.width, height: size.height), display: true)

        onShow?()
        p.orderFrontRegardless()
    }

    private func hide() {
        hideWork?.cancel()
        hideWork = nil
        panel?.orderOut(nil)
        seenChangeCount = NSPasteboard(name: .drag).changeCount   // don't re-show for the same drag
    }

    /// Safety net: if no drag events arrive for a while (drag cancelled, dropped elsewhere), hide.
    private func scheduleHide(after seconds: TimeInterval = 1.5) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.hide() }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func cancelHide() {
        hideWork?.cancel()
        hideWork = nil
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let drop = DropView(frame: NSRect(origin: .zero, size: size))

        let effect = NSVisualEffectView(frame: drop.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        drop.addSubview(effect)

        let icon = NSImageView(image: NSImage(systemSymbolName: "music.note", accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let label = NSTextField(labelWithString: "Drop")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
        ])

        drop.onHighlight = { [weak self, weak effect] on in
            effect?.material = on ? .selection : .hudWindow
            if on { self?.cancelHide() } else { self?.scheduleHide() }
        }
        drop.onDrop = { [weak self] text in
            self?.onDrop?(text)
            self?.hide()
        }

        p.contentView = drop
        return p
    }
}
