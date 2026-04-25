import AppKit
import Foundation

final class LayoutCanvas: NSView {
    override var isFlipped: Bool { true }

    private enum ItemKind {
        case window(index: Int)
        case stack(index: Int)
    }

    private struct ItemPresentation {
        var id: String
        var kind: ItemKind
        var desktopFrame: CGRect
        var titleLines: [String]
        var bundleId: String
    }

    private var layoutModel: DesktopLayout
    private let displayFrame: CGRect
    private var items: [ItemPresentation] = []
    private var viewsByID: [String: RoundedRectView] = [:]

    init(layout: DesktopLayout, displayFrame: CGRect) {
        self.layoutModel = layout
        self.displayFrame = displayFrame
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor
        rebuildItems()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        relayoutViews()
    }

    func setLayout(_ layout: DesktopLayout) {
        layoutModel = layout
        rebuildItems()
        relayoutViews()
    }

    func updatedLayout(description: String) -> DesktopLayout {
        var updated = layoutModel
        updated.description = description

        for item in items {
            switch item.kind {
            case .window(let index):
                if updated.windows.indices.contains(index) {
                    updated.windows[index].frame = RectData(item.desktopFrame)
                }
            case .stack(let index):
                if updated.stacks.indices.contains(index) {
                    updated.stacks[index].frame = RectData(item.desktopFrame)
                }
            }
        }
        return updated
    }

    private func rebuildItems() {
        viewsByID.values.forEach { $0.removeFromSuperview() }
        viewsByID.removeAll()
        items.removeAll()

        for (index, window) in layoutModel.windows.enumerated() {
            let item = ItemPresentation(
                id: "window-\(index)",
                kind: .window(index: index),
                desktopFrame: window.frame.cgRect,
                titleLines: [window.appName, window.title].filter { !$0.isEmpty },
                bundleId: window.bundleId
            )
            items.append(item)
        }

        for (index, stack) in layoutModel.stacks.enumerated() {
            let names = stack.windows.map(\.appName)
            let item = ItemPresentation(
                id: "stack-\(index)",
                kind: .stack(index: index),
                desktopFrame: stack.frame.cgRect,
                titleLines: ["[Stack] \(stack.name)"] + Array(names.prefix(2)),
                bundleId: stack.windows.first?.bundleId ?? ""
            )
            items.append(item)
        }

        for item in items {
            let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundleId)
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
            let view = RoundedRectView(
                itemID: item.id,
                frame: toCanvasRect(item.desktopFrame),
                icon: icon,
                titleLines: item.titleLines
            )
            view.onFrameChanged = { [weak self] id, frame in
                self?.updateDesktopFrame(for: id, from: frame)
            }
            view.onSelect = { [weak self] id in
                self?.setSelection(id: id)
            }
            addSubview(view)
            viewsByID[item.id] = view
        }
    }

    private func relayoutViews() {
        for item in items {
            guard let view = viewsByID[item.id] else { continue }
            view.frame = toCanvasRect(item.desktopFrame)
        }
    }

    private func updateDesktopFrame(for id: String, from canvasFrame: CGRect) {
        guard let itemIndex = items.firstIndex(where: { $0.id == id }) else {
            return
        }

        let desktop = toDesktopRect(canvasFrame)
        items[itemIndex].desktopFrame = desktop

        switch items[itemIndex].kind {
        case .window(let index):
            if layoutModel.windows.indices.contains(index) {
                layoutModel.windows[index].frame = RectData(desktop)
            }
        case .stack(let index):
            if layoutModel.stacks.indices.contains(index) {
                layoutModel.stacks[index].frame = RectData(desktop)
            }
        }
    }

    private func setSelection(id: String) {
        for (itemID, view) in viewsByID {
            view.setSelected(itemID == id)
        }
    }

    private func toCanvasRect(_ desktopRect: CGRect) -> CGRect {
        let scaleX = bounds.width / max(displayFrame.width, 1)
        let scaleY = bounds.height / max(displayFrame.height, 1)

        let x = (desktopRect.minX - displayFrame.minX) * scaleX
        let yFromTop = (displayFrame.maxY - desktopRect.maxY) * scaleY
        let width = desktopRect.width * scaleX
        let height = desktopRect.height * scaleY

        return CGRect(x: x, y: yFromTop, width: width, height: height)
    }

    private func toDesktopRect(_ canvasRect: CGRect) -> CGRect {
        let scaleX = max(displayFrame.width, 1) / max(bounds.width, 1)
        let scaleY = max(displayFrame.height, 1) / max(bounds.height, 1)

        let width = canvasRect.width * scaleX
        let height = canvasRect.height * scaleY
        let x = displayFrame.minX + (canvasRect.minX * scaleX)
        let maxY = displayFrame.maxY - (canvasRect.minY * scaleY)
        let y = maxY - height

        return CGRect(x: x, y: y, width: width, height: height)
    }
}
