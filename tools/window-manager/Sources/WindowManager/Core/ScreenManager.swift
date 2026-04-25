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
}

