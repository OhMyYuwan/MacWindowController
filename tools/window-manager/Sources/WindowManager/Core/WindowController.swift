import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

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
    nonisolated(unsafe) private static var raiseGeneration: UInt64 = 0

    @discardableResult
    func ensureAccessibilityPermission(prompt: Bool = true) -> Bool {
        let options: CFDictionary = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func hasAccessibilityPermission() -> Bool {
        ensureAccessibilityPermission(prompt: false)
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
        try raiseResolvedWindow(targetWindow, bundleId: bundleId)
    }

    func raiseWindow(bundleId: String, windowNumber: Int) throws {
        let targetWindow = try resolveAXWindow(bundleId: bundleId, windowNumber: windowNumber)
        try raiseResolvedWindow(targetWindow, bundleId: bundleId)
    }

    func raiseWindowOnly(bundleId: String, windowIndex: Int = 0) throws {
        let targetWindow = try resolveAXWindow(bundleId: bundleId, windowIndex: windowIndex)
        try raiseResolvedWindowOnly(targetWindow, bundleId: bundleId)
    }

    func raiseWindowOnly(bundleId: String, windowNumber: Int) throws {
        let targetWindow = try resolveAXWindow(bundleId: bundleId, windowNumber: windowNumber)
        try raiseResolvedWindowOnly(targetWindow, bundleId: bundleId)
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
        let focusedFrame = frame(for: focused)
        let hint: Int? = {
            if let number {
                return try? findWindowIndex(bundleId: bundleId, windowNumber: number)
            }
            return try? findWindowIndex(bundleId: bundleId, exactTitle: focusedTitle)
        }()
        return WindowIdentity(
            bundleId: bundleId,
            title: focusedTitle,
            windowNumber: number,
            appName: app.localizedName,
            windowIndexHint: hint,
            frameHint: focusedFrame.map(RectData.init)
        )
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
        let hint: Int? = number.flatMap { try? findWindowIndex(bundleId: bundleId, windowNumber: $0) } ?? windowIndex
        return WindowIdentity(
            bundleId: bundleId,
            title: currentTitle,
            windowNumber: number,
            appName: app.localizedName,
            windowIndexHint: hint,
            frameHint: frame(for: targetWindow).map(RectData.init)
        )
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

    func findWindowIndex(bundleId: String, exactTitle title: String) throws -> Int? {
        try findWindowIndex(bundleId: bundleId, exactTitle: title, windowIndexHint: nil, nearFrame: nil)
    }

    func findWindowIndex(
        bundleId: String,
        exactTitle title: String,
        windowIndexHint: Int?,
        nearFrame: CGRect?
    ) throws -> Int? {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return nil }

        let windows = try axWindows(bundleId: bundleId)

        if let hint = windowIndexHint, hint >= 0, hint < windows.count {
            let hintedTitle = self.title(for: windows[hint]).trimmingCharacters(in: .whitespacesAndNewlines)
            if hintedTitle == normalizedTitle {
                return hint
            }
        }

        var candidates: [(index: Int, frame: CGRect?)] = []
        for (index, window) in windows.enumerated() {
            let current = self.title(for: window).trimmingCharacters(in: .whitespacesAndNewlines)
            if current == normalizedTitle {
                candidates.append((index, frame(for: window)))
            }
        }
        guard !candidates.isEmpty else { return nil }

        if let nearFrame {
            let sorted = candidates.sorted { lhs, rhs in
                frameDistance(lhs.frame, nearFrame) < frameDistance(rhs.frame, nearFrame)
            }
            return sorted.first?.index
        }

        return candidates.first?.index
    }

    func findWindowIndex(bundleId: String, windowNumber: Int) throws -> Int? {
        let all = listWindows(onScreenOnly: false).filter { $0.bundleId == bundleId }
        guard let target = all.first(where: { $0.windowNumber == windowNumber }) else {
            return nil
        }

        let targetFrame = target.frame.cgRect
        let targetTitle = target.title
        let ax = try axWindows(bundleId: bundleId)

        for (index, window) in ax.enumerated() {
            if cgWindowID(for: window) == windowNumber {
                return index
            }
        }

        for (index, window) in ax.enumerated() {
            if windowNumberAttribute(for: window) == windowNumber {
                return index
            }
        }

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
        let windows = try axWindows(bundleId: bundleId)
        for window in windows {
            if cgWindowID(for: window) == windowNumber {
                return window
            }
        }
        guard let index = try findWindowIndex(bundleId: bundleId, windowNumber: windowNumber) else {
            throw WindowControllerError.noWindows(bundleId)
        }
        guard index >= 0, index < windows.count else {
            throw WindowControllerError.windowIndexOutOfRange(index)
        }
        return windows[index]
    }

    private func raiseResolvedWindow(_ targetWindow: AXUIElement, bundleId: String) throws {
        let app = try runningApplication(bundleId: bundleId)
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let targetWindowNumber = cgWindowID(for: targetWindow)

        let myGeneration: UInt64 = {
            Self.raiseGeneration &+= 1
            return Self.raiseGeneration
        }()

        raiseWindowElement(targetWindow, appElement: appElement)

        _ = app.unhide()
        _ = app.activate(options: [.activateIgnoringOtherApps])

        raiseWindowElement(targetWindow, appElement: appElement)

        if let targetWindowNumber {
            for delay in [0.05, 0.15] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [bundleId] in
                    let current = Self.raiseGeneration
                    guard current == myGeneration else { return }
                    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else { return }
                    let appElement = AXUIElementCreateApplication(app.processIdentifier)
                    guard let windows = Self.copyAXWindows(for: appElement) else { return }
                    guard let targetWindow = windows.first(where: { Self.cgWindowIDStatic(for: $0) == targetWindowNumber }) else { return }
                    Self.reassertWindow(targetWindow, appElement: appElement)
                }
            }
        }
    }

    private static func reassertWindow(_ window: AXUIElement, appElement: AXUIElement) {
        _ = AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, window)
        _ = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    private static func copyAXWindows(for appElement: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let windows = value as? [AXUIElement], !windows.isEmpty else {
            return nil
        }
        return windows
    }

    private static func cgWindowIDStatic(for window: AXUIElement) -> Int? {
        var windowID: CGWindowID = 0
        guard _AXUIElementGetWindow(window, &windowID) == .success else { return nil }
        return Int(windowID)
    }

    private func raiseResolvedWindowOnly(_ targetWindow: AXUIElement, bundleId: String) throws {
        let app = try runningApplication(bundleId: bundleId)
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        raiseWindowElement(targetWindow, appElement: appElement)

        let finalRaise = AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
        guard finalRaise == .success else {
            throw WindowControllerError.axFailure("raise window only", finalRaise)
        }
    }

    private func raiseWindowElement(_ targetWindow: AXUIElement, appElement: AXUIElement) {
        _ = AXUIElementSetAttributeValue(targetWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        _ = AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, targetWindow)
        _ = AXUIElementSetAttributeValue(targetWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(targetWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
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

    private func cgWindowID(for window: AXUIElement) -> Int? {
        var windowID: CGWindowID = 0
        guard _AXUIElementGetWindow(window, &windowID) == .success else { return nil }
        return Int(windowID)
    }

    private func windowNumberAttribute(for window: AXUIElement) -> Int? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, "AXWindowNumber" as CFString, &value)
        guard result == .success, let value else { return nil }
        if let number = value as? Int {
            return number
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private func frameDistance(_ lhs: CGRect?, _ rhs: CGRect) -> CGFloat {
        guard let lhs else { return .greatestFiniteMagnitude }
        return abs(lhs.origin.x - rhs.origin.x)
            + abs(lhs.origin.y - rhs.origin.y)
            + abs(lhs.size.width - rhs.size.width)
            + abs(lhs.size.height - rhs.size.height)
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

        if let number = cgWindowID(for: window),
           candidates.contains(where: { $0.windowNumber == number }) {
            return number
        }

        if let number = windowNumberAttribute(for: window),
           candidates.contains(where: { $0.windowNumber == number }) {
            return number
        }

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
