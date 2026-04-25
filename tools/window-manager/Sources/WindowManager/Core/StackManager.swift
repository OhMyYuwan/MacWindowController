import AppKit
import CoreGraphics
import Foundation

enum StackManagerError: LocalizedError {
    case stackExists(String)
    case stackMissing(String)
    case emptyStackWindows
    case invalidActiveIndex
    case invalidName

    var errorDescription: String? {
        switch self {
        case .stackExists(let name):
            return "Stack already exists: \(name)"
        case .stackMissing(let name):
            return "Stack not found: \(name)"
        case .emptyStackWindows:
            return "Stack windows list cannot be empty"
        case .invalidActiveIndex:
            return "Active index is out of range"
        case .invalidName:
            return "Stack name cannot be empty"
        }
    }
}

final class StackManager {
    static let desktopTabBarHeight: CGFloat = 38
    private let windowController: WindowController
    private let screenManager: ScreenManager
    private let layoutEngine: LayoutEngine
    private let fileManager: FileManager
    private let supportDirectoryURL: URL
    private var stacks: [String: WindowStack]

    init(
        windowController: WindowController,
        screenManager: ScreenManager = ScreenManager(),
        layoutEngine: LayoutEngine = LayoutEngine(),
        fileManager: FileManager = .default
    ) {
        self.windowController = windowController
        self.screenManager = screenManager
        self.layoutEngine = layoutEngine
        self.fileManager = fileManager
        self.supportDirectoryURL = StackManager.resolveSupportDirectory(fileManager: fileManager)
        self.stacks = [:]
        load()
    }

    func listStacks() -> [WindowStack] {
        stacks.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func stack(named name: String) -> WindowStack? {
        stacks[name]
    }

    @discardableResult
    func createStack(name: String, position: TilePosition, windows bundleIds: [String], displayIndex: Int? = nil) throws -> WindowStack {
        let frame = layoutEngine.frame(for: position, in: screenManager.visibleFrameInScreenCoordinates(displayIndex: displayIndex))
        return try createStack(name: name, frame: frame, windows: bundleIds, activeIndex: 0)
    }

    @discardableResult
    func createStack(name: String, frame: CGRect, windows bundleIds: [String], activeIndex: Int = 0) throws -> WindowStack {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw StackManagerError.invalidName
        }
        guard !bundleIds.isEmpty else {
            throw StackManagerError.emptyStackWindows
        }
        guard stacks[normalizedName] == nil else {
            throw StackManagerError.stackExists(normalizedName)
        }

        var bundleOccurrences: [String: Int] = [:]
        var identities: [WindowIdentity] = []
        let contentFrame = stackContentFrame(from: frame)

        for bundleId in bundleIds {
            let index = bundleOccurrences[bundleId, default: 0]
            bundleOccurrences[bundleId] = index + 1

            let identity = (try? windowController.windowIdentity(bundleId: bundleId, windowIndex: index))
                ?? WindowIdentity(bundleId: bundleId, title: "", windowNumber: nil)
            identities.append(identity)
            try setWindowFrame(identity: identity, fallbackWindowIndex: index, frame: contentFrame)
        }

        let safeActive = min(max(activeIndex, 0), identities.count - 1)
        let activeOccurrence = occurrenceIndex(for: safeActive, in: identities)
        try raiseWindow(identity: identities[safeActive], fallbackWindowIndex: activeOccurrence)

        let stack = WindowStack(
            name: normalizedName,
            frame: RectData(frame),
            windows: identities,
            activeIndex: safeActive,
            createdAt: Date()
        )
        stacks[normalizedName] = stack
        try save()
        return stack
    }

    @discardableResult
    func putWindowInStack(name: String, frame: CGRect, bundleId: String) throws -> WindowStack {
        let identity = (try? windowController.windowIdentity(bundleId: bundleId, windowIndex: 0))
            ?? WindowIdentity(bundleId: bundleId, title: "", windowNumber: nil)
        return try putWindowInStack(name: name, frame: frame, window: identity)
    }

    @discardableResult
    func putWindowInStack(name: String, frame: CGRect, window: WindowIdentity) throws -> WindowStack {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw StackManagerError.invalidName
        }

        // 跨堆栈去重：从其他堆栈中移除该窗口
        if let windowNumber = window.windowNumber {
            for (stackName, var stack) in stacks where stackName != normalizedName {
                if let idx = stack.windows.firstIndex(where: { $0.windowNumber == windowNumber }) {
                    stack.windows.remove(at: idx)
                    if stack.windows.isEmpty {
                        stacks.removeValue(forKey: stackName)
                    } else {
                        stack.activeIndex = min(stack.activeIndex, stack.windows.count - 1)
                        stacks[stackName] = stack
                    }
                }
            }
        }

        if let existing = stacks[normalizedName] {
            var windows = existing.windows

            // 同堆栈去重：优先使用 windowNumber
            if let newNumber = window.windowNumber {
                if let existingIndex = windows.firstIndex(where: { $0.windowNumber == newNumber }) {
                    windows[existingIndex] = window
                    return try rebuildStack(
                        name: normalizedName,
                        frame: frame,
                        windows: windows,
                        activeIndex: existingIndex
                    )
                }
            }

            windows.append(window)
            return try rebuildStack(
                name: normalizedName,
                frame: frame,
                windows: windows,
                activeIndex: windows.count - 1
            )
        }

        return try rebuildStack(
            name: normalizedName,
            frame: frame,
            windows: [window],
            activeIndex: 0
        )
    }

    func switchStack(name: String, index: Int) throws {
        guard var stack = stacks[name] else {
            throw StackManagerError.stackMissing(name)
        }
        guard index >= 0, index < stack.windows.count else {
            throw StackManagerError.invalidActiveIndex
        }

        let previousIndex = stack.activeIndex
        if previousIndex == index {
            return
        }

        let contentFrame = stackContentFrame(from: stack.frame.cgRect)
        let nextOccurrence = occurrenceIndex(for: index, in: stack.windows)

        // 确保目标窗口在正确的位置和大小
        try setWindowFrame(identity: stack.windows[index], fallbackWindowIndex: nextOccurrence, frame: contentFrame)

        // 直接置顶目标窗口，不最小化其他窗口
        try raiseWindow(identity: stack.windows[index], fallbackWindowIndex: nextOccurrence)

        stack.activeIndex = index
        stacks[name] = stack
        try save()
    }

    func deleteStack(name: String) throws {
        guard stacks[name] != nil else {
            throw StackManagerError.stackMissing(name)
        }
        stacks.removeValue(forKey: name)
        try save()
    }

    func clearAllStacks() throws {
        stacks.removeAll()
        try save()
    }

    func snapshotLayoutStacks() -> [LayoutStack] {
        let liveWindows = windowController.listWindows(onScreenOnly: false)
        let grouped = Dictionary(grouping: liveWindows) { $0.bundleId }

        return listStacks().map { stack in
            var occurrences: [String: Int] = [:]
            let mappedWindows = stack.windows.map { identity -> LayoutWindow in
                let idx = occurrences[identity.bundleId, default: 0]
                occurrences[identity.bundleId] = idx + 1
                let liveWindow: WindowInfo? = {
                    if let number = identity.windowNumber {
                        return liveWindows.first(where: { $0.windowNumber == number })
                    }
                    return grouped[identity.bundleId]?[safe: idx]
                }()
                let iconPath = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identity.bundleId)?.path
                return LayoutWindow(
                    bundleId: identity.bundleId,
                    appName: liveWindow?.appName ?? identity.bundleId,
                    title: liveWindow?.title ?? identity.title,
                    windowNumber: liveWindow?.windowNumber,
                    frame: liveWindow?.frame ?? stack.frame,
                    iconPath: iconPath
                )
            }

            return LayoutStack(
                name: stack.name,
                frame: stack.frame,
                windows: mappedWindows,
                activeIndex: stack.activeIndex
            )
        }
    }

    private func occurrenceIndex(for targetIndex: Int, in windows: [WindowIdentity]) -> Int {
        guard targetIndex > 0 else { return 0 }
        let targetBundle = windows[targetIndex].bundleId
        return windows[..<targetIndex].filter { $0.bundleId == targetBundle }.count
    }

    private func rebuildStack(name: String, frame: CGRect, windows: [WindowIdentity], activeIndex: Int) throws -> WindowStack {
        guard !windows.isEmpty else {
            throw StackManagerError.emptyStackWindows
        }

        let contentFrame = stackContentFrame(from: frame)
        var bundleOccurrences: [String: Int] = [:]

        for identity in windows {
            let index = bundleOccurrences[identity.bundleId, default: 0]
            bundleOccurrences[identity.bundleId] = index + 1
            try setWindowFrame(identity: identity, fallbackWindowIndex: index, frame: contentFrame)
        }

        let safeActive = min(max(activeIndex, 0), windows.count - 1)
        let activeOccurrence = occurrenceIndex(for: safeActive, in: windows)
        try raiseWindow(identity: windows[safeActive], fallbackWindowIndex: activeOccurrence)

        let updated = WindowStack(
            name: name,
            frame: RectData(frame),
            windows: windows,
            activeIndex: safeActive,
            createdAt: Date()
        )
        stacks[name] = updated
        try save()
        return updated
    }

    private func setWindowFrame(identity: WindowIdentity, fallbackWindowIndex: Int, frame: CGRect) throws {
        if let windowNumber = identity.windowNumber {
            try windowController.setWindowFrame(bundleId: identity.bundleId, windowNumber: windowNumber, frame: frame)
        } else {
            try windowController.setWindowFrame(bundleId: identity.bundleId, windowIndex: fallbackWindowIndex, frame: frame)
        }
    }

    private func raiseWindow(identity: WindowIdentity, fallbackWindowIndex: Int) throws {
        if let windowNumber = identity.windowNumber {
            try windowController.raiseWindow(bundleId: identity.bundleId, windowNumber: windowNumber)
        } else {
            try windowController.raiseWindow(bundleId: identity.bundleId, windowIndex: fallbackWindowIndex)
        }
    }

    private func setWindowMinimized(identity: WindowIdentity, fallbackWindowIndex: Int, minimized: Bool) throws {
        if let windowNumber = identity.windowNumber {
            try windowController.setWindowMinimized(bundleId: identity.bundleId, windowNumber: windowNumber, minimized: minimized)
        } else {
            try windowController.setWindowMinimized(bundleId: identity.bundleId, windowIndex: fallbackWindowIndex, minimized: minimized)
        }
    }

    private func stackContentFrame(from stackFrame: CGRect) -> CGRect {
        // AX API 坐标系：y=0 在屏幕顶部，y 向下增长
        // 标签栏在堆栈区域顶部，窗口内容在标签栏下方
        // 所以窗口 y 起点需要向下偏移标签栏高度
        let contentHeight = max(80.0, stackFrame.height - Self.desktopTabBarHeight)
        return CGRect(
            x: stackFrame.minX,
            y: stackFrame.minY + Self.desktopTabBarHeight,
            width: stackFrame.width,
            height: contentHeight
        )
    }

    private func load() {
        guard let data = try? Data(contentsOf: stacksURL) else {
            stacks = [:]
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([String: WindowStack].self, from: data) {
            stacks = loaded
        } else {
            stacks = [:]
        }
    }

    private func save() throws {
        try ensureSupportDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(stacks)
        try data.write(to: stacksURL, options: .atomic)
    }

    private func ensureSupportDirectory() throws {
        try fileManager.createDirectory(
            at: supportDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    private var stacksURL: URL {
        supportDirectoryURL.appendingPathComponent("stacks.json", isDirectory: false)
    }

    private static func resolveSupportDirectory(fileManager: FileManager) -> URL {
        if let custom = ProcessInfo.processInfo.environment["WINDOW_MANAGER_LAYOUTS_DIR"] {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }

        let tempFallback = URL(fileURLWithPath: "/tmp/winctlmanager-layouts", isDirectory: true)
        if canCreateDirectory(at: tempFallback, fileManager: fileManager) {
            return tempFallback
        }

        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".winctlmanager", isDirectory: true)
    }

    private static func canCreateDirectory(at url: URL, fileManager: FileManager) -> Bool {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
