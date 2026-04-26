import AppKit
import Foundation

final class DesktopLayoutCoordinator {
    private let windowController: WindowController
    private let stackManager: StackManager
    private let store: DesktopLayoutStore

    init(
        windowController: WindowController,
        stackManager: StackManager,
        store: DesktopLayoutStore
    ) {
        self.windowController = windowController
        self.stackManager = stackManager
        self.store = store
    }

    @discardableResult
    func saveCurrentDesktop(name: String, description: String) throws -> DesktopLayout {
        let windows = windowController.listWindows(onScreenOnly: true).map { window in
            LayoutWindow(
                bundleId: window.bundleId,
                appName: window.appName,
                title: window.title,
                windowNumber: window.windowNumber,
                frame: window.frame,
                iconPath: NSWorkspace.shared.urlForApplication(withBundleIdentifier: window.bundleId)?.path
            )
        }
        let stacks = stackManager.snapshotLayoutStacks()
        let layout = DesktopLayout(
            name: name,
            description: description,
            createdAt: Date(),
            windows: windows,
            stacks: stacks
        )
        try store.save(layout)
        return layout
    }

    func listDesktops() -> [DesktopLayout] {
        store.list()
    }

    func loadDesktop(name: String) throws -> DesktopLayout {
        try store.load(name: name)
    }

    func deleteDesktop(name: String) throws {
        try store.delete(name: name)
    }

    func exportDesktop(name: String, to outputURL: URL) throws {
        try store.exportLayout(name: name, to: outputURL)
    }

    @discardableResult
    func importDesktop(from inputURL: URL) throws -> DesktopLayout {
        try store.importLayout(from: inputURL)
    }

    func applyDesktop(name: String) throws {
        let layout = try loadDesktop(name: name)
        try applyLayout(layout)
    }

    func applyLayout(_ layout: DesktopLayout) throws {
        var launchSet = Set(layout.windows.map(\.bundleId))
        for stack in layout.stacks {
            stack.windows.forEach { launchSet.insert($0.bundleId) }
        }
        for bundleId in launchSet {
            launchIfNeeded(bundleId: bundleId)
        }

        var occurrences: [String: Int] = [:]
        for window in layout.windows {
            let index = occurrences[window.bundleId, default: 0]
            occurrences[window.bundleId] = index + 1
            try? windowController.setWindowMinimized(bundleId: window.bundleId, windowIndex: index, minimized: false)
            try windowController.setWindowFrame(
                bundleId: window.bundleId,
                windowIndex: index,
                frame: window.frame.cgRect
            )
        }

        try stackManager.clearAllStacks()
        for stack in layout.stacks {
            let bundleIds = stack.windows.map(\.bundleId)
            _ = try stackManager.createStack(
                name: stack.name,
                frame: stack.frame.cgRect,
                windows: bundleIds,
                activeIndex: stack.activeIndex
            )
        }
    }

    private func launchIfNeeded(bundleId: String) {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty {
            return
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = false
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
            if let error {
                NSLog("desktop-layout: launch failed for %@: %@", bundleId, error.localizedDescription)
            }
        }

        // Give new applications a moment to create windows.
        usleep(300_000)
    }
}
