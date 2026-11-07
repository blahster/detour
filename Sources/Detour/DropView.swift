import AppKit

/// Accepts dragged text and links. Used as the invisible overlay on the status item button
/// and as the content of the floating drop pad.
final class DropView: NSView {
    var onDrop: ((String) -> Void)?
    var onClick: (() -> Void)?
    var onHighlight: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.string, .URL])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onHighlight?(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onHighlight?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onHighlight?(false)
        let pb = sender.draggingPasteboard
        var text = pb.string(forType: .string)
        if text == nil {
            text = (pb.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL)?.absoluteString
        }
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return false }
        onDrop?(t)
        return true
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
