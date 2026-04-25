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
}

