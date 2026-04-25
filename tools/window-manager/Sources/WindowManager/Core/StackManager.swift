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
    private let windowController: WindowController
    private let screenManager: ScreenManager
    private let layoutEngine: LayoutEngine
    private let fileManager: FileManager
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
        self.stacks = [:]
        load()
    }

    func listStacks() -> [WindowStack] {
        stacks.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @discardableResult
    func createStack(name: String, position: TilePosition, windows bundleIds: [String], displayIndex: Int? = nil) throws -> WindowStack {
        let frame = layoutEngine.frame(for: position, in: screenManager.visibleFrame(displayIndex: displayIndex))
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

        for bundleId in bundleIds {
            let index = bundleOccurrences[bundleId, default: 0]
            bundleOccurrences[bundleId] = index + 1

            try windowController.setWindowFrame(bundleId: bundleId, windowIndex: index, frame: frame)
            try windowController.setWindowMinimized(bundleId: bundleId, windowIndex: index, minimized: true)

            let title = (try? windowController.windowTitle(bundleId: bundleId, windowIndex: index)) ?? ""
            identities.append(
                WindowIdentity(
                    bundleId: bundleId,
                    title: title,
                    windowNumber: nil
                )
            )
        }

        let safeActive = min(max(activeIndex, 0), identities.count - 1)
        let activeOccurrence = occurrenceIndex(for: safeActive, in: identities)
        try windowController.setWindowMinimized(
            bundleId: identities[safeActive].bundleId,
            windowIndex: activeOccurrence,
            minimized: false
        )

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

        let previousOccurrence = occurrenceIndex(for: previousIndex, in: stack.windows)
        let nextOccurrence = occurrenceIndex(for: index, in: stack.windows)

        try windowController.setWindowMinimized(
            bundleId: stack.windows[previousIndex].bundleId,
            windowIndex: previousOccurrence,
            minimized: true
        )
        try windowController.setWindowMinimized(
            bundleId: stack.windows[index].bundleId,
            windowIndex: nextOccurrence,
            minimized: false
        )
        try windowController.activateApp(bundleId: stack.windows[index].bundleId)

        stack.activeIndex = index
        stacks[name] = stack
        try save()
    }

    func deleteStack(name: String) throws {
        guard let stack = stacks[name] else {
            throw StackManagerError.stackMissing(name)
        }

        for (idx, identity) in stack.windows.enumerated() {
            let occurrence = occurrenceIndex(for: idx, in: stack.windows)
            try? windowController.setWindowMinimized(
                bundleId: identity.bundleId,
                windowIndex: occurrence,
                minimized: false
            )
        }

        stacks.removeValue(forKey: name)
        try save()
    }

    func clearAllStacks() throws {
        for stack in stacks.values {
            for (idx, identity) in stack.windows.enumerated() {
                let occurrence = occurrenceIndex(for: idx, in: stack.windows)
                try? windowController.setWindowMinimized(
                    bundleId: identity.bundleId,
                    windowIndex: occurrence,
                    minimized: false
                )
            }
        }
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
                let liveWindow = grouped[identity.bundleId]?[safe: idx]
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

    private var supportDirectoryURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("WinCtlManager", isDirectory: true)
    }

    private var stacksURL: URL {
        supportDirectoryURL.appendingPathComponent("stacks.json", isDirectory: false)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
