import AppKit
import CoreGraphics
import Foundation

final class ScreenManager {
    func mainVisibleFrame() -> CGRect {
        NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
    }

    func visibleFrame(displayIndex: Int?) -> CGRect {
        guard
            let displayIndex,
            displayIndex >= 0,
            displayIndex < NSScreen.screens.count
        else {
            return mainVisibleFrame()
        }
        return NSScreen.screens[displayIndex].visibleFrame
    }

    // MARK: - Coordinate System Conversion

    /// Convert NSWindow coordinates to AX/Screen coordinates
    /// NSWindow: origin at bottom-left, y increases upward
    /// AX/Screen: origin at top-left, y increases downward
    func convertToScreenCoordinates(_ rect: CGRect, screenHeight: CGFloat) -> CGRect {
        return CGRect(
            x: rect.minX,
            y: screenHeight - (rect.minY + rect.height),
            width: rect.width,
            height: rect.height
        )
    }

    /// Convert AX/Screen coordinates to NSWindow coordinates
    /// AX/Screen: origin at top-left, y increases downward
    /// NSWindow: origin at bottom-left, y increases upward
    func convertToNSWindowCoordinates(_ rect: CGRect, screenHeight: CGFloat) -> CGRect {
        return CGRect(
            x: rect.minX,
            y: screenHeight - (rect.minY + rect.height),
            width: rect.width,
            height: rect.height
        )
    }

    /// Get main screen visible frame in AX/Screen coordinates
    func mainVisibleFrameInScreenCoordinates() -> CGRect {
        guard let screen = NSScreen.main else { return .zero }
        let nsWindowFrame = screen.visibleFrame
        let screenHeight = screen.frame.height
        return convertToScreenCoordinates(nsWindowFrame, screenHeight: screenHeight)
    }

    /// Get visible frame in AX/Screen coordinates for a specific display
    func visibleFrameInScreenCoordinates(displayIndex: Int?) -> CGRect {
        guard
            let displayIndex,
            displayIndex >= 0,
            displayIndex < NSScreen.screens.count
        else {
            return mainVisibleFrameInScreenCoordinates()
        }
        let screen = NSScreen.screens[displayIndex]
        let nsWindowFrame = screen.visibleFrame
        let screenHeight = screen.frame.height
        return convertToScreenCoordinates(nsWindowFrame, screenHeight: screenHeight)
    }

    func displaySnapshots() -> [LayoutDisplaySnapshot] {
        NSScreen.screens.enumerated().map { index, screen in
            let screenHeight = screen.frame.height
            let idNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let id = idNumber?.uint32Value ?? UInt32(index)
            return LayoutDisplaySnapshot(
                id: id,
                index: index,
                name: screen.localizedName,
                frame: RectData(convertToScreenCoordinates(screen.frame, screenHeight: screenHeight)),
                visibleFrame: RectData(convertToScreenCoordinates(screen.visibleFrame, screenHeight: screenHeight))
            )
        }
    }

    func displaySnapshot(id: UInt32?) -> LayoutDisplaySnapshot? {
        let displays = displaySnapshots()
        if let id, let exact = displays.first(where: { $0.id == id }) {
            return exact
        }
        return displays.first
    }

    func preferredDisplaySnapshot(for windows: [WindowInfo]) -> LayoutDisplaySnapshot? {
        let displays = displaySnapshots()
        guard !displays.isEmpty else { return nil }
        guard !windows.isEmpty else { return displays.first }

        var scores: [UInt32: CGFloat] = [:]
        for window in windows {
            let center = CGPoint(x: window.frame.cgRect.midX, y: window.frame.cgRect.midY)
            if let display = displays.first(where: { $0.visibleFrame.cgRect.contains(center) }) {
                scores[display.id, default: 0] += max(1, window.frame.cgRect.width * window.frame.cgRect.height)
            }
        }
        guard let bestId = scores.max(by: { $0.value < $1.value })?.key else {
            return displays.first
        }
        return displays.first(where: { $0.id == bestId }) ?? displays.first
    }
}
