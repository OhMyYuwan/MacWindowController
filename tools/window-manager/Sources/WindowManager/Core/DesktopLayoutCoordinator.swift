import AppKit
import Foundation

final class DesktopLayoutCoordinator {
    private let windowController: WindowController
    private let stackManager: StackManager
    private let store: DesktopLayoutStore
    private let screenManager: ScreenManager
    private let browserRestorer: BrowserPageRestorer
    private weak var partitionState: DesktopPartitionState?

    init(
        windowController: WindowController,
        stackManager: StackManager,
        store: DesktopLayoutStore,
        screenManager: ScreenManager = ScreenManager(),
        browserRestorer: BrowserPageRestorer = BrowserPageRestorer(),
        partitionState: DesktopPartitionState? = nil
    ) {
        self.windowController = windowController
        self.stackManager = stackManager
        self.store = store
        self.screenManager = screenManager
        self.browserRestorer = browserRestorer
        self.partitionState = partitionState
    }

    @MainActor
    @discardableResult
    func saveCurrentDesktop(name: String, description: String) throws -> DesktopLayout {
        let allWindows = windowController.listWindows(onScreenOnly: true)
        let preferredDisplay = screenManager.preferredDisplaySnapshot(for: allWindows)
        let assignments = partitionState?.zoneAssignmentsByWindowNumber ?? [:]

        let windows = allWindows.map { window in
            let browserPage = browserRestorer.capturedPage(for: window.bundleId, windowTitle: window.title)
            return LayoutWindow(
                bundleId: window.bundleId,
                appName: window.appName,
                title: window.title,
                windowNumber: window.windowNumber,
                frame: window.frame,
                iconPath: NSWorkspace.shared.urlForApplication(withBundleIdentifier: window.bundleId)?.path,
                zoneName: assignments[window.windowNumber],
                browserURL: browserPage?.url,
                browserKind: browserPage?.kind
            )
        }

        let stacks = stackManager.snapshotLayoutStacks().map { stack in
            var updated = stack
            updated.zoneName = stack.name  // Stack name typically matches zone name
            return updated
        }

        let partition = partitionState.map { DesktopPartitionSnapshot(from: $0) }

        let layout = DesktopLayout(
            schemaVersion: 3,
            name: name,
            description: description,
            createdAt: Date(),
            windows: windows,
            stacks: stacks,
            partition: partition,
            preferredDisplay: preferredDisplay
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
    func wakeDesktop(name: String, targetDisplayId: UInt32?) throws {
        let layout = try loadDesktop(name: name)
        try applyLayout(layout, targetDisplayId: targetDisplayId)
    }

    @MainActor
    func applyLayout(_ layout: DesktopLayout, targetDisplayId: UInt32? = nil) throws {
        let targetDisplay = screenManager.displaySnapshot(id: targetDisplayId ?? layout.preferredDisplay?.id)
        let sourceDisplay = layout.preferredDisplay

        // Restore partition state if available (schema v2)
        if let partition = layout.partition {
            let restoredState = partition.toState()
            partitionState?.mergeMode = restoredState.mergeMode
            partitionState?.splitX = restoredState.splitX
            partitionState?.splitY = restoredState.splitY
            partitionState?.stackThreshold = restoredState.stackThreshold
        }

        let browserWindows = layout.windows.filter { ($0.browserURL?.isEmpty == false) }
        for window in browserWindows {
            if let url = window.browserURL {
                browserRestorer.restorePage(bundleId: window.bundleId, url: url)
            }
        }

        var launchSet = Set(layout.windows.map(\.bundleId))
        for stack in layout.stacks {
            stack.windows.forEach { launchSet.insert($0.bundleId) }
        }
        for bundleId in launchSet {
            guard bundleId != WindowInfo.unknownBundleId else { continue }
            launchIfNeeded(bundleId: bundleId)
        }

        usleep(browserWindows.isEmpty ? 300_000 : 900_000)

        // If partition snapshot exists, use zone-based restoration
        if let partition = layout.partition {
            try applyZoneBasedLayout(layout, partition: partition, sourceDisplay: sourceDisplay, targetDisplay: targetDisplay)
        } else {
            // Legacy: restore by absolute frames
            try applyLegacyLayout(layout, sourceDisplay: sourceDisplay, targetDisplay: targetDisplay)
        }
    }

    @MainActor
    private func applyZoneBasedLayout(
        _ layout: DesktopLayout,
        partition: DesktopPartitionSnapshot,
        sourceDisplay: LayoutDisplaySnapshot?,
        targetDisplay: LayoutDisplaySnapshot?
    ) throws {
        try stackManager.clearAllStacks()
        partitionState?.zoneAssignmentsByWindowNumber.removeAll()

        let currentWindowsByBundle = Dictionary(
            grouping: windowController.listWindows(onScreenOnly: true).filter(\.isControllable),
            by: \.bundleId
        ).mapValues { windows in
            windows.sorted {
                if $0.windowNumber != $1.windowNumber {
                    return $0.windowNumber < $1.windowNumber
                }
                if $0.title != $1.title {
                    return $0.title < $1.title
                }
                return $0.frame.cgRect.minX < $1.frame.cgRect.minX
            }
        }
        var usedWindowNumbers = Set<Int>()

        // Group saved windows by zone and bind the restored runtime windows back
        // to the partition model. Window numbers are session-local, so the saved
        // windowNumber cannot be reused directly after browser/app restore.
        let windowsByZone = Dictionary(grouping: layout.windows) { $0.zoneName ?? "unassigned" }

        for (zoneName, zoneWindows) in windowsByZone where zoneName != "unassigned" {
            var occurrences: [String: Int] = [:]
            for savedWindow in zoneWindows {
                guard savedWindow.bundleId != WindowInfo.unknownBundleId else { continue }
                let index = occurrences[savedWindow.bundleId, default: 0]
                occurrences[savedWindow.bundleId] = index + 1

                let candidates = currentWindowsByBundle[savedWindow.bundleId] ?? []
                let titleMatch = candidates.first { candidate in
                    !usedWindowNumbers.contains(candidate.windowNumber)
                        && !savedWindow.title.isEmpty
                        && candidate.title == savedWindow.title
                }
                let occurrenceMatch = candidates.dropFirst(index).first {
                    !usedWindowNumbers.contains($0.windowNumber)
                }
                guard let currentWindow = titleMatch ?? occurrenceMatch else { continue }

                usedWindowNumbers.insert(currentWindow.windowNumber)
                partitionState?.zoneAssignmentsByWindowNumber[currentWindow.windowNumber] = zoneName
                try? windowController.setWindowMinimized(
                    bundleId: currentWindow.bundleId,
                    windowNumber: currentWindow.windowNumber,
                    minimized: false
                )
                try? windowController.setWindowFrame(
                    bundleId: currentWindow.bundleId,
                    windowNumber: currentWindow.windowNumber,
                    frame: mapRect(savedWindow.frame.cgRect, sourceDisplay: sourceDisplay, targetDisplay: targetDisplay)
                )
            }
        }

        // Restore stacks
        for stack in layout.stacks {
            let bundleIds = stack.windows.map(\.bundleId)
            _ = try stackManager.createStack(
                name: stack.name,
                frame: mapRect(stack.frame.cgRect, sourceDisplay: sourceDisplay, targetDisplay: targetDisplay),
                windows: bundleIds,
                activeIndex: stack.activeIndex
            )
        }
    }

    @MainActor
    private func applyLegacyLayout(
        _ layout: DesktopLayout,
        sourceDisplay: LayoutDisplaySnapshot?,
        targetDisplay: LayoutDisplaySnapshot?
    ) throws {
        var occurrences: [String: Int] = [:]
        for window in layout.windows {
            guard window.bundleId != WindowInfo.unknownBundleId else { continue }
            let index = occurrences[window.bundleId, default: 0]
            occurrences[window.bundleId] = index + 1
            try? windowController.setWindowMinimized(bundleId: window.bundleId, windowIndex: index, minimized: false)
            try windowController.setWindowFrame(
                bundleId: window.bundleId,
                windowIndex: index,
                frame: mapRect(window.frame.cgRect, sourceDisplay: sourceDisplay, targetDisplay: targetDisplay)
            )
        }

        try stackManager.clearAllStacks()
        for stack in layout.stacks {
            let bundleIds = stack.windows.map(\.bundleId)
            _ = try stackManager.createStack(
                name: stack.name,
                frame: mapRect(stack.frame.cgRect, sourceDisplay: sourceDisplay, targetDisplay: targetDisplay),
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

    private func mapRect(
        _ rect: CGRect,
        sourceDisplay: LayoutDisplaySnapshot?,
        targetDisplay: LayoutDisplaySnapshot?
    ) -> CGRect {
        guard let source = sourceDisplay?.visibleFrame.cgRect,
              let target = targetDisplay?.visibleFrame.cgRect,
              source.width > 1,
              source.height > 1 else {
            return rect
        }

        let relativeX = (rect.minX - source.minX) / source.width
        let relativeY = (rect.minY - source.minY) / source.height
        let relativeW = rect.width / source.width
        let relativeH = rect.height / source.height
        return CGRect(
            x: target.minX + relativeX * target.width,
            y: target.minY + relativeY * target.height,
            width: max(80, relativeW * target.width),
            height: max(80, relativeH * target.height)
        )
    }
}
