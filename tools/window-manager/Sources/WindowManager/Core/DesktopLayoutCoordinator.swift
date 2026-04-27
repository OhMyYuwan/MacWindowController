import AppKit
import Foundation

final class DesktopLayoutCoordinator {
    private let windowController: WindowController
    private let stackManager: StackManager
    private let store: DesktopLayoutStore
    private weak var partitionState: DesktopPartitionState?

    init(
        windowController: WindowController,
        stackManager: StackManager,
        store: DesktopLayoutStore,
        partitionState: DesktopPartitionState? = nil
    ) {
        self.windowController = windowController
        self.stackManager = stackManager
        self.store = store
        self.partitionState = partitionState
    }

    @MainActor
    @discardableResult
    func saveCurrentDesktop(name: String, description: String) throws -> DesktopLayout {
        let allWindows = windowController.listWindows(onScreenOnly: true)
        let assignments = partitionState?.zoneAssignmentsByWindowNumber ?? [:]

        let windows = allWindows.map { window in
            LayoutWindow(
                bundleId: window.bundleId,
                appName: window.appName,
                title: window.title,
                windowNumber: window.windowNumber,
                frame: window.frame,
                iconPath: NSWorkspace.shared.urlForApplication(withBundleIdentifier: window.bundleId)?.path,
                zoneName: assignments[window.windowNumber]
            )
        }

        let stacks = stackManager.snapshotLayoutStacks().map { stack in
            var updated = stack
            updated.zoneName = stack.name  // Stack name typically matches zone name
            return updated
        }

        let partition = partitionState.map { DesktopPartitionSnapshot(from: $0) }

        let layout = DesktopLayout(
            schemaVersion: 2,
            name: name,
            description: description,
            createdAt: Date(),
            windows: windows,
            stacks: stacks,
            partition: partition
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

    @MainActor
    func applyDesktop(name: String) throws {
        let layout = try loadDesktop(name: name)
        try applyLayout(layout)
    }

    @MainActor
    func applyLayout(_ layout: DesktopLayout) throws {
        // Restore partition state if available (schema v2)
        if let partition = layout.partition {
            let restoredState = partition.toState()
            partitionState?.mergeMode = restoredState.mergeMode
            partitionState?.splitX = restoredState.splitX
            partitionState?.splitY = restoredState.splitY
            partitionState?.stackThreshold = restoredState.stackThreshold
        }

        var launchSet = Set(layout.windows.map(\.bundleId))
        for stack in layout.stacks {
            stack.windows.forEach { launchSet.insert($0.bundleId) }
        }
        for bundleId in launchSet {
            launchIfNeeded(bundleId: bundleId)
        }

        // If partition snapshot exists, use zone-based restoration
        if let partition = layout.partition {
            try applyZoneBasedLayout(layout, partition: partition)
        } else {
            // Legacy: restore by absolute frames
            try applyLegacyLayout(layout)
        }
    }

    @MainActor
    private func applyZoneBasedLayout(_ layout: DesktopLayout, partition: DesktopPartitionSnapshot) throws {
        try stackManager.clearAllStacks()
        partitionState?.zoneAssignmentsByWindowNumber.removeAll()

        // Group windows by zone
        let windowsByZone = Dictionary(grouping: layout.windows) { $0.zoneName ?? "unassigned" }

        for (zoneName, zoneWindows) in windowsByZone where zoneName != "unassigned" {
            var occurrences: [String: Int] = [:]
            for window in zoneWindows {
                let index = occurrences[window.bundleId, default: 0]
                occurrences[window.bundleId] = index + 1
                try? windowController.setWindowMinimized(bundleId: window.bundleId, windowIndex: index, minimized: false)
            }

            // Zone behavior will be applied by the runtime's forced-zone logic after windows are positioned
        }

        // Restore stacks
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

    @MainActor
    private func applyLegacyLayout(_ layout: DesktopLayout) throws {
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
