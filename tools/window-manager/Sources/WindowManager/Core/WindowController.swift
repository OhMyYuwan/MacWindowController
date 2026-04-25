import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum WindowControllerError: LocalizedError {
    case appNotRunning(String)
    case accessibilityNotTrusted
    case noWindows(String)
    case windowIndexOutOfRange(Int)
    case axFailure(String, AXError)

    var errorDescription: String? {
        switch self {
        case .appNotRunning(let bundleId):
            return "Application is not running: \(bundleId)"
        case .accessibilityNotTrusted:
            return "Accessibility permission is required. Please grant permissions in System Settings -> Privacy & Security -> Accessibility."
        case .noWindows(let bundleId):
            return "No controllable windows found for \(bundleId)"
        case .windowIndexOutOfRange(let index):
            return "Window index out of range: \(index)"
        case .axFailure(let action, let error):
            return "AX operation failed during \(action): \(error.rawValue)"
        }
    }
}

final class WindowController {
    private let layoutEngine = LayoutEngine()

    @discardableResult
    func ensureAccessibilityPermission(prompt: Bool = true) -> Bool {
        let options: CFDictionary = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func listWindows(onScreenOnly: Bool = true) -> [WindowInfo] {
        var options: CGWindowListOption = [.excludeDesktopElements]
        if onScreenOnly {
            options.insert(.optionOnScreenOnly)
        } else {
            options.insert(.optionAll)
        }

        guard
            let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else {
            return []
        }

        return rawList.compactMap { windowDict in
            guard let layer = windowDict[kCGWindowLayer as String] as? Int, layer == 0 else {
                return nil
            }

            guard let pid = windowDict[kCGWindowOwnerPID as String] as? Int32 else {
                return nil
            }

            guard
                let bounds = windowDict[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds)
            else {
                return nil
            }

            guard frame.width > 1, frame.height > 1 else {
                return nil
            }

            let runningApp = NSRunningApplication(processIdentifier: pid)
            let bundleId = runningApp?.bundleIdentifier ?? "unknown.bundle"
            let ownerName = windowDict[kCGWindowOwnerName as String] as? String ?? bundleId
            let title = (windowDict[kCGWindowName as String] as? String) ?? ""
            let windowNumber = windowDict[kCGWindowNumber as String] as? Int ?? -1

            return WindowInfo(
                bundleId: bundleId,
                appName: ownerName,
                pid: pid,
                windowNumber: windowNumber,
                title: title,
                frame: RectData(frame),
                isOnScreen: onScreenOnly
            )
        }
    }

    func tileWindow(bundleId: String, position: TilePosition, in screenFrame: CGRect, windowIndex: Int = 0) throws {
        let frame = layoutEngine.frame(for: position, in: screenFrame)
        try setWindowFrame(bundleId: bundleId, windowIndex: windowIndex, frame: frame)
    }

    func moveWindow(bundleId: String, windowIndex: Int = 0, to point: CGPoint) throws {
        let targetWindow = try resolveAXWindow(bundleId: bundleId, windowIndex: windowIndex)
        try setPosition(window: targetWindow, point: point)
    }

    func resizeWindow(bundleId: String, windowIndex: Int = 0, to size: CGSize) throws {
        let targetWindow = try resolveAXWindow(bundleId: bundleId, windowIndex: windowIndex)
        try setSize(window: targetWindow, size: size)
    }

    func setWindowFrame(bundleId: String, windowIndex: Int = 0, frame: CGRect) throws {
        let targetWindow = try resolveAXWindow(bundleId: bundleId, windowIndex: windowIndex)
        try setPosition(window: targetWindow, point: frame.origin)
        try setSize(window: targetWindow, size: frame.size)
    }

    func setWindowMinimized(bundleId: String, windowIndex: Int = 0, minimized: Bool) throws {
        let targetWindow = try resolveAXWindow(bundleId: bundleId, windowIndex: windowIndex)
        let boolValue: CFBoolean = minimized ? kCFBooleanTrue : kCFBooleanFalse
        let result = AXUIElementSetAttributeValue(targetWindow, kAXMinimizedAttribute as CFString, boolValue)
        guard result == .success else {
            throw WindowControllerError.axFailure("set minimized", result)
        }
    }

    func activateApp(bundleId: String) throws {
        let app = try runningApplication(bundleId: bundleId)
        _ = app.activate(options: [.activateIgnoringOtherApps])
    }

    func windowTitle(bundleId: String, windowIndex: Int = 0) throws -> String {
        let targetWindow = try resolveAXWindow(bundleId: bundleId, windowIndex: windowIndex)
        return title(for: targetWindow)
    }

    func windowCount(bundleId: String) throws -> Int {
        try axWindows(bundleId: bundleId).count
    }

    private func runningApplication(bundleId: String) throws -> NSRunningApplication {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
            throw WindowControllerError.appNotRunning(bundleId)
        }
        return app
    }

    private func axWindows(bundleId: String) throws -> [AXUIElement] {
        guard ensureAccessibilityPermission(prompt: true) else {
            throw WindowControllerError.accessibilityNotTrusted
        }

        let app = try runningApplication(bundleId: bundleId)
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        guard result == .success else {
            throw WindowControllerError.axFailure("list windows", result)
        }

        guard let windows = value as? [AXUIElement], !windows.isEmpty else {
            throw WindowControllerError.noWindows(bundleId)
        }
        return windows
    }

    private func resolveAXWindow(bundleId: String, windowIndex: Int) throws -> AXUIElement {
        let windows = try axWindows(bundleId: bundleId)
        guard windowIndex >= 0 else {
            throw WindowControllerError.windowIndexOutOfRange(windowIndex)
        }
        guard windowIndex < windows.count else {
            throw WindowControllerError.windowIndexOutOfRange(windowIndex)
        }
        return windows[windowIndex]
    }

    private func setPosition(window: AXUIElement, point: CGPoint) throws {
        var mutablePoint = point
        guard let axValue = AXValueCreate(.cgPoint, &mutablePoint) else {
            throw WindowControllerError.axFailure("create point value", .failure)
        }

        let result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, axValue)
        guard result == .success else {
            throw WindowControllerError.axFailure("set position", result)
        }
    }

    private func setSize(window: AXUIElement, size: CGSize) throws {
        var mutableSize = size
        guard let axValue = AXValueCreate(.cgSize, &mutableSize) else {
            throw WindowControllerError.axFailure("create size value", .failure)
        }

        let result = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, axValue)
        guard result == .success else {
            throw WindowControllerError.axFailure("set size", result)
        }
    }

    private func title(for window: AXUIElement) -> String {
        var titleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
        guard result == .success else { return "" }
        return titleRef as? String ?? ""
    }
}
