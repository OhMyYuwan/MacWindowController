import AppKit
import Foundation

final class RoundedRectView: NSView {
    let itemID: String
    private let icon: NSImage?
    private let titleLines: [String]
    private var dragStartPoint: NSPoint = .zero
    private var dragStartFrame: NSRect = .zero
    private var isResizing = false
    private(set) var isSelected = false {
        didSet { needsDisplay = true }
    }

    var onFrameChanged: ((String, CGRect) -> Void)?
    var onSelect: ((String) -> Void)?

    init(itemID: String, frame: NSRect, icon: NSImage?, titleLines: [String]) {
        self.itemID = itemID
        self.icon = icon
        self.titleLines = titleLines
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let background = NSColor.systemBlue.withAlphaComponent(isSelected ? 0.45 : 0.25)
        let border = NSColor.systemBlue.withAlphaComponent(isSelected ? 0.9 : 0.55)

        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        background.setFill()
        path.fill()
        border.setStroke()
        path.lineWidth = 2
        path.stroke()

        if let icon {
            icon.draw(in: NSRect(x: 8, y: bounds.height - 34, width: 24, height: 24))
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]

        for (idx, line) in titleLines.prefix(3).enumerated() {
            let drawY = bounds.height - CGFloat(18 + (idx * 15))
            line.draw(in: NSRect(x: 38, y: drawY, width: bounds.width - 48, height: 14), withAttributes: attrs)
        }

        let handleRect = resizeHandleRect
        NSColor.white.withAlphaComponent(0.85).setFill()
        NSBezierPath(ovalIn: handleRect).fill()
    }

    override func mouseDown(with event: NSEvent) {
        isSelected = true
        onSelect?(itemID)
        dragStartPoint = convert(event.locationInWindow, from: nil)
        dragStartFrame = frame
        isResizing = resizeHandleRect.contains(dragStartPoint)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let deltaX = point.x - dragStartPoint.x
        let deltaY = point.y - dragStartPoint.y

        var newFrame = dragStartFrame
        if isResizing {
            newFrame.size.width = max(80, dragStartFrame.width + deltaX)
            newFrame.size.height = max(64, dragStartFrame.height + deltaY)
        } else {
            newFrame.origin.x = dragStartFrame.origin.x + deltaX
            newFrame.origin.y = dragStartFrame.origin.y + deltaY
        }

        frame = newFrame
        onFrameChanged?(itemID, newFrame)
    }

    override func mouseUp(with event: NSEvent) {
        onFrameChanged?(itemID, frame)
    }

    func setSelected(_ selected: Bool) {
        isSelected = selected
    }

    private var resizeHandleRect: NSRect {
        NSRect(x: bounds.width - 12, y: 4, width: 8, height: 8)
    }
}
