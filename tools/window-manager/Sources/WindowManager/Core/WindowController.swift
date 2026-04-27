import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum WindowControllerError: LocalizedError {
    case appNotRunning(String)
    case appNotInstalled(String)
    case accessibilityNotTrusted
    case noWindows(String)
    case windowIndexOutOfRange(Int)
    case axFailure(String, AXError)

    var errorDescription: String? {
        switch self {
        case .appNotRunning(let bundleId):
            return "Application is not running: \(bundleId)"
        case .appNotInstalled(let bundleId):
            return "Application is not installed: \(bundleId)"
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
            let bundleId = runningApp?.bundleIdentifier ?? WindowInfo.unknownBundleId
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

    func setWindowFrame(bundleId: String, windowNumber: Int, frame: CGRect) throws {
        let targetWindow = try resolveAXWindow(bundleId: bundleId, windowNumber: windowNumber)
        try setPosition(window: targetWindow, point: frame.origin)
        try setSize(window: targetWindow, size: frame.size)
    }

    func raiseWindow(bundleId: String, windowIndex: Int = 0) throws {
        let targetWindow = try resolveAXWindow(bundleId: bundleId, windowIndex: windowIndex)
        let result = AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
        guard result == .success else {
            throw WindowControllerError.axFailure("raise window", result)
        }
        let app = try runningApplication(bundleId: bundleId)
        _ = app.activate(options: [.activateIgnoringOtherApps])
    }

    func raiseWindow(bundleId: String, windowNumber: Int) throws {
        let targetWindow = try resolveAXWindow(bundleId: bundleId, windowNumber: windowNumber)
        let result = AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
        guard result == .success else {
            throw WindowControllerError.axFailure("raise window", result)
        }
        let app = try runningApplication(bundleId: bundleId)
        _ = app.activate(options: [.activateIgnoringOtherApps])
    }

    func setWindowMinimized(bundleId: String, windowIndex: Int = 0, minimized: Bool) throws {
        let targetWindow = try resolveAXWindow(bundleId: bundleId, windowIndex: windowIndex)
        let boolValue: CFBoolean = minimized ? kCFBooleanTrue : kCFBooleanFalse
        let result = AXUIElementSetAttributeValue(targetWindow, kAXMinimizedAttribute as CFString, boolValue)
        guard result == .success else {
            throw WindowControllerError.axFailure("set minimized", result)
        }
    }

    func setWindowMinimized(bundleId: String, windowNumber: Int, minimized: Bool) throws {
        let targetWindow = try resolveAXWindow(bundleId: bundleId, windowNumber: windowNumber)
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

    func launchApp(bundleId: String, activate: Bool = true) throws {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            if activate {
                _ = running.activate(options: [.activateIgnoringOtherApps])
            }
            return
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            throw WindowControllerError.appNotInstalled(bundleId)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activate
        configuration.hides = false

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error {
                NSLog("window-manager launch failed for %@: %@", bundleId, error.localizedDescription)
            }
        }
    }

    func windowTitle(bundleId: String, windowIndex: Int = 0) throws -> String {
        let targetWindow = try resolveAXWindow(bundleId: bundleId, windowIndex: windowIndex)
        return title(for: targetWindow)
    }

    func windowTitle(bundleId: String, windowNumber: Int) throws -> String {
        let targetWindow = try resolveAXWindow(bundleId: bundleId, windowNumber: windowNumber)
        return title(for: targetWindow)
    }

    func windowCount(bundleId: String) throws -> Int {
        try axWindows(bundleId: bundleId).count
    }

    func windowInfo(bundleId: String, windowNumber: Int) -> WindowInfo? {
        listWindows(onScreenOnly: false)
            .first { $0.bundleId == bundleId && $0.windowNumber == windowNumber }
    }

    func frontmostBundleId() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func frontmostWindowIdentity(ignoringCurrentProcess: Bool = false) -> WindowIdentity? {
        guard
            let app = NSWorkspace.shared.frontmostApplication,
            let bundleId = app.bundleIdentifier
        else {
            return nil
        }

        if ignoringCurrentProcess, app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedRef)
        guard result == .success, let focusedWindow = focusedRef else {
            return nil
        }

        let focused = focusedWindow as! AXUIElement
        let focusedTitle = title(for: focused)
        let number = windowNumber(for: focused, bundleId: bundleId, pid: app.processIdentifier, expectedTitle: focusedTitle)
        return WindowIdentity(bundleId: bundleId, title: focusedTitle, windowNumber: number)
    }

    func windowIdentity(bundleId: String, windowIndex: Int = 0) throws -> WindowIdentity {
        let app = try runningApplication(bundleId: bundleId)
        let targetWindow = try resolveAXWindow(bundleId: bundleId, windowIndex: windowIndex)
        let currentTitle = title(for: targetWindow)
        let number = windowNumber(
            for: targetWindow,
            bundleId: bundleId,
            pid: app.processIdentifier,
            expectedTitle: currentTitle
        )
        return WindowIdentity(bundleId: bundleId, title: currentTitle, windowNumber: number)
    }

    func findWindowIndex(bundleId: String, titleContains query: String) throws -> Int? {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return nil }

        let windows = try axWindows(bundleId: bundleId)
        for (index, window) in windows.enumerated() {
            let titleValue = title(for: window).lowercased()
            if titleValue.contains(normalizedQuery) {
                return index
            }
        }
        return nil
    }

    func findWindowIndex(bundleId: String, windowNumber: Int) throws -> Int? {
        let all = listWindows(onScreenOnly: false).filter { $0.bundleId == bundleId }
        guard let target = all.first(where: { $0.windowNumber == windowNumber }) else {
            return nil
        }

        let targetFrame = target.frame.cgRect
        let targetTitle = target.title
        let ax = try axWindows(bundleId: bundleId)
        var best: (index: Int, score: Double)?

        for (index, window) in ax.enumerated() {
            let titlePenalty: Double = {
                let axTitle = title(for: window)
                if targetTitle.isEmpty {
                    return 0
                }
                return axTitle == targetTitle ? -100_000 : 10_000
            }()

            let framePenalty: Double = {
                guard let frame = frame(for: window) else {
                    return 1_000_000
                }
                return abs(Double(frame.origin.x - targetFrame.origin.x))
                    + abs(Double(frame.origin.y - targetFrame.origin.y))
                    + abs(Double(frame.size.width - targetFrame.size.width))
                    + abs(Double(frame.size.height - targetFrame.size.height))
            }()

            let score = titlePenalty + framePenalty
            if best == nil || score < best!.score {
                best = (index, score)
            }
        }

        return best?.index
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

        let manageable = windows.filter(isManageableWindow)
        guard !manageable.isEmpty else {
            throw WindowControllerError.noWindows(bundleId)
        }
        return manageable
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

    private func resolveAXWindow(bundleId: String, windowNumber: Int) throws -> AXUIElement {
        guard let index = try findWindowIndex(bundleId: bundleId, windowNumber: windowNumber) else {
            throw WindowControllerError.noWindows(bundleId)
        }
        return try resolveAXWindow(bundleId: bundleId, windowIndex: index)
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

    private func isManageableWindow(_ window: AXUIElement) -> Bool {
        guard stringAttribute(window, attribute: kAXRoleAttribute as CFString) == kAXWindowRole as String else {
            return false
        }

        if let subrole = stringAttribute(window, attribute: kAXSubroleAttribute as CFString) {
            let allowedSubroles: Set<String> = [
                kAXStandardWindowSubrole as String,
                kAXDialogSubrole as String,
                kAXSystemDialogSubrole as String
            ]
            if !allowedSubroles.contains(subrole) {
                return false
            }
        }

        guard attributeIsSettable(window, attribute: kAXPositionAttribute as CFString),
              attributeIsSettable(window, attribute: kAXSizeAttribute as CFString)
        else {
            return false
        }

        return true
    }

    private func attributeIsSettable(_ element: AXUIElement, attribute: CFString) -> Bool {
        var settable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(element, attribute, &settable)
        return result == .success && settable.boolValue
    }

    private func stringAttribute(_ element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private func frame(for window: AXUIElement) -> CGRect? {
        guard
            let position = pointAttribute(window, attribute: kAXPositionAttribute as CFString),
            let size = sizeAttribute(window, attribute: kAXSizeAttribute as CFString)
        else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func pointAttribute(_ element: AXUIElement, attribute: CFString) -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard
            result == .success,
            let cfValue = value,
            CFGetTypeID(cfValue) == AXValueGetTypeID()
        else {
            return nil
        }
        let axValue = cfValue as! AXValue
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func sizeAttribute(_ element: AXUIElement, attribute: CFString) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard
            result == .success,
            let cfValue = value,
            CFGetTypeID(cfValue) == AXValueGetTypeID()
        else {
            return nil
        }
        let axValue = cfValue as! AXValue
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    private func windowNumber(
        for window: AXUIElement,
        bundleId: String,
        pid: pid_t,
        expectedTitle: String
    ) -> Int? {
        let candidates = listWindows(onScreenOnly: false).filter { info in
            info.bundleId == bundleId && info.pid == pid
        }
        guard !candidates.isEmpty else { return nil }

        let axFrame = frame(for: window)
        var best: (number: Int, score: Double)?
        for candidate in candidates {
            let titlePenalty: Double
            if expectedTitle.isEmpty {
                titlePenalty = 0
            } else {
                titlePenalty = candidate.title == expectedTitle ? -100_000 : 10_000
            }

            let sizePenalty: Double = {
                if candidate.frame.width < 120 || candidate.frame.height < 120 {
                    return 50_000
                }
                return 0
            }()

            let framePenalty: Double = {
                guard let axFrame else { return 0 }
                let candidateFrame = candidate.frame.cgRect
                return abs(Double(candidateFrame.origin.x - axFrame.origin.x))
                    + abs(Double(candidateFrame.origin.y - axFrame.origin.y))
                    + abs(Double(candidateFrame.size.width - axFrame.size.width))
                    + abs(Double(candidateFrame.size.height - axFrame.size.height))
            }()

            let score = titlePenalty + sizePenalty + framePenalty
            if best == nil || score < best!.score {
                best = (candidate.windowNumber, score)
            }
        }
        return best?.number
    }
}
