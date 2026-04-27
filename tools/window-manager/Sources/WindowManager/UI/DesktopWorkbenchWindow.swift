import AppKit
import Foundation

@MainActor
enum DesktopMergeMode: Int, CaseIterable {
    case grid = 0
    case leftColumn
    case rightColumn
    case topRow
    case bottomRow
    case leftRight
    case topBottom
    case threeColumns
    case threeRows

    var title: String {
        switch self {
        case .grid: return "四分"
        case .leftColumn: return "左大右二"
        case .rightColumn: return "左二右大"
        case .topRow: return "上大下二"
        case .bottomRow: return "上二下大"
        case .leftRight: return "左右分屏"
        case .topBottom: return "上下分屏"
        case .threeColumns: return "三列"
        case .threeRows: return "三行"
        }
    }
}

@MainActor
private enum WorkbenchSection: Int, CaseIterable {
    case layouts
    case stacks
    case settings

    var title: String {
        switch self {
        case .layouts: return "布局"
        case .stacks: return "堆叠"
        case .settings: return "设置"
        }
    }

    var symbolName: String {
        switch self {
        case .layouts: return "square.split.2x2.fill"
        case .stacks: return "square.3.layers.3d.top.filled"
        case .settings: return "gearshape.fill"
        }
    }
}

@MainActor
enum DesktopWorkbenchLauncher {
    private static var runtimeHolder: DesktopWorkbenchRuntime?

    static func open(
        windowController: WindowController,
        stackManager: StackManager,
        layoutStore: DesktopLayoutStore,
        screenManager: ScreenManager,
        focusedLayoutName: String? = nil
    ) {
        let app = NSApplication.shared
        let runtime = DesktopWorkbenchRuntime(
            windowController: windowController,
            stackManager: stackManager,
            layoutStore: layoutStore,
            screenManager: screenManager,
            focusedLayoutName: focusedLayoutName
        )
        runtimeHolder = runtime

        app.setActivationPolicy(.regular)
        app.delegate = runtime
        app.activate(ignoringOtherApps: true)
        app.run()

        runtimeHolder = nil
    }
}

@MainActor
private final class DesktopWorkbenchRuntime: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let leftBucketName = "left"
    private struct ShortcutKeyOption {
        let title: String
        let keyCode: UInt16
    }

    private let windowController: WindowController
    private let stackManager: StackManager
    private let layoutCoordinator: DesktopLayoutCoordinator
    private let layoutStore: DesktopLayoutStore
    private let screenManager: ScreenManager
    private let partitionState: DesktopPartitionState
    private lazy var zoneManager = DesktopZoneManager(
        windowController: windowController,
        screenManager: screenManager,
        stackManager: stackManager,
        partitionState: partitionState
    )

    private var focusedLayoutName: String?
    private var appConfig = DesktopConfig.load()
    private var mergeMode: DesktopMergeMode {
        get { partitionState.mergeMode }
        set { partitionState.mergeMode = newValue }
    }
    private var leftBucketEnabled = true
    private var autoScanEnabled = false
    private var selectedLayoutName: String?
    private var lastExternalWindowIdentity: WindowIdentity?

    private var window: NSWindow?
    private var desktopView: DesktopContainerView?
    private var desktopHandleOverlayView: DesktopHandleOverlayView?
    private var desktopOverlayView: DesktopContainerView?
    private var layoutNameField: NSTextField?
    private var appBundleIdField: NSTextField?
    private var chromeWindowCountField: NSTextField?
    private var mergeControl: NSSegmentedControl?
    private var statusLabel: NSTextField?
    private var shortcutHintLabel: NSTextField?
    private var noteScrollView: NSScrollView?
    private var noteStackView: NSStackView?
    private var desktopOverlayToggleButton: NSButton?
    private var stackPanels: [String: NSPanel] = [:]
    private var stackPanelTabStacks: [String: NSStackView] = [:]
    private var refreshTimer: Timer?
    private var keyboardMonitors: [Any] = []
    private var appActivationObserver: NSObjectProtocol?
    private var layoutOverlayPanel: NSPanel?
    private var layoutOverlayView: LayoutModeGridOverlayView?
    private var isShowingLayoutOverlay = false
    private var settingsWindow: NSWindow?
    private var desktopPartitionPanel: NSPanel?
    private var shortcutKeyPopup: NSPopUpButton?
    private var shortcutCommandToggle: NSButton?
    private var shortcutOptionToggle: NSButton?
    private var shortcutShiftToggle: NSButton?
    private var shortcutControlToggle: NSButton?
    private var shortcutCurrentLabel: NSTextField?
    private var splitApplyWorkItem: DispatchWorkItem?
    private var partitionModelInitialized = false
    private var lastWindowFramesByNumber: [Int: CGRect] = [:]
    private var isProgrammaticZoneTransfer = false
    private var desktopOverlayEditingEnabled = true
    private var isOptionDragTransferMode = false
    private var currentSection: WorkbenchSection = .layouts
    private var contentContainer: NSView?
    private var sidebarItems: [SidebarItemView] = []

    init(
        windowController: WindowController,
        stackManager: StackManager,
        layoutStore: DesktopLayoutStore,
        screenManager: ScreenManager,
        focusedLayoutName: String?
    ) {
        self.windowController = windowController
        self.stackManager = stackManager
        self.layoutStore = layoutStore
        self.screenManager = screenManager
        self.focusedLayoutName = focusedLayoutName

        let config = DesktopConfig.load()
        self.partitionState = DesktopPartitionState(
            mergeMode: .leftColumn,
            splitX: 0.5,
            splitY: 0.5,
            stackThreshold: config.stackThreshold
        )
        self.layoutCoordinator = DesktopLayoutCoordinator(
            windowController: windowController,
            stackManager: stackManager,
            store: layoutStore,
            partitionState: partitionState
        )
        self.appConfig = config
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 80, width: 1320, height: 900),
            styleMask: [.titled, .resizable, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WinCtlManager"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 1100, height: 760)
        window.backgroundColor = NSColor.windowBackgroundColor
        window.center()
        window.delegate = self
        self.window = window

        // Root split view: sidebar (220pt fixed) + content area
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = splitView

        let sidebar = makeSidebarView()
        splitView.addArrangedSubview(sidebar)
        let contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        self.contentContainer = contentContainer
        splitView.addArrangedSubview(contentContainer)

        // Sidebar fixed at 220 pt
        sidebar.widthAnchor.constraint(equalToConstant: 220).isActive = true
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        splitView.setPosition(220, ofDividerAt: 0)
        splitView.adjustSubviews()

        let mergeControl = NSSegmentedControl(
            labels: DesktopMergeMode.allCases.map(\.title),
            trackingMode: .selectOne,
            target: self,
            action: #selector(changeMergeMode(_:))
        )
        mergeControl.segmentStyle = .rounded
        mergeControl.selectedSegment = partitionState.mergeMode.rawValue
        self.mergeControl = mergeControl

        let desktopView = DesktopContainerView(displayFrame: screenManager.mainVisibleFrame())
        desktopView.translatesAutoresizingMaskIntoConstraints = false
        desktopView.onBucketTabSelected = { [weak self] index in
            self?.switchLeftBucket(to: index)
        }
        desktopView.onSplitChanged = { [weak self] x, y, isFinal in
            guard let self else { return }
            self.handleSplitChanged(x: x, y: y, isFinal: isFinal)
        }
        self.desktopView = desktopView
        installDesktopOverlayPanel()

        let statusLabel = NSTextField(labelWithString: "就绪")
        statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        self.statusLabel = statusLabel

        let nameField = NSTextField(string: focusedLayoutName ?? "workspace_\(dateSuffix())")
        nameField.placeholderString = "布局名称"
        self.layoutNameField = nameField

        let noteStack = NSStackView()
        noteStack.orientation = .horizontal
        noteStack.spacing = 10
        noteStack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        noteStack.alignment = .top
        noteStack.frame = NSRect(x: 0, y: 0, width: 900, height: 204)
        self.noteStackView = noteStack

        let noteScroll = NSScrollView()
        noteScroll.drawsBackground = false
        noteScroll.hasHorizontalScroller = true
        noteScroll.hasVerticalScroller = false
        noteScroll.autohidesScrollers = true
        noteScroll.documentView = noteStack
        noteScroll.translatesAutoresizingMaskIntoConstraints = false
        noteScroll.heightAnchor.constraint(equalToConstant: 220).isActive = true
        self.noteScrollView = noteScroll

        switchSection(.layouts, animated: false)

        window.makeKeyAndOrderFront(nil)

        installKeyboardShortcuts()
        updateShortcutHintLabel()
        startRefreshTimer()
        startPanelZOrderMonitoring()
        partitionModelInitialized = !stackManager.listStacks().isEmpty
        refreshWorkbench()
        if let focusedLayoutName {
            selectedLayoutName = focusedLayoutName
        }
    }

    func windowWillClose(_ notification: Notification) {
        for monitor in keyboardMonitors {
            NSEvent.removeMonitor(monitor)
        }
        keyboardMonitors.removeAll()
        if let appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver)
        }
        refreshTimer?.invalidate()
        mousePollingTimer?.invalidate()
        splitApplyWorkItem?.cancel()
        layoutOverlayPanel?.close()
        desktopPartitionPanel?.close()
        for panel in stackPanels.values { panel.close() }
        stackPanels.removeAll()
        NSApplication.shared.terminate(nil)
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refreshWorkbench()
            }
        }
    }

    private func startPanelZOrderMonitoring() {
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateAllPanelZOrder()
            }
        }
    }

    private func updateAllPanelZOrder() {
        let allStacks = stackManager.listStacks()

        for stack in allStacks {
            guard let panel = stackPanels[stack.name], !stack.windows.isEmpty else { continue }
            let safeIndex = stack.activeIndex < stack.windows.count ? stack.activeIndex : 0
            let activeWindow = stack.windows[safeIndex]

            // Tab bar should be at the same z-level as the active window in its zone.
            // Use the active window's windowNumber to find its CGWindow and order
            // the panel just above it.
            if let windowNumber = activeWindow.windowNumber {
                panel.order(.above, relativeTo: windowNumber)
            } else {
                panel.orderFront(nil)
            }
        }
    }

    private func installKeyboardShortcuts() {
        for monitor in keyboardMonitors {
            NSEvent.removeMonitor(monitor)
        }
        keyboardMonitors.removeAll()

        let keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
            if self.shortcutMatches(flags: flags, keyCode: event.keyCode) {
                if !event.isARepeat {
                    self.showLayoutModeOverlay()
                }
                return nil
            }

            let tileFlagsRequired = flags.contains(.command) && flags.contains(.option)
            guard tileFlagsRequired else { return event }
            switch event.keyCode {
            case 123:
                self.tileFrontmost(position: .left)
                return nil
            case 124:
                self.tileFrontmost(position: .right)
                return nil
            case 126:
                self.tileFrontmost(position: .top)
                return nil
            case 125:
                self.tileFrontmost(position: .bottom)
                return nil
            default:
                return event
            }
        }

        let keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == self.appConfig.layoutHUDShortcut.keyCode {
                self.hideLayoutModeOverlay()
                return nil
            }
            return event
        }

        let flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event.modifierFlags)
            return event
        }

        // Also need a global monitor so we get flag changes when other apps are active
        let flagsChangedGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event.modifierFlags)
        }

        keyboardMonitors = [keyDownMonitor, keyUpMonitor, flagsChangedMonitor, flagsChangedGlobalMonitor].compactMap { $0 }
    }

    private func handleFlagsChanged(_ modifierFlags: NSEvent.ModifierFlags) {
        let flags = modifierFlags.intersection([.command, .option, .shift, .control])
        if self.isShowingLayoutOverlay && !self.shortcutFlagsSatisfied(flags: flags) {
            self.hideLayoutModeOverlay()
        }

        // Command+Shift = zone transfer mode
        let transferHeld = flags.contains(.command) && flags.contains(.shift)
        if transferHeld != self.isOptionDragTransferMode {
            self.isOptionDragTransferMode = transferHeld
            self.desktopHandleOverlayView?.isZoneHighlightMode = transferHeld
            self.desktopHandleOverlayView?.needsDisplay = true
            if transferHeld {
                self.setStatus("按住 ⌘⇧ 拖动窗口可跨块转移", error: false)
            } else {
                self.desktopHandleOverlayView?.highlightedZoneName = nil
            }
        }
    }

    private func refreshWorkbench() {
        if let identity = windowController.frontmostWindowIdentity(ignoringCurrentProcess: true) {
            lastExternalWindowIdentity = identity
        }
        updateDesktopOverlayPanelFrame()
        let windows = windowController.listWindows(onScreenOnly: true)
        _ = stackManager.reconcileStacks(with: windows)

        if !partitionModelInitialized, !stackManager.listStacks().isEmpty {
            partitionModelInitialized = true
        }

        if partitionModelInitialized {
            applyWindowZoneTransfers(windows)

            // Strong enforcement: every window must fill its assigned zone unless
            // user is actively dragging with ⌘⇧ to transfer between zones.
            if !isOptionDragTransferMode {
                enforceZoneFrames(windows)
            }
        }

        let leftBucket = stackManager.stack(named: leftBucketName)
        desktopView?.update(
            windows: windows,
            leftBucket: leftBucket,
            mergeMode: mergeMode,
            leftBucketEnabled: leftBucketEnabled
        )
        desktopHandleOverlayView?.mergeMode = mergeMode
        desktopHandleOverlayView?.splitX = partitionState.splitX
        desktopHandleOverlayView?.splitY = partitionState.splitY
        desktopHandleOverlayView?.needsDisplay = true
        refreshAllStackPanels()
        reloadLayoutCards()
        updateLayoutModeOverlayHighlight()
    }

    private func installDesktopOverlayPanel() {
        let frame = screenManager.mainVisibleFrame()
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar  // Above all windows to ensure handles are clickable
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Start with ignoring events; will toggle based on mouse position
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hasShadow = false

        let handleOverlay = DesktopHandleOverlayView(frame: panel.contentView?.bounds ?? .zero)
        handleOverlay.autoresizingMask = [.width, .height]
        handleOverlay.mergeMode = mergeMode
        handleOverlay.splitX = partitionState.splitX
        handleOverlay.splitY = partitionState.splitY
        handleOverlay.onSplitChanged = { [weak self] x, y, isFinal in
            guard let self else { return }
            self.handleSplitChanged(x: x, y: y, isFinal: isFinal)
            self.desktopView?.applyExternalSplit(x: x, y: y)
        }

        let content = NSView(frame: panel.contentView?.bounds ?? .zero)
        content.autoresizingMask = [.width, .height]
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = content
        content.addSubview(handleOverlay)

        desktopHandleOverlayView = handleOverlay
        desktopPartitionPanel = panel
        panel.orderFrontRegardless()

        // Install global mouse monitor to detect when cursor enters divider zones
        installGlobalMouseMonitor()
    }

    private func installGlobalMouseMonitor() {
        // Global monitor: fires when events go to other apps (panel ignoring events)
        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.updatePanelEventMode()
        }
        if let globalMonitor {
            keyboardMonitors.append(globalMonitor)
        }

        // Local monitor: fires when events come to this app (panel receiving events)
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.updatePanelEventMode()
            return event
        }
        if let localMonitor {
            keyboardMonitors.append(localMonitor)
        }

        // High-frequency polling timer: ensures panel state is always in sync
        // with mouse position, even during fast movements that monitors might miss
        startMousePollingTimer()
    }

    private var mousePollingTimer: Timer?

    private func startMousePollingTimer() {
        mousePollingTimer?.invalidate()
        mousePollingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePanelEventMode()
            }
        }
    }

    private func updatePanelEventMode() {
        guard let overlay = desktopHandleOverlayView, let panel = desktopPartitionPanel else { return }

        let screenPoint = NSEvent.mouseLocation
        let windowPoint = overlay.window?.convertPoint(fromScreen: screenPoint) ?? .zero
        let viewPoint = overlay.convert(windowPoint, from: nil)

        overlay.updateHoverState(at: viewPoint)

        // Enable panel events when near any divider
        let shouldReceiveEvents = overlay.isNearDivider(at: viewPoint)
        if panel.ignoresMouseEvents == shouldReceiveEvents {
            panel.ignoresMouseEvents = !shouldReceiveEvents
        }
    }

    private func updateDesktopOverlayPanelFrame() {
        guard let panel = desktopPartitionPanel else { return }
        panel.setFrame(screenManager.mainVisibleFrame(), display: true)
    }

    @objc
    private func toggleDesktopOverlayEditing() {
        setDesktopOverlayEditing(enabled: !desktopOverlayEditingEnabled)
    }

    private func setDesktopOverlayEditing(enabled: Bool) {
        desktopOverlayEditingEnabled = enabled
        desktopOverlayToggleButton?.title = enabled ? "桌面分区柄：显示" : "桌面分区柄：隐藏"

        guard let panel = desktopPartitionPanel else { return }
        if enabled {
            panel.orderFrontRegardless()
            setStatus("已显示桌面分区柄（拖拽柄即可调整分区）", error: false)
        } else {
            panel.orderOut(nil)
            setStatus("已隐藏桌面分区柄", error: false)
        }
    }

    private func handleSplitChanged(x: CGFloat, y: CGFloat, isFinal: Bool) {
        desktopView?.applyExternalSplit(x: x, y: y)
        desktopHandleOverlayView?.splitX = x
        desktopHandleOverlayView?.splitY = y
        partitionState.updateSplits(x: x, y: y)

        splitApplyWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let windows = self.windowController.listWindows(onScreenOnly: true)
            try? self.zoneManager.applyForcedZones(windows: windows, mergeMode: self.mergeMode)
            self.refreshAllStackPanels()
        }
        splitApplyWorkItem = work

        if isFinal {
            DispatchQueue.main.async(execute: work)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: work)
        }
    }

    private func applyWindowZoneTransfers(_ windows: [WindowInfo]) {
        guard !isProgrammaticZoneTransfer else { return }
        guard isOptionDragTransferMode else { return }  // Only transfer when Command+Shift is held

        let visibleNumbers = Set(windows.map(\.windowNumber))
        partitionState.zoneAssignmentsByWindowNumber = partitionState.zoneAssignmentsByWindowNumber.filter { visibleNumbers.contains($0.key) }
        lastWindowFramesByNumber = lastWindowFramesByNumber.filter { visibleNumbers.contains($0.key) }

        let assignments = zoneManager.currentZoneAssignments(windows: windows, mergeMode: mergeMode)
        desktopHandleOverlayView?.activeZoneNames = Set(assignments.values)

        for window in windows {
            let number = window.windowNumber
            let frame = window.frame.cgRect
            let targetZone = assignments[number]

            if partitionState.zoneAssignmentsByWindowNumber[number] == nil {
                partitionState.zoneAssignmentsByWindowNumber[number] = targetZone
                lastWindowFramesByNumber[number] = frame
                continue
            }

            defer { lastWindowFramesByNumber[number] = frame }

            guard let previousFrame = lastWindowFramesByNumber[number] else { continue }
            let movedDistance = abs(previousFrame.minX - frame.minX) + abs(previousFrame.minY - frame.minY)
            guard movedDistance > 6 else { continue }

            let currentZone = partitionState.zoneAssignmentsByWindowNumber[number]
            guard currentZone != targetZone, let newZone = targetZone else { continue }

            isProgrammaticZoneTransfer = true
            defer { isProgrammaticZoneTransfer = false }

            partitionState.zoneAssignmentsByWindowNumber[number] = newZone
            desktopHandleOverlayView?.highlightedZoneName = newZone
            desktopHandleOverlayView?.needsDisplay = true

            do {
                try zoneManager.applyForcedZones(windows: windows, mergeMode: mergeMode)
                setStatus("窗口已进入分区：\(newZone)", error: false)
            } catch {
                setStatus("窗口转移分区失败：\(error.localizedDescription)", error: true)
            }
        }
    }

    /// Strongly enforce that every window fills its assigned zone.
    /// For stack zones, windows fill the content area (below tab bar).
    /// For ordinary zones, windows fill the full zone frame.
    private func enforceZoneFrames(_ windows: [WindowInfo]) {
        guard !isProgrammaticZoneTransfer else { return }

        let zoneMap = Dictionary(uniqueKeysWithValues: zoneManager.zoneDefinitions(mergeMode: mergeMode).map { ($0.name, $0.frame) })
        let activeStacks = Set(stackManager.listStacks().map(\.name))

        for window in windows {
            let number = window.windowNumber
            guard let assignedZone = partitionState.zoneAssignmentsByWindowNumber[number],
                  let zoneFrame = zoneMap[assignedZone] else { continue }

            // Stack zones: windows go below the tab bar
            let targetFrame: CGRect
            if activeStacks.contains(assignedZone) {
                let tabBarHeight = StackManager.desktopTabBarHeight
                targetFrame = CGRect(
                    x: zoneFrame.minX,
                    y: zoneFrame.minY + tabBarHeight,
                    width: zoneFrame.width,
                    height: max(80, zoneFrame.height - tabBarHeight)
                )
            } else {
                targetFrame = zoneFrame
            }

            let currentFrame = window.frame.cgRect

            let delta = abs(currentFrame.minX - targetFrame.minX)
                + abs(currentFrame.minY - targetFrame.minY)
                + abs(currentFrame.width - targetFrame.width)
                + abs(currentFrame.height - targetFrame.height)

            guard delta > 8 else { continue }

            isProgrammaticZoneTransfer = true
            defer { isProgrammaticZoneTransfer = false }

            do {
                try windowController.setWindowFrame(
                    bundleId: window.bundleId,
                    windowNumber: window.windowNumber,
                    frame: targetFrame
                )
            } catch {
                setStatus("强制归位失败：\(error.localizedDescription)", error: true)
            }
        }
    }

    @objc
    private func launchAppFromInput() {
        let bundleId = appBundleIdField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !bundleId.isEmpty else {
            setStatus("请输入 Bundle ID", error: true)
            return
        }

        do {
            try windowController.launchApp(bundleId: bundleId, activate: true)
            setStatus("已打开 \(bundleId)", error: false)
            refreshWorkbench()
        } catch {
            setStatus(error.localizedDescription, error: true)
        }
    }

    @objc
    private func openMultipleChromeWindows() {
        let countRaw = chromeWindowCountField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "3"
        let count = Int(countRaw) ?? 3
        guard count > 0 else {
            setStatus("窗口数需大于 0", error: true)
            return
        }

        do {
            try windowController.launchApp(bundleId: "com.google.Chrome", activate: true)
            try openChromeWindows(count: count)
            setStatus("已新建 \(count) 个 Chrome 窗口", error: false)
            refreshWorkbench()
        } catch {
            setStatus(error.localizedDescription, error: true)
        }
    }

    @objc
    private func tileFrontmostLeft() {
        tileFrontmost(position: .left)
    }

    @objc
    private func tileFrontmostRight() {
        tileFrontmost(position: .right)
    }

    @objc
    private func tileFrontmostTop() {
        tileFrontmost(position: .top)
    }

    @objc
    private func tileFrontmostBottom() {
        tileFrontmost(position: .bottom)
    }

    private func tileFrontmost(position: TilePosition) {
        guard let target = targetWindowIdentity() else {
            setStatus("未找到可操作的目标窗口（先点一次目标 App）", error: true)
            return
        }

        do {
            let frame = screenManager.mainVisibleFrameInScreenCoordinates()

            // 根据 position 确定堆栈名称
            let stackName = stackNameForPosition(position)
            let positionFrame = LayoutEngine().frame(for: position, in: frame)

            // 所有位置都使用堆栈管理
            _ = try stackManager.putWindowInStack(name: stackName, frame: positionFrame, window: target)
            setStatus("已将 \(target.bundleId) 收纳到 \(stackName)", error: false)

            refreshWorkbench()
        } catch {
            setStatus(error.localizedDescription, error: true)
        }
    }

    // 根据 TilePosition 返回堆栈名称
    private func stackNameForPosition(_ position: TilePosition) -> String {
        switch position {
        case .left:
            return "left"
        case .right:
            return "right"
        case .top:
            return "top"
        case .bottom:
            return "bottom"
        case .topLeft:
            return "top-left"
        case .topRight:
            return "top-right"
        case .bottomLeft:
            return "bottom-left"
        case .bottomRight:
            return "bottom-right"
        case .fullscreen:
            return "fullscreen"
        }
    }

    @objc
    private func addFrontmostToLeftBucket() {
        guard let target = targetWindowIdentity() else {
            setStatus("未找到可操作的目标窗口（先点一次目标 App）", error: true)
            return
        }
        do {
            let leftFrame = LayoutEngine().frame(for: .left, in: screenManager.mainVisibleFrameInScreenCoordinates())
            _ = try stackManager.putWindowInStack(name: "left", frame: leftFrame, window: target)
            leftBucketEnabled = true
            mergeMode = .leftColumn
            mergeControl?.selectedSegment = mergeMode.rawValue
            updateLayoutModeOverlayHighlight()
            setStatus("左桶已收纳 \(target.bundleId)", error: false)
            refreshWorkbench()
        } catch {
            setStatus(error.localizedDescription, error: true)
        }
    }

    private func switchLeftBucket(to index: Int) {
        do {
            try stackManager.switchStack(name: leftBucketName, index: index)
            setStatus("左桶切换到标签 \(index + 1)", error: false)
            refreshWorkbench()
        } catch {
            setStatus(error.localizedDescription, error: true)
        }
    }

    @objc
    private func toggleLeftBucket(_ sender: NSButton) {
        leftBucketEnabled = sender.state == .on
        if leftBucketEnabled {
            mergeMode = .leftColumn
            mergeControl?.selectedSegment = mergeMode.rawValue
            updateLayoutModeOverlayHighlight()
            setStatus("左桶模式已开启：左半屏将使用标签桶堆叠", error: false)
        } else {
            setStatus("左桶模式已关闭：左半屏恢复普通平铺", error: false)
        }
        refreshWorkbench()
    }

    @objc
    private func changeMergeMode(_ sender: NSSegmentedControl) {
        mergeMode = DesktopMergeMode(rawValue: sender.selectedSegment) ?? .grid
        updateLayoutModeOverlayHighlight()
        setStatus("切分模式：\(mergeMode.title)", error: false)
        refreshWorkbench()
    }

    private func shortcutFlagsSatisfied(flags: NSEvent.ModifierFlags) -> Bool {
        let shortcut = appConfig.layoutHUDShortcut
        if shortcut.command && !flags.contains(.command) { return false }
        if shortcut.option && !flags.contains(.option) { return false }
        if shortcut.shift && !flags.contains(.shift) { return false }
        if shortcut.control && !flags.contains(.control) { return false }
        return true
    }

    private func shortcutMatches(flags: NSEvent.ModifierFlags, keyCode: UInt16) -> Bool {
        keyCode == appConfig.layoutHUDShortcut.keyCode && shortcutFlagsSatisfied(flags: flags)
    }

    private func shortcutKeyOptions() -> [ShortcutKeyOption] {
        [
            .init(title: "A", keyCode: 0), .init(title: "B", keyCode: 11), .init(title: "C", keyCode: 8),
            .init(title: "D", keyCode: 2), .init(title: "E", keyCode: 14), .init(title: "F", keyCode: 3),
            .init(title: "G", keyCode: 5), .init(title: "H", keyCode: 4), .init(title: "I", keyCode: 34),
            .init(title: "J", keyCode: 38), .init(title: "K", keyCode: 40), .init(title: "L", keyCode: 37),
            .init(title: "M", keyCode: 46), .init(title: "N", keyCode: 45), .init(title: "O", keyCode: 31),
            .init(title: "P", keyCode: 35), .init(title: "Q", keyCode: 12), .init(title: "R", keyCode: 15),
            .init(title: "S", keyCode: 1), .init(title: "T", keyCode: 17), .init(title: "U", keyCode: 32),
            .init(title: "V", keyCode: 9), .init(title: "W", keyCode: 13), .init(title: "X", keyCode: 7),
            .init(title: "Y", keyCode: 16), .init(title: "Z", keyCode: 6),
            .init(title: "0", keyCode: 29), .init(title: "1", keyCode: 18), .init(title: "2", keyCode: 19),
            .init(title: "3", keyCode: 20), .init(title: "4", keyCode: 21), .init(title: "5", keyCode: 23),
            .init(title: "6", keyCode: 22), .init(title: "7", keyCode: 26), .init(title: "8", keyCode: 28),
            .init(title: "9", keyCode: 25)
        ]
    }

    private func keyTitle(for keyCode: UInt16) -> String {
        shortcutKeyOptions().first(where: { $0.keyCode == keyCode })?.title ?? "KeyCode \(keyCode)"
    }

    private func shortcutDisplayText() -> String {
        let shortcut = appConfig.layoutHUDShortcut
        var parts: [String] = []
        if shortcut.control { parts.append("⌃") }
        if shortcut.option { parts.append("⌥") }
        if shortcut.shift { parts.append("⇧") }
        if shortcut.command { parts.append("⌘") }
        parts.append(keyTitle(for: shortcut.keyCode))
        return parts.joined()
    }

    private func updateShortcutHintLabel() {
        shortcutHintLabel?.stringValue = "按住 \(shortcutDisplayText()) 显示布局九宫格"
    }

    @objc
    private func openSettingsWindow() {
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 220, y: 180, width: 620, height: 440),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.title = "Settings"
        settingsWindow.center()

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false
        settingsWindow.contentView = root

        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.tabViewType = .topTabsBezelBorder

        let generalItem = NSTabViewItem(identifier: "general")
        generalItem.label = "通用"
        let generalView = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 330))
        let generalLabel = NSTextField(labelWithString: "通用设置将在此扩展。")
        generalLabel.frame = NSRect(x: 20, y: 280, width: 300, height: 20)
        generalLabel.textColor = .secondaryLabelColor
        generalView.addSubview(generalLabel)
        generalItem.view = generalView
        tabView.addTabViewItem(generalItem)

        let hotkeyItem = NSTabViewItem(identifier: "hotkey")
        hotkeyItem.label = "快捷键"
        let hotkeyView = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 330))

        let title = NSTextField(labelWithString: "布局九宫格快捷键")
        title.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        title.frame = NSRect(x: 20, y: 292, width: 280, height: 24)
        hotkeyView.addSubview(title)

        let hint = NSTextField(labelWithString: "按住该快捷键时显示九宫格 HUD，松开自动隐藏。")
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 20, y: 268, width: 420, height: 18)
        hotkeyView.addSubview(hint)

        let keyLabel = NSTextField(labelWithString: "主按键")
        keyLabel.frame = NSRect(x: 20, y: 226, width: 80, height: 20)
        hotkeyView.addSubview(keyLabel)

        let keyPopup = NSPopUpButton(frame: NSRect(x: 100, y: 222, width: 120, height: 28), pullsDown: false)
        let options = shortcutKeyOptions()
        keyPopup.addItems(withTitles: options.map(\.title))
        if let idx = options.firstIndex(where: { $0.keyCode == appConfig.layoutHUDShortcut.keyCode }) {
            keyPopup.selectItem(at: idx)
        }
        hotkeyView.addSubview(keyPopup)
        shortcutKeyPopup = keyPopup

        let cmdToggle = NSButton(checkboxWithTitle: "Command (⌘)", target: nil, action: nil)
        cmdToggle.frame = NSRect(x: 20, y: 182, width: 160, height: 24)
        cmdToggle.state = appConfig.layoutHUDShortcut.command ? .on : .off
        hotkeyView.addSubview(cmdToggle)
        shortcutCommandToggle = cmdToggle

        let optToggle = NSButton(checkboxWithTitle: "Option (⌥)", target: nil, action: nil)
        optToggle.frame = NSRect(x: 190, y: 182, width: 150, height: 24)
        optToggle.state = appConfig.layoutHUDShortcut.option ? .on : .off
        hotkeyView.addSubview(optToggle)
        shortcutOptionToggle = optToggle

        let shiftToggle = NSButton(checkboxWithTitle: "Shift (⇧)", target: nil, action: nil)
        shiftToggle.frame = NSRect(x: 20, y: 152, width: 160, height: 24)
        shiftToggle.state = appConfig.layoutHUDShortcut.shift ? .on : .off
        hotkeyView.addSubview(shiftToggle)
        shortcutShiftToggle = shiftToggle

        let controlToggle = NSButton(checkboxWithTitle: "Control (⌃)", target: nil, action: nil)
        controlToggle.frame = NSRect(x: 190, y: 152, width: 150, height: 24)
        controlToggle.state = appConfig.layoutHUDShortcut.control ? .on : .off
        hotkeyView.addSubview(controlToggle)
        shortcutControlToggle = controlToggle

        let current = NSTextField(labelWithString: "当前：\(shortcutDisplayText())")
        current.textColor = .secondaryLabelColor
        current.frame = NSRect(x: 20, y: 112, width: 280, height: 20)
        hotkeyView.addSubview(current)
        shortcutCurrentLabel = current

        let saveButton = NSButton(title: "保存快捷键", target: self, action: #selector(saveShortcutSettings))
        saveButton.frame = NSRect(x: 20, y: 68, width: 120, height: 30)
        hotkeyView.addSubview(saveButton)

        hotkeyItem.view = hotkeyView
        tabView.addTabViewItem(hotkeyItem)

        root.addArrangedSubview(tabView)
        tabView.heightAnchor.constraint(equalToConstant: 360).isActive = true

        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = settingsWindow
    }

    @objc
    private func saveShortcutSettings() {
        let options = shortcutKeyOptions()
        let selectedIndex = shortcutKeyPopup?.indexOfSelectedItem ?? 0
        guard selectedIndex >= 0, selectedIndex < options.count else {
            setStatus("无效快捷键配置", error: true)
            return
        }

        let command = shortcutCommandToggle?.state == .on
        let option = shortcutOptionToggle?.state == .on
        let shift = shortcutShiftToggle?.state == .on
        let control = shortcutControlToggle?.state == .on

        if !(command || option || shift || control) {
            setStatus("至少需要一个修饰键", error: true)
            return
        }

        appConfig.layoutHUDShortcut = DesktopConfig.Shortcut(
            keyCode: options[selectedIndex].keyCode,
            command: command,
            option: option,
            shift: shift,
            control: control
        )

        do {
            try appConfig.save()
            installKeyboardShortcuts()
            updateShortcutHintLabel()
            shortcutCurrentLabel?.stringValue = "当前：\(shortcutDisplayText())"
            setStatus("快捷键已更新：\(shortcutDisplayText())", error: false)
        } catch {
            setStatus("保存快捷键失败：\(error.localizedDescription)", error: true)
        }
    }

    private func showLayoutModeOverlay() {
        isShowingLayoutOverlay = true
        let panel = ensureLayoutModeOverlayPanel()
        layoutOverlayView?.activeMode = mergeMode

        let size = NSSize(width: 560, height: 420)
        let visibleFrame: NSRect
        if let screen = window?.screen ?? NSScreen.main {
            visibleFrame = screen.visibleFrame
        } else {
            visibleFrame = NSRect(x: 120, y: 120, width: 1000, height: 700)
        }

        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    private func hideLayoutModeOverlay() {
        isShowingLayoutOverlay = false
        layoutOverlayPanel?.orderOut(nil)
    }

    private func updateLayoutModeOverlayHighlight() {
        layoutOverlayView?.activeMode = mergeMode
    }

    private func ensureLayoutModeOverlayPanel() -> NSPanel {
        if let existing = layoutOverlayPanel {
            return existing
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hasShadow = true

        let effect = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        effect.material = .hudWindow
        effect.blendingMode = .withinWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        panel.contentView = effect

        let overlayView = LayoutModeGridOverlayView(frame: effect.bounds)
        overlayView.autoresizingMask = [.width, .height]
        overlayView.activeMode = mergeMode
        overlayView.onModeSelected = { [weak self] mode in
            guard let self else { return }
            self.mergeMode = mode
            self.mergeControl?.selectedSegment = mode.rawValue
            self.updateLayoutModeOverlayHighlight()
            self.setStatus("切分模式：\(mode.title)", error: false)
            self.refreshWorkbench()
        }
        effect.addSubview(overlayView)

        layoutOverlayView = overlayView
        layoutOverlayPanel = panel
        return panel
    }

    @objc
    private func saveCurrentLayout() {
        let name = layoutNameField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else {
            setStatus("请输入布局名称", error: true)
            return
        }
        do {
            let description = "Saved from workbench \(Date())"
            _ = try layoutCoordinator.saveCurrentDesktop(name: name, description: description)
            selectedLayoutName = name
            setStatus("已保存布局：\(name)", error: false)
            reloadLayoutCards()
        } catch {
            setStatus(error.localizedDescription, error: true)
        }
    }

    @objc
    private func reloadLayoutCards() {
        guard let noteStackView else { return }
        let layouts = layoutCoordinator.listDesktops()
        noteStackView.arrangedSubviews.forEach { view in
            noteStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for layout in layouts {
            let card = LayoutNoteCardView(layout: layout, selected: layout.name == selectedLayoutName)
            card.onSelect = { [weak self] selectedName in
                self?.selectedLayoutName = selectedName
                self?.layoutNameField?.stringValue = selectedName
                self?.reloadLayoutCards()
            }
            card.onApply = { [weak self] selectedName in
                self?.applyLayout(named: selectedName)
            }
            noteStackView.addArrangedSubview(card)
        }

        // Keep document width in sync with content to prevent Auto Layout conflicts
        // inside NSStackView when cards have fixed widths.
        let cardWidth: CGFloat = 210
        let spacing: CGFloat = noteStackView.spacing
        let insets = noteStackView.edgeInsets
        let count = CGFloat(layouts.count)
        let cardsTotal = count * cardWidth + max(0, count - 1) * spacing
        let minimumVisibleWidth = noteScrollView?.contentSize.width ?? 420
        let targetWidth = max(minimumVisibleWidth, insets.left + cardsTotal + insets.right)
        noteStackView.frame = NSRect(x: 0, y: 0, width: targetWidth, height: 204)
    }

    private func applyLayout(named name: String) {
        do {
            try layoutCoordinator.applyDesktop(name: name)
            setStatus("已应用布局：\(name)", error: false)
            refreshWorkbench()
        } catch {
            setStatus(error.localizedDescription, error: true)
        }
    }

    private func makeSidebarView() -> NSView {
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 0
        container.edgeInsets = NSEdgeInsets(top: 20, left: 0, bottom: 20, right: 0)
        container.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            container.topAnchor.constraint(equalTo: sidebar.topAnchor),
            container.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor)
        ])

        let appTitle = NSTextField(labelWithString: "WinCtlManager")
        appTitle.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        appTitle.alignment = .center
        container.addArrangedSubview(appTitle)

        let spacer1 = NSView()
        spacer1.translatesAutoresizingMaskIntoConstraints = false
        spacer1.heightAnchor.constraint(equalToConstant: 24).isActive = true
        container.addArrangedSubview(spacer1)

        let navStack = NSStackView()
        navStack.orientation = .vertical
        navStack.spacing = 4
        navStack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        container.addArrangedSubview(navStack)

        for section in WorkbenchSection.allCases {
            let item = SidebarItemView(section: section)
            item.isSelected = section == currentSection
            item.onTap = { [weak self] tappedSection in
                self?.switchSection(tappedSection, animated: true)
            }
            sidebarItems.append(item)
            navStack.addArrangedSubview(item)
        }

        container.setCustomSpacing(0, after: navStack)
        let spacer2 = NSView()
        spacer2.translatesAutoresizingMaskIntoConstraints = false
        container.addArrangedSubview(spacer2)

        return sidebar
    }

    private func switchSection(_ section: WorkbenchSection, animated: Bool) {
        currentSection = section
        sidebarItems.forEach { $0.isSelected = ($0.section == section) }

        let newPanel: NSView
        switch section {
        case .layouts: newPanel = makeLayoutsPanel()
        case .stacks: newPanel = makeStacksPanel()
        case .settings: newPanel = makeSettingsPanel()
        }

        newPanel.translatesAutoresizingMaskIntoConstraints = false
        newPanel.alphaValue = animated ? 0 : 1

        contentContainer?.subviews.forEach { $0.removeFromSuperview() }
        contentContainer?.addSubview(newPanel)
        NSLayoutConstraint.activate([
            newPanel.leadingAnchor.constraint(equalTo: contentContainer!.leadingAnchor),
            newPanel.trailingAnchor.constraint(equalTo: contentContainer!.trailingAnchor),
            newPanel.topAnchor.constraint(equalTo: contentContainer!.topAnchor),
            newPanel.bottomAnchor.constraint(equalTo: contentContainer!.bottomAnchor)
        ])

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.allowsImplicitAnimation = true
                newPanel.alphaValue = 1
            }
        }
    }

    private func makeLayoutsPanel() -> NSView {
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)

        // Quick Actions card: save row + shortcut hint
        let saveRow = NSStackView()
        saveRow.orientation = .horizontal
        saveRow.spacing = 8
        saveRow.alignment = .centerY
        if let nameField = layoutNameField {
            saveRow.addArrangedSubview(nameField)
        }
        let saveBtn = makeButton("保存当前布局", action: #selector(saveCurrentLayout))
        saveBtn.contentTintColor = .controlAccentColor
        saveRow.addArrangedSubview(saveBtn)
        let shortcutHintLabel = NSTextField(labelWithString: "")
        shortcutHintLabel.textColor = .secondaryLabelColor
        shortcutHintLabel.font = NSFont.systemFont(ofSize: 11)
        self.shortcutHintLabel = shortcutHintLabel
        saveRow.addArrangedSubview(shortcutHintLabel)
        updateShortcutHintLabel()
        root.addArrangedSubview(makeGlassCard(containing: saveRow))

        // Mode card
        let modeRow = NSStackView()
        modeRow.orientation = .horizontal
        modeRow.spacing = 10
        modeRow.alignment = .centerY
        let modeLabel = NSTextField(labelWithString: "布局模式")
        modeLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        modeLabel.textColor = .secondaryLabelColor
        modeRow.addArrangedSubview(modeLabel)
        if let mergeControl { modeRow.addArrangedSubview(mergeControl) }
        let overlayToggle = makeButton("桌面分区柄：显示", action: #selector(toggleDesktopOverlayEditing))
        desktopOverlayToggleButton = overlayToggle
        modeRow.addArrangedSubview(overlayToggle)
        root.addArrangedSubview(makeGlassCard(containing: modeRow))

        // Canvas card
        if let desktopView {
            root.addArrangedSubview(makeGlassCard(
                containing: desktopView,
                insets: NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
            ))
        }

        // Status
        if let statusLabel {
            root.addArrangedSubview(makeGlassCard(
                containing: statusLabel,
                insets: NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
            ))
        }

        // Snapshots scroll
        if let noteScrollView {
            root.addArrangedSubview(makeGlassCard(
                containing: noteScrollView,
                insets: NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
            ))
        }

        return root
    }

    private func makeStacksPanel() -> NSView {
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)

        // Tile shortcuts card
        let tileRow = NSStackView()
        tileRow.orientation = .horizontal
        tileRow.spacing = 8
        tileRow.alignment = .centerY
        tileRow.addArrangedSubview(makeButton("左半屏 ⌥⌘←", action: #selector(tileFrontmostLeft)))
        tileRow.addArrangedSubview(makeButton("右半屏 ⌥⌘→", action: #selector(tileFrontmostRight)))
        tileRow.addArrangedSubview(makeButton("上半屏 ⌥⌘↑", action: #selector(tileFrontmostTop)))
        tileRow.addArrangedSubview(makeButton("下半屏 ⌥⌘↓", action: #selector(tileFrontmostBottom)))
        root.addArrangedSubview(makeGlassCard(containing: tileRow))

        // Left bucket controls
        let bucketRow = NSStackView()
        bucketRow.orientation = .horizontal
        bucketRow.spacing = 8
        bucketRow.alignment = .centerY
        bucketRow.addArrangedSubview(makeButton("加入左桶", action: #selector(addFrontmostToLeftBucket)))
        let bucketToggle = NSButton(checkboxWithTitle: "左半屏使用桶堆叠", target: self, action: #selector(toggleLeftBucket))
        bucketToggle.state = leftBucketEnabled ? .on : .off
        bucketRow.addArrangedSubview(bucketToggle)
        root.addArrangedSubview(makeGlassCard(containing: bucketRow))

        // Active stacks list
        let headerLabel = NSTextField(labelWithString: "活跃堆叠")
        headerLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        root.addArrangedSubview(headerLabel)

        let stacks = stackManager.listStacks()
        if stacks.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "暂无活跃堆叠")
            emptyLabel.textColor = .tertiaryLabelColor
            root.addArrangedSubview(emptyLabel)
        } else {
            for stack in stacks {
                let row = NSStackView()
                row.orientation = .horizontal
                row.spacing = 8
                row.alignment = .centerY
                let nameLabel = NSTextField(labelWithString: "\(stack.name)  (\(stack.windows.count) 窗口)")
                nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
                row.addArrangedSubview(nameLabel)
                root.addArrangedSubview(makeGlassCard(containing: row))
            }
        }

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(spacer)

        return root
    }

    private func makeSettingsPanel() -> NSView {
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)

        // Hotkey section
        let hotkeyTitle = NSTextField(labelWithString: "布局九宫格快捷键")
        hotkeyTitle.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        root.addArrangedSubview(hotkeyTitle)

        let hint = NSTextField(labelWithString: "按住该快捷键时显示九宫格 HUD，松开自动隐藏。")
        hint.textColor = .secondaryLabelColor
        hint.font = NSFont.systemFont(ofSize: 12)
        root.addArrangedSubview(hint)

        let keyRow = NSStackView()
        keyRow.orientation = .horizontal
        keyRow.spacing = 8
        keyRow.alignment = .centerY
        let keyLabel = NSTextField(labelWithString: "主按键")
        keyLabel.font = NSFont.systemFont(ofSize: 13)
        keyRow.addArrangedSubview(keyLabel)
        let keyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        let options = shortcutKeyOptions()
        keyPopup.addItems(withTitles: options.map(\.title))
        if let idx = options.firstIndex(where: { $0.keyCode == appConfig.layoutHUDShortcut.keyCode }) {
            keyPopup.selectItem(at: idx)
        }
        shortcutKeyPopup = keyPopup
        keyRow.addArrangedSubview(keyPopup)
        root.addArrangedSubview(makeGlassCard(containing: keyRow))

        let modRow = NSStackView()
        modRow.orientation = .horizontal
        modRow.spacing = 12
        modRow.alignment = .centerY
        let cmdToggle = NSButton(checkboxWithTitle: "⌘", target: nil, action: nil)
        cmdToggle.state = appConfig.layoutHUDShortcut.command ? .on : .off
        shortcutCommandToggle = cmdToggle
        modRow.addArrangedSubview(cmdToggle)
        let optToggle = NSButton(checkboxWithTitle: "⌥", target: nil, action: nil)
        optToggle.state = appConfig.layoutHUDShortcut.option ? .on : .off
        shortcutOptionToggle = optToggle
        modRow.addArrangedSubview(optToggle)
        let shiftToggle = NSButton(checkboxWithTitle: "⇧", target: nil, action: nil)
        shiftToggle.state = appConfig.layoutHUDShortcut.shift ? .on : .off
        shortcutShiftToggle = shiftToggle
        modRow.addArrangedSubview(shiftToggle)
        let controlToggle = NSButton(checkboxWithTitle: "⌃", target: nil, action: nil)
        controlToggle.state = appConfig.layoutHUDShortcut.control ? .on : .off
        shortcutControlToggle = controlToggle
        modRow.addArrangedSubview(controlToggle)
        root.addArrangedSubview(makeGlassCard(containing: modRow))

        let current = NSTextField(labelWithString: "当前：\(shortcutDisplayText())")
        current.textColor = .secondaryLabelColor
        shortcutCurrentLabel = current
        root.addArrangedSubview(current)

        root.addArrangedSubview(makeButton("保存快捷键", action: #selector(saveShortcutSettings)))

        // Advanced section (collapsed)
        let advancedTitle = NSTextField(labelWithString: "高级工具")
        advancedTitle.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        advancedTitle.textColor = .secondaryLabelColor
        root.addArrangedSubview(advancedTitle)

        let advRow = NSStackView()
        advRow.orientation = .vertical
        advRow.spacing = 8
        let bundleRow = NSStackView()
        bundleRow.orientation = .horizontal
        bundleRow.spacing = 8
        bundleRow.alignment = .centerY
        let appBundleIdField = NSTextField(string: "com.google.Chrome")
        appBundleIdField.placeholderString = "Bundle ID"
        appBundleIdField.translatesAutoresizingMaskIntoConstraints = false
        appBundleIdField.widthAnchor.constraint(equalToConstant: 280).isActive = true
        self.appBundleIdField = appBundleIdField
        bundleRow.addArrangedSubview(appBundleIdField)
        bundleRow.addArrangedSubview(makeButton("打开 App", action: #selector(launchAppFromInput)))
        advRow.addArrangedSubview(bundleRow)

        let chromeRow = NSStackView()
        chromeRow.orientation = .horizontal
        chromeRow.spacing = 8
        chromeRow.alignment = .centerY
        let chromeCountField = NSTextField(string: "3")
        chromeCountField.placeholderString = "窗口数"
        chromeCountField.alignment = .right
        chromeCountField.translatesAutoresizingMaskIntoConstraints = false
        chromeCountField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        self.chromeWindowCountField = chromeCountField
        chromeRow.addArrangedSubview(chromeCountField)
        chromeRow.addArrangedSubview(makeButton("多开 Chrome", action: #selector(openMultipleChromeWindows)))
        advRow.addArrangedSubview(chromeRow)

        advRow.addArrangedSubview(makeButton("立即扫描", action: #selector(runAutoScan)))
        root.addArrangedSubview(makeGlassCard(containing: advRow))

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(spacer)

        return root
    }

    private func makeButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        return button
    }

    private func makeGlassCard(containing content: NSView, insets: NSEdgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)) -> NSVisualEffectView {
        let card = NSVisualEffectView()
        card.material = .underWindowBackground
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.masksToBounds = true
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.25).cgColor
        card.layer?.borderWidth = 1
        card.translatesAutoresizingMaskIntoConstraints = false

        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: insets.left),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -insets.right),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: insets.top),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -insets.bottom)
        ])
        return card
    }

    private func setStatus(_ text: String, error: Bool) {
        statusLabel?.stringValue = text
        statusLabel?.textColor = error ? .systemRed : .secondaryLabelColor
    }

    private func targetWindowIdentity() -> WindowIdentity? {
        if let identity = windowController.frontmostWindowIdentity(ignoringCurrentProcess: true) {
            lastExternalWindowIdentity = identity
            return identity
        }
        return lastExternalWindowIdentity
    }

    private func tileWindow(identity: WindowIdentity, position: TilePosition, in screenFrame: CGRect) throws {
        if let windowNumber = identity.windowNumber {
            let frame = LayoutEngine().frame(for: position, in: screenFrame)
            try windowController.setWindowFrame(bundleId: identity.bundleId, windowNumber: windowNumber, frame: frame)
        } else {
            try windowController.tileWindow(bundleId: identity.bundleId, position: position, in: screenFrame, windowIndex: 0)
        }
    }

    @objc
    private func runAutoScan() {
        do {
            let windows = windowController.listWindows(onScreenOnly: true)
            try zoneManager.applyForcedZones(windows: windows, mergeMode: mergeMode)
            partitionState.zoneAssignmentsByWindowNumber = zoneManager.currentZoneAssignments(windows: windows, mergeMode: mergeMode)
            lastWindowFramesByNumber.removeAll()
            for window in windows {
                lastWindowFramesByNumber[window.windowNumber] = window.frame.cgRect
            }
            partitionModelInitialized = true
            setStatus("自动扫描完成", error: false)
            refreshWorkbench()
        } catch {
            setStatus(error.localizedDescription, error: true)
        }
    }

    private func refreshAllStackPanels() {
        let allStacks = stackManager.listStacks()
        let activeNames = Set(allStacks.map(\.name))

        for name in stackPanels.keys where !activeNames.contains(name) {
            stackPanels[name]?.close()
            stackPanels.removeValue(forKey: name)
            stackPanelTabStacks.removeValue(forKey: name)
        }

        let screenH = NSScreen.main?.frame.height ?? 0
        for stack in allStacks {
            updateStackPanel(stack: stack, screenHeight: screenH)
        }
    }

    private func updateStackPanel(stack: WindowStack, screenHeight: CGFloat) {
        let axFrame = stack.frame.cgRect
        let panelFrame = NSRect(
            x: axFrame.minX + 8,
            y: screenHeight - axFrame.minY - 32,
            width: max(220, axFrame.width - 16),
            height: 32
        )

        let panel: NSPanel
        let tabsStack: NSStackView

        if let existing = stackPanels[stack.name], let existingTabs = stackPanelTabStacks[stack.name] {
            panel = existing
            tabsStack = existingTabs
        } else {
            (panel, tabsStack) = makeStackPanel()
            stackPanels[stack.name] = panel
            stackPanelTabStacks[stack.name] = tabsStack
        }

        panel.setFrame(panelFrame, display: true)

        tabsStack.arrangedSubviews.forEach {
            tabsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        if stack.windows.isEmpty {
            panel.orderOut(nil)
            return
        }

        for (index, identity) in stack.windows.prefix(8).enumerated() {
            let label = "\(index + 1). \(identity.title.isEmpty ? identity.bundleId : identity.title)"
            let btn = StackTabButton(title: label, target: self, action: #selector(selectStackTab(_:)))
            btn.stackName = stack.name
            btn.tabIndex = index
            btn.bezelStyle = .rounded
            btn.controlSize = .small
            btn.font = NSFont.systemFont(ofSize: 11, weight: index == stack.activeIndex ? .semibold : .regular)
            tabsStack.addArrangedSubview(btn)
        }
        // Z-order is managed exclusively by updateAllPanelZOrder; don't touch it here.
    }

    private func makeStackPanel() -> (NSPanel, NSStackView) {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .normal
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hasShadow = true

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .withinWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 8
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]
        panel.contentView = effect

        let tabs = NSStackView()
        tabs.orientation = .horizontal
        tabs.spacing = 6
        tabs.alignment = .centerY
        tabs.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        tabs.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(tabs)
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            tabs.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            tabs.topAnchor.constraint(equalTo: effect.topAnchor),
            tabs.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])

        return (panel, tabs)
    }

    @objc
    private func selectStackTab(_ sender: StackTabButton) {
        do {
            try stackManager.switchStack(name: sender.stackName, index: sender.tabIndex)
            setStatus("\(sender.stackName) 切换到标签 \(sender.tabIndex + 1)", error: false)
            refreshWorkbench()
        } catch {
            setStatus(error.localizedDescription, error: true)
        }
    }

    private func openChromeWindows(count: Int) throws {
        let script = """
        tell application id "com.google.Chrome"
            activate
            repeat \(count) times
                make new window
            end repeat
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "osascript failed"
            throw NSError(domain: "Workbench", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func dateSuffix() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMdd_HHmm"
        return formatter.string(from: Date())
    }
}

@MainActor
private final class LayoutNoteCardView: NSView {
    let layout: DesktopLayout
    var onSelect: ((String) -> Void)?
    var onApply: ((String) -> Void)?

    private let selected: Bool

    init(layout: DesktopLayout, selected: Bool) {
        self.layout = layout
        self.selected = selected
        super.init(frame: NSRect(x: 0, y: 0, width: 210, height: 180))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 210).isActive = true
        heightAnchor.constraint(equalToConstant: 180).isActive = true
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bg = selected ? NSColor.systemYellow.withAlphaComponent(0.35) : NSColor.systemYellow.withAlphaComponent(0.2)
        let border = selected ? NSColor.systemOrange : NSColor.systemYellow.withAlphaComponent(0.8)

        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        bg.setFill()
        path.fill()
        border.setStroke()
        path.lineWidth = 2
        path.stroke()

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        layout.name.draw(in: NSRect(x: 10, y: bounds.height - 26, width: bounds.width - 20, height: 18), withAttributes: titleAttrs)

        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        "\(layout.windows.count) 窗口 / \(layout.stacks.count) 堆叠".draw(
            in: NSRect(x: 10, y: bounds.height - 44, width: bounds.width - 20, height: 16),
            withAttributes: subAttrs
        )

        let preview = NSRect(x: 10, y: 12, width: bounds.width - 20, height: bounds.height - 64)
        drawPreview(in: preview)
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?(layout.name)
        if event.clickCount >= 2 {
            onApply?(layout.name)
        }
    }

    private func drawPreview(in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor.white.withAlphaComponent(0.75).setFill()
        path.fill()

        let linePath = NSBezierPath()
        linePath.move(to: NSPoint(x: rect.midX, y: rect.minY))
        linePath.line(to: NSPoint(x: rect.midX, y: rect.maxY))
        linePath.move(to: NSPoint(x: rect.minX, y: rect.midY))
        linePath.line(to: NSPoint(x: rect.maxX, y: rect.midY))
        NSColor.systemGray.withAlphaComponent(0.5).setStroke()
        linePath.lineWidth = 1
        linePath.stroke()

        let quadrants = occupiedQuadrants()
        for quadrant in quadrants {
            NSColor.systemBlue.withAlphaComponent(0.22).setFill()
            NSBezierPath(roundedRect: quadrantRect(quadrant, in: rect).insetBy(dx: 2, dy: 2), xRadius: 4, yRadius: 4).fill()
        }
    }

    private func occupiedQuadrants() -> Set<Int> {
        var result: Set<Int> = []
        let allFrames = layout.windows.map(\.frame.cgRect) + layout.stacks.map(\.frame.cgRect)
        for frame in allFrames {
            let mid = CGPoint(x: frame.midX, y: frame.midY)
            let horizontal = mid.x >= 0 ? 1 : 0
            let vertical = mid.y >= 0 ? 0 : 2
            result.insert(horizontal + vertical)
        }
        return result
    }

    private func quadrantRect(_ quadrant: Int, in rect: NSRect) -> NSRect {
        let halfW = rect.width / 2
        let halfH = rect.height / 2
        switch quadrant {
        case 0: return NSRect(x: rect.minX, y: rect.midY, width: halfW, height: halfH) // TL
        case 1: return NSRect(x: rect.midX, y: rect.midY, width: halfW, height: halfH) // TR
        case 2: return NSRect(x: rect.minX, y: rect.minY, width: halfW, height: halfH) // BL
        default: return NSRect(x: rect.midX, y: rect.minY, width: halfW, height: halfH) // BR
        }
    }
}

@MainActor
private final class DesktopContainerView: NSView {
    private struct Section {
        var title: String
        var frame: CGRect
        var isBucket: Bool
        var tabs: [String]
        var activeTabIndex: Int
        var windows: [WindowInfo]
    }

    private struct TabHitArea {
        var rect: CGRect
        var index: Int
    }

    private enum Quadrant: CaseIterable {
        case tl
        case tr
        case bl
        case br
    }

    private enum DragAxis { case horizontal, vertical, both }

    private let displayFrame: CGRect
    private var sections: [Section] = []
    private var tabHitAreas: [TabHitArea] = []
    private var cachedWindows: [WindowInfo] = []
    private var cachedLeftBucket: WindowStack?
    private var cachedLeftBucketEnabled = true
    var onBucketTabSelected: ((Int) -> Void)?
    var onSplitChanged: ((CGFloat, CGFloat, Bool) -> Void)?

    // Split ratios (0~1), default 0.5
    var splitX: CGFloat = 0.5
    var splitY: CGFloat = 0.5

    private var draggingAxis: DragAxis?
    private let dividerHitWidth: CGFloat = 20
    private let dividerBarWidth: CGFloat = 6
    private var currentMergeMode: DesktopMergeMode = .leftColumn

    init(displayFrame: CGRect) {
        self.displayFrame = displayFrame
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.95).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(
        windows: [WindowInfo],
        leftBucket: WindowStack?,
        mergeMode: DesktopMergeMode,
        leftBucketEnabled: Bool
    ) {
        cachedWindows = windows
        cachedLeftBucket = leftBucket
        cachedLeftBucketEnabled = leftBucketEnabled
        currentMergeMode = mergeMode
        rebuildSections()
        needsDisplay = true
    }

    func applyExternalSplit(x: CGFloat, y: CGFloat) {
        splitX = clampSplit(x)
        splitY = clampSplit(y)
        rebuildSections()
        needsDisplay = true
    }

    private func rebuildSections() {
        splitX = clampSplit(splitX)
        splitY = clampSplit(splitY)
        let map = Dictionary(grouping: cachedWindows) { classify(window: $0) }
        sections = buildSections(for: currentMergeMode).map { descriptor in
            let sectionWindows = descriptor.quadrants.flatMap { map[$0] ?? [] }
            if descriptor.isLeftArea, cachedLeftBucketEnabled {
                let tabs = cachedLeftBucket?.windows.map { $0.title.isEmpty ? $0.bundleId : $0.title } ?? []
                let activeTabIndex = cachedLeftBucket?.activeIndex ?? 0
                return Section(
                    title: descriptor.title + "（标签桶）",
                    frame: descriptor.frame,
                    isBucket: true,
                    tabs: tabs,
                    activeTabIndex: activeTabIndex,
                    windows: sectionWindows
                )
            }

            return Section(
                title: descriptor.title,
                frame: descriptor.frame,
                isBucket: false,
                tabs: [],
                activeTabIndex: 0,
                windows: sectionWindows
            )
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawCanvasBackground()
        tabHitAreas.removeAll()
        for section in sections {
            tabHitAreas.append(contentsOf: drawSection(section))
        }

        // Draw divider lines
        guard let inset = sanitizedInsetBounds() else { return }
        let xDivider = inset.minX + inset.width * splitX
        let yDivider = inset.minY + inset.height * splitY

        if modeUsesVerticalDivider(currentMergeMode) {
            let vRect = NSRect(
                x: xDivider - dividerBarWidth / 2,
                y: inset.minY,
                width: dividerBarWidth,
                height: inset.height
            )
            if let safeVRect = safeRect(vRect, minWidth: 2, minHeight: 2) {
                let vBar = NSBezierPath(roundedRect: safeVRect, xRadius: 3, yRadius: 3)
                NSColor.white.withAlphaComponent(0.36).setFill()
                vBar.fill()
                NSColor.systemBlue.withAlphaComponent(0.18).setStroke()
                vBar.lineWidth = 1
                vBar.stroke()
                drawSplitHandle(at: NSPoint(x: xDivider, y: inset.midY), vertical: true)
            }
        }

        if modeUsesHorizontalDivider(currentMergeMode) {
            let hRect = NSRect(
                x: inset.minX,
                y: yDivider - dividerBarWidth / 2,
                width: inset.width,
                height: dividerBarWidth
            )
            if let safeHRect = safeRect(hRect, minWidth: 2, minHeight: 2) {
                let hBar = NSBezierPath(roundedRect: safeHRect, xRadius: 3, yRadius: 3)
                NSColor.white.withAlphaComponent(0.36).setFill()
                hBar.fill()
                NSColor.systemBlue.withAlphaComponent(0.18).setStroke()
                hBar.lineWidth = 1
                hBar.stroke()
                drawSplitHandle(at: NSPoint(x: inset.midX, y: yDivider), vertical: false)
            }
        }
    }

    /// macOS-style draggable handle: small white pill with shadow at the divider center.
    private func drawSplitHandle(at center: NSPoint, vertical: Bool) {
        let handleLength: CGFloat = 36
        let handleThickness: CGFloat = 10
        let rect: NSRect
        if vertical {
            rect = NSRect(
                x: center.x - handleThickness / 2,
                y: center.y - handleLength / 2,
                width: handleThickness,
                height: handleLength
            )
        } else {
            rect = NSRect(
                x: center.x - handleLength / 2,
                y: center.y - handleThickness / 2,
                width: handleLength,
                height: handleThickness
            )
        }
        guard let safe = safeRect(rect, minWidth: 4, minHeight: 4) else { return }

        // Shadow
        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 4
        shadow.set()

        let path = NSBezierPath(roundedRect: safe, xRadius: handleThickness / 2, yRadius: handleThickness / 2)
        NSColor.white.withAlphaComponent(0.95).setFill()
        path.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        // Center grip line for visual affordance
        let gripPath = NSBezierPath()
        if vertical {
            let lineLen = min(handleLength * 0.5, 18)
            gripPath.move(to: NSPoint(x: center.x, y: center.y - lineLen / 2))
            gripPath.line(to: NSPoint(x: center.x, y: center.y + lineLen / 2))
        } else {
            let lineLen = min(handleLength * 0.5, 18)
            gripPath.move(to: NSPoint(x: center.x - lineLen / 2, y: center.y))
            gripPath.line(to: NSPoint(x: center.x + lineLen / 2, y: center.y))
        }
        NSColor.tertiaryLabelColor.setStroke()
        gripPath.lineWidth = 1.5
        gripPath.lineCapStyle = .round
        gripPath.stroke()
    }

    private func drawCanvasBackground() {
        guard let bgRect = safeRect(bounds.insetBy(dx: 2, dy: 2), minWidth: 2, minHeight: 2) else { return }
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 14, yRadius: 14)
        let gradient = NSGradient(
            colors: [
                NSColor(calibratedRed: 0.93, green: 0.96, blue: 1.0, alpha: 0.55),
                NSColor(calibratedRed: 0.98, green: 0.98, blue: 0.99, alpha: 0.55)
            ]
        )
        gradient?.draw(in: bgPath, angle: 90)
        NSColor.separatorColor.withAlphaComponent(0.3).setStroke()
        bgPath.lineWidth = 1
        bgPath.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

        // Check tab hits first
        if let hitArea = tabHitAreas.first(where: { $0.rect.contains(location) }) {
            onBucketTabSelected?(hitArea.index)
            return
        }

        // Check divider hits
        guard let inset = sanitizedInsetBounds() else {
            super.mouseDown(with: event)
            return
        }
        let xDivider = inset.minX + inset.width * splitX
        let yDivider = inset.minY + inset.height * splitY

        let hitX = modeUsesVerticalDivider(currentMergeMode) && abs(location.x - xDivider) < dividerHitWidth
        let hitY = modeUsesHorizontalDivider(currentMergeMode) && abs(location.y - yDivider) < dividerHitWidth

        if hitX && hitY {
            draggingAxis = .both
        } else if hitX {
            draggingAxis = .horizontal
        } else if hitY {
            draggingAxis = .vertical
        } else {
            super.mouseDown(with: event)
            return
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let axis = draggingAxis else {
            super.mouseDragged(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        guard let inset = sanitizedInsetBounds() else {
            draggingAxis = nil
            return
        }

        if axis == .horizontal || axis == .both {
            let newX = (location.x - inset.minX) / max(inset.width, 1)
            splitX = clampSplit(newX)
        }

        if axis == .vertical || axis == .both {
            let newY = (location.y - inset.minY) / max(inset.height, 1)
            splitY = clampSplit(newY)
        }

        rebuildSections()
        needsDisplay = true
        onSplitChanged?(splitX, splitY, false)
    }

    override func mouseUp(with event: NSEvent) {
        if draggingAxis != nil {
            onSplitChanged?(splitX, splitY, true)
        }
        draggingAxis = nil
        super.mouseUp(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()

        guard let inset = sanitizedInsetBounds() else { return }
        let xDivider = inset.minX + inset.width * splitX
        let yDivider = inset.minY + inset.height * splitY

        // Horizontal divider cursor
        if modeUsesVerticalDivider(currentMergeMode) {
            let hRect = NSRect(
                x: xDivider - dividerHitWidth / 2,
                y: inset.minY,
                width: dividerHitWidth,
                height: inset.height
            )
            addCursorRect(hRect, cursor: .resizeLeftRight)
        }

        // Vertical divider cursor
        if modeUsesHorizontalDivider(currentMergeMode) {
            let vRect = NSRect(
                x: inset.minX,
                y: yDivider - dividerHitWidth / 2,
                width: inset.width,
                height: dividerHitWidth
            )
            addCursorRect(vRect, cursor: .resizeUpDown)
        }
    }

    private func drawSection(_ section: Section) -> [TabHitArea] {
        guard let sectionRect = safeRect(section.frame, minWidth: 6, minHeight: 6) else { return [] }
        let path = NSBezierPath(roundedRect: sectionRect, xRadius: 10, yRadius: 10)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.08)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 5
        shadow.set()

        let fillGradient: NSGradient?
        if section.isBucket {
            fillGradient = NSGradient(colors: [
                NSColor.systemBlue.withAlphaComponent(0.28),
                NSColor.systemCyan.withAlphaComponent(0.2)
            ])
        } else {
            fillGradient = NSGradient(colors: [
                NSColor.white.withAlphaComponent(0.42),
                NSColor.systemGray.withAlphaComponent(0.14)
            ])
        }
        fillGradient?.draw(in: path, angle: 90)
        NSGraphicsContext.current?.saveGraphicsState()
        NSShadow().set()

        (section.isBucket ? NSColor.systemBlue.withAlphaComponent(0.72) : NSColor.systemGray.withAlphaComponent(0.40)).setStroke()
        path.lineWidth = 1.5
        path.stroke()
        NSGraphicsContext.current?.restoreGraphicsState()

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: section.isBucket ? NSColor.systemBlue : NSColor.labelColor
        ]
        section.title.draw(
            in: NSRect(x: sectionRect.minX + 10, y: sectionRect.maxY - 24, width: sectionRect.width - 20, height: 16),
            withAttributes: titleAttrs
        )

        if section.isBucket {
            return drawTabs(
                section.tabs,
                activeIndex: section.activeTabIndex,
                in: sectionRect.insetBy(dx: 8, dy: 28)
            )
        } else {
            drawStackList(section.windows, in: sectionRect.insetBy(dx: 10, dy: 28))
            return []
        }
    }

    private func drawTabs(_ tabs: [String], activeIndex: Int, in rect: CGRect) -> [TabHitArea] {
        guard let safeArea = safeRect(rect, minWidth: 12, minHeight: 18) else { return [] }
        var hitAreas: [TabHitArea] = []
        if let tabBarRect = safeRect(CGRect(x: safeArea.minX, y: safeArea.maxY - 30, width: safeArea.width, height: 24), minWidth: 12, minHeight: 8) {
            let bar = NSBezierPath(roundedRect: tabBarRect, xRadius: 6, yRadius: 6)
            NSColor.systemBlue.withAlphaComponent(0.12).setFill()
            bar.fill()
        }

        if tabs.isEmpty {
            drawPlaceholder("空桶（点击“加入左桶”或将窗口平铺到左侧）", in: safeArea.insetBy(dx: 4, dy: 6))
            return hitAreas
        }

        let safeActiveIndex = min(max(activeIndex, 0), tabs.count - 1)
        var x = safeArea.minX
        let topY = safeArea.maxY - 30
        for (index, tab) in tabs.prefix(6).enumerated() {
            let label = "\(index + 1). \(tab)"
            let preferredWidth = min(140, max(80, CGFloat(label.count) * 7.2))
            let remainingWidth = safeArea.maxX - x
            if remainingWidth < 56 { break }

            guard let tabRect = safeRect(
                CGRect(x: x, y: topY, width: min(preferredWidth, remainingWidth), height: 22),
                minWidth: 48,
                minHeight: 10
            ) else { break }

            let p = NSBezierPath(roundedRect: tabRect, xRadius: 6, yRadius: 6)
            let isActive = index == safeActiveIndex
            (isActive ? NSColor.systemBlue.withAlphaComponent(0.62) : NSColor.systemBlue.withAlphaComponent(0.24)).setFill()
            p.fill()
            NSColor.systemBlue.withAlphaComponent(0.75).setStroke()
            p.lineWidth = 1
            p.stroke()

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
            label.draw(in: tabRect.insetBy(dx: 8, dy: 4), withAttributes: attrs)
            hitAreas.append(TabHitArea(rect: tabRect, index: index))
            x = tabRect.maxX + 6
            if x > safeArea.maxX - 42 { break }
        }

        let infoAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let activeTitle = tabs[safeActiveIndex]
        "当前标签：\(activeTitle)（点击上方标签切换）".draw(
            in: NSRect(x: safeArea.minX + 2, y: safeArea.maxY - 52, width: safeArea.width - 6, height: 16),
            withAttributes: infoAttrs
        )
        return hitAreas
    }

    private func drawStackList(_ windows: [WindowInfo], in rect: CGRect) {
        guard let safeArea = safeRect(rect, minWidth: 8, minHeight: 8) else { return }
        if windows.isEmpty {
            drawPlaceholder("空区域", in: safeArea)
            return
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        var y = safeArea.maxY - 20
        for window in windows.prefix(8) {
            let title = window.title.isEmpty ? window.appName : "\(window.appName) - \(window.title)"
            title.draw(in: NSRect(x: safeArea.minX, y: y, width: safeArea.width - 4, height: 14), withAttributes: attrs)
            y -= 15
            if y < safeArea.minY { break }
        }
    }

    private func drawPlaceholder(_ text: String, in rect: CGRect) {
        guard let safeArea = safeRect(rect, minWidth: 8, minHeight: 8) else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        text.draw(
            in: NSRect(x: safeArea.minX, y: safeArea.midY - 7, width: safeArea.width, height: 14),
            withAttributes: attrs
        )
    }

    private func classify(window: WindowInfo) -> Quadrant {
        let center = CGPoint(
            x: window.frame.cgRect.midX,
            y: window.frame.cgRect.midY
        )
        let xMid = displayFrame.midX
        let yMid = displayFrame.midY
        let isRight = center.x >= xMid
        let isTop = center.y >= yMid

        switch (isTop, isRight) {
        case (true, false): return .tl
        case (true, true): return .tr
        case (false, false): return .bl
        case (false, true): return .br
        }
    }

    private func buildSections(for mode: DesktopMergeMode) -> [(title: String, frame: CGRect, quadrants: [Quadrant], isLeftArea: Bool)] {
        guard let inset = sanitizedInsetBounds() else { return [] }

        let safeSplitX = clampSplit(splitX)
        let safeSplitY = clampSplit(splitY)
        let xSplit = inset.minX + inset.width * safeSplitX
        let ySplit = inset.minY + inset.height * safeSplitY

        let leftW = xSplit - inset.minX
        let rightW = inset.maxX - xSplit
        let bottomH = ySplit - inset.minY
        let topH = inset.maxY - ySplit

        let tl = CGRect(x: inset.minX, y: ySplit, width: leftW, height: topH)
        let tr = CGRect(x: xSplit, y: ySplit, width: rightW, height: topH)
        let bl = CGRect(x: inset.minX, y: inset.minY, width: leftW, height: bottomH)
        let br = CGRect(x: xSplit, y: inset.minY, width: rightW, height: bottomH)

        switch mode {
        case .grid:
            return [
                ("左上", tl, [.tl], true),
                ("右上", tr, [.tr], false),
                ("左下", bl, [.bl], true),
                ("右下", br, [.br], false)
            ]
        case .leftColumn:
            let left = CGRect(x: inset.minX, y: inset.minY, width: leftW, height: inset.height)
            return [
                ("左侧大块", left, [.tl, .bl], true),
                ("右上", tr, [.tr], false),
                ("右下", br, [.br], false)
            ]
        case .rightColumn:
            let right = CGRect(x: xSplit, y: inset.minY, width: rightW, height: inset.height)
            return [
                ("左上", tl, [.tl], true),
                ("左下", bl, [.bl], true),
                ("右侧大块", right, [.tr, .br], false)
            ]
        case .topRow:
            let top = CGRect(x: inset.minX, y: ySplit, width: inset.width, height: topH)
            return [
                ("上方大块", top, [.tl, .tr], true),
                ("左下", bl, [.bl], true),
                ("右下", br, [.br], false)
            ]
        case .bottomRow:
            let bottom = CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: bottomH)
            return [
                ("左上", tl, [.tl], true),
                ("右上", tr, [.tr], false),
                ("下方大块", bottom, [.bl, .br], true)
            ]
        case .leftRight:
            let left = CGRect(x: inset.minX, y: inset.minY, width: leftW, height: inset.height)
            let right = CGRect(x: xSplit, y: inset.minY, width: rightW, height: inset.height)
            return [
                ("左侧", left, [.tl, .bl], true),
                ("右侧", right, [.tr, .br], false)
            ]
        case .topBottom:
            let top = CGRect(x: inset.minX, y: ySplit, width: inset.width, height: topH)
            let bottom = CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: bottomH)
            return [
                ("上方", top, [.tl, .tr], true),
                ("下方", bottom, [.bl, .br], false)
            ]
        case .threeColumns:
            let thirdW = inset.width / 3
            let c1 = CGRect(x: inset.minX, y: inset.minY, width: thirdW, height: inset.height)
            let c2 = CGRect(x: inset.minX + thirdW, y: inset.minY, width: thirdW, height: inset.height)
            let c3 = CGRect(x: inset.minX + thirdW * 2, y: inset.minY, width: thirdW, height: inset.height)
            return [
                ("左列", c1, [.tl, .bl], true),
                ("中列", c2, [.tl, .bl, .tr, .br], false),
                ("右列", c3, [.tr, .br], false)
            ]
        case .threeRows:
            let thirdH = inset.height / 3
            let r1 = CGRect(x: inset.minX, y: inset.minY + thirdH * 2, width: inset.width, height: thirdH)
            let r2 = CGRect(x: inset.minX, y: inset.minY + thirdH, width: inset.width, height: thirdH)
            let r3 = CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: thirdH)
            return [
                ("上行", r1, [.tl, .tr], true),
                ("中行", r2, [.tl, .tr, .bl, .br], false),
                ("下行", r3, [.bl, .br], false)
            ]
        }
    }

    private func modeUsesVerticalDivider(_ mode: DesktopMergeMode) -> Bool {
        switch mode {
        case .leftRight, .leftColumn, .rightColumn, .topRow, .bottomRow, .grid:
            return true
        default:
            return false
        }
    }

    private func modeUsesHorizontalDivider(_ mode: DesktopMergeMode) -> Bool {
        switch mode {
        case .topBottom, .topRow, .bottomRow, .leftColumn, .rightColumn, .grid:
            return true
        default:
            return false
        }
    }

    private func clampSplit(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0.5 }
        return max(0.2, min(0.8, value))
    }

    private func sanitizedInsetBounds() -> CGRect? {
        safeRect(bounds.insetBy(dx: 10, dy: 10), minWidth: 2, minHeight: 2)
    }

    private func safeRect(_ rect: CGRect, minWidth: CGFloat, minHeight: CGFloat) -> CGRect? {
        guard rect.origin.x.isFinite,
              rect.origin.y.isFinite,
              rect.width.isFinite,
              rect.height.isFinite else {
            return nil
        }
        let standardized = rect.standardized
        guard standardized.width >= minWidth, standardized.height >= minHeight else {
            return nil
        }
        return standardized
    }
}

private final class StackTabButton: NSButton {
    var stackName: String = ""
    var tabIndex: Int = 0
}

@MainActor
private final class DesktopHandleOverlayView: NSView {
    var mergeMode: DesktopMergeMode = .leftColumn {
        didSet {
            rebuildDividers()
            needsDisplay = true
        }
    }
    var splitX: CGFloat = 0.5 {
        didSet {
            rebuildDividers()
            needsDisplay = true
        }
    }
    var splitY: CGFloat = 0.5 {
        didSet {
            rebuildDividers()
            needsDisplay = true
        }
    }
    var onSplitChanged: ((CGFloat, CGFloat, Bool) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    /// Zone transfer mode: show all zone boundaries
    var isZoneHighlightMode = false {
        didSet {
            if isZoneHighlightMode != oldValue {
                needsDisplay = true
                if isZoneHighlightMode {
                    startGlowAnimation()
                } else {
                    stopGlowAnimation()
                }
            }
        }
    }

    /// Active zones (windows being dragged over them)
    var activeZoneNames: Set<String> = [] {
        didSet { needsDisplay = true }
    }

    /// Highlighted zone (target zone for window transfer)
    var highlightedZoneName: String? {
        didSet { needsDisplay = true }
    }

    private var glowAnimationTimer: Timer?
    private var glowPhase: CGFloat = 0

    private struct Divider {
        let isVertical: Bool
        let start: NSPoint
        let end: NSPoint
        let center: NSPoint
    }

    private var dividers: [Divider] = []
    private var hoveredDividerIndex: Int?
    private var draggingDividerIndex: Int?
    private let handleLength: CGFloat = 60
    private let handleThickness: CGFloat = 6
    private let handleHitPadding: CGFloat = 6  // Extra padding around the visible handle for easier clicking
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        rebuildDividers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    private func rebuildDividers() {
        guard let inset = sanitizedInsetBounds() else {
            dividers = []
            return
        }

        let xDivider = inset.minX + inset.width * splitX
        // NSView coordinates: y=0 at bottom, so we need to invert splitY
        let yDivider = inset.minY + inset.height * (1.0 - splitY)

        var newDividers: [Divider] = []

        switch mergeMode {
        case .leftRight:
            // Single vertical divider spanning full height
            newDividers.append(Divider(
                isVertical: true,
                start: NSPoint(x: xDivider, y: inset.minY),
                end: NSPoint(x: xDivider, y: inset.maxY),
                center: NSPoint(x: xDivider, y: inset.midY)
            ))

        case .topBottom:
            // Single horizontal divider spanning full width
            newDividers.append(Divider(
                isVertical: false,
                start: NSPoint(x: inset.minX, y: yDivider),
                end: NSPoint(x: inset.maxX, y: yDivider),
                center: NSPoint(x: inset.midX, y: yDivider)
            ))

        case .leftColumn:
            // Vertical divider (full height) + horizontal divider (right side only)
            newDividers.append(Divider(
                isVertical: true,
                start: NSPoint(x: xDivider, y: inset.minY),
                end: NSPoint(x: xDivider, y: inset.maxY),
                center: NSPoint(x: xDivider, y: inset.midY)
            ))
            newDividers.append(Divider(
                isVertical: false,
                start: NSPoint(x: xDivider, y: yDivider),
                end: NSPoint(x: inset.maxX, y: yDivider),
                center: NSPoint(x: (xDivider + inset.maxX) / 2, y: yDivider)
            ))

        case .rightColumn:
            // Vertical divider (full height) + horizontal divider (left side only)
            newDividers.append(Divider(
                isVertical: true,
                start: NSPoint(x: xDivider, y: inset.minY),
                end: NSPoint(x: xDivider, y: inset.maxY),
                center: NSPoint(x: xDivider, y: inset.midY)
            ))
            newDividers.append(Divider(
                isVertical: false,
                start: NSPoint(x: inset.minX, y: yDivider),
                end: NSPoint(x: xDivider, y: yDivider),
                center: NSPoint(x: (inset.minX + xDivider) / 2, y: yDivider)
            ))

        case .topRow:
            // Horizontal divider (full width) + vertical divider (bottom side only)
            newDividers.append(Divider(
                isVertical: false,
                start: NSPoint(x: inset.minX, y: yDivider),
                end: NSPoint(x: inset.maxX, y: yDivider),
                center: NSPoint(x: inset.midX, y: yDivider)
            ))
            newDividers.append(Divider(
                isVertical: true,
                start: NSPoint(x: xDivider, y: inset.minY),
                end: NSPoint(x: xDivider, y: yDivider),
                center: NSPoint(x: xDivider, y: (inset.minY + yDivider) / 2)
            ))

        case .bottomRow:
            // Horizontal divider (full width) + vertical divider (top side only)
            newDividers.append(Divider(
                isVertical: false,
                start: NSPoint(x: inset.minX, y: yDivider),
                end: NSPoint(x: inset.maxX, y: yDivider),
                center: NSPoint(x: inset.midX, y: yDivider)
            ))
            newDividers.append(Divider(
                isVertical: true,
                start: NSPoint(x: xDivider, y: yDivider),
                end: NSPoint(x: xDivider, y: inset.maxY),
                center: NSPoint(x: xDivider, y: (yDivider + inset.maxY) / 2)
            ))

        case .grid:
            // Full cross: vertical + horizontal
            newDividers.append(Divider(
                isVertical: true,
                start: NSPoint(x: xDivider, y: inset.minY),
                end: NSPoint(x: xDivider, y: inset.maxY),
                center: NSPoint(x: xDivider, y: inset.midY)
            ))
            newDividers.append(Divider(
                isVertical: false,
                start: NSPoint(x: inset.minX, y: yDivider),
                end: NSPoint(x: inset.maxX, y: yDivider),
                center: NSPoint(x: inset.midX, y: yDivider)
            ))

        case .threeColumns:
            let third1 = inset.minX + inset.width / 3
            let third2 = inset.minX + inset.width * 2 / 3
            newDividers.append(Divider(
                isVertical: true,
                start: NSPoint(x: third1, y: inset.minY),
                end: NSPoint(x: third1, y: inset.maxY),
                center: NSPoint(x: third1, y: inset.midY)
            ))
            newDividers.append(Divider(
                isVertical: true,
                start: NSPoint(x: third2, y: inset.minY),
                end: NSPoint(x: third2, y: inset.maxY),
                center: NSPoint(x: third2, y: inset.midY)
            ))

        case .threeRows:
            let third1 = inset.minY + inset.height / 3
            let third2 = inset.minY + inset.height * 2 / 3
            newDividers.append(Divider(
                isVertical: false,
                start: NSPoint(x: inset.minX, y: third1),
                end: NSPoint(x: inset.maxX, y: third1),
                center: NSPoint(x: inset.midX, y: third1)
            ))
            newDividers.append(Divider(
                isVertical: false,
                start: NSPoint(x: inset.minX, y: third2),
                end: NSPoint(x: inset.maxX, y: third2),
                center: NSPoint(x: inset.midX, y: third2)
            ))
        }

        dividers = newDividers
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw zone boundaries when in transfer mode
        if isZoneHighlightMode {
            drawZoneBoundaries()
        }

        // Only draw handle when hovered (and not in zone transfer mode)
        if !isZoneHighlightMode, let hoveredIndex = hoveredDividerIndex, hoveredIndex < dividers.count {
            let divider = dividers[hoveredIndex]
            drawHandle(for: divider)
        }
    }

    private func drawZoneBoundaries() {
        guard let inset = sanitizedInsetBounds() else { return }

        // Calculate zone frames based on current merge mode
        let zones = calculateZoneFrames(in: inset)

        for (zoneName, zoneFrame) in zones {
            let isHighlighted = highlightedZoneName == zoneName
            let isActive = activeZoneNames.contains(zoneName)

            if isHighlighted {
                // Cyan-blue glow bands for target zone
                drawGlowingZone(zoneFrame)
            } else if isActive {
                // Subtle blue boundary for active zones with rounded corners
                let boundaryPath = NSBezierPath(roundedRect: zoneFrame, xRadius: 8, yRadius: 8)
                NSColor.systemBlue.withAlphaComponent(0.4).setStroke()
                boundaryPath.lineWidth = 2
                boundaryPath.stroke()

                let fillPath = NSBezierPath(roundedRect: zoneFrame, xRadius: 8, yRadius: 8)
                NSColor.systemBlue.withAlphaComponent(0.06).setFill()
                fillPath.fill()
            } else {
                // Faint boundary for inactive zones with rounded corners
                let boundaryPath = NSBezierPath(roundedRect: zoneFrame, xRadius: 8, yRadius: 8)
                NSColor.systemBlue.withAlphaComponent(0.22).setStroke()
                boundaryPath.lineWidth = 1.5
                boundaryPath.stroke()

                let fillPath = NSBezierPath(roundedRect: zoneFrame, xRadius: 8, yRadius: 8)
                NSColor.systemBlue.withAlphaComponent(0.025).setFill()
                fillPath.fill()
            }
        }
    }

    private func drawGlowingZone(_ frame: CGRect) {
        // Rounded corner radius for modern look
        let cornerRadius: CGFloat = 12

        // Multi-layer soft glow with flowing animation
        let baseIntensity = 0.5 + 0.35 * sin(glowPhase)
        let flowOffset = glowPhase * 2  // Faster flow animation

        // Outer expanding glow layers (soft gradient)
        for i in stride(from: 6, through: 1, by: -1) {
            let offset = CGFloat(i) * 4
            let alpha = baseIntensity * (CGFloat(7 - i) / 6.0) * 0.18
            let glowFrame = frame.insetBy(dx: -offset, dy: -offset)
            let glowPath = NSBezierPath(roundedRect: glowFrame, xRadius: cornerRadius + offset, yRadius: cornerRadius + offset)

            // Flowing hue shift for dynamic effect
            let hueShift = 0.02 * sin(flowOffset + CGFloat(i) * 0.3)
            let glowColor = NSColor(
                calibratedHue: 0.54 + hueShift,  // Cyan-blue with subtle flow
                saturation: 0.85 + 0.15 * sin(glowPhase + CGFloat(i) * 0.5),
                brightness: 0.95,
                alpha: alpha
            )
            glowColor.setStroke()
            glowPath.lineWidth = 5
            glowPath.stroke()
        }

        // Inner fill with breathing effect
        let fillPath = NSBezierPath(roundedRect: frame, xRadius: cornerRadius, yRadius: cornerRadius)
        let fillColor = NSColor(
            calibratedHue: 0.54,
            saturation: 0.5,
            brightness: 0.85,
            alpha: 0.15 + 0.1 * sin(glowPhase)
        )
        fillColor.setFill()
        fillPath.fill()

        // Main boundary with strong pulsating glow
        let mainPath = NSBezierPath(roundedRect: frame, xRadius: cornerRadius, yRadius: cornerRadius)
        let pulseIntensity = 0.6 + 0.4 * sin(glowPhase * 1.3)
        let mainColor = NSColor(
            calibratedHue: 0.53,
            saturation: 0.95,
            brightness: 1.0,
            alpha: pulseIntensity
        )
        mainColor.setStroke()
        mainPath.lineWidth = 3.5
        mainPath.stroke()

        // Inner accent with flowing shimmer
        let innerFrame = frame.insetBy(dx: 8, dy: 8)
        let innerPath = NSBezierPath(roundedRect: innerFrame, xRadius: cornerRadius - 4, yRadius: cornerRadius - 4)
        let shimmerPhase = glowPhase * 2.5
        let innerColor = NSColor(
            calibratedHue: 0.50,  // More blue for contrast
            saturation: 0.75,
            brightness: 0.98,
            alpha: 0.35 + 0.25 * sin(shimmerPhase)
        )
        innerColor.setStroke()
        innerPath.lineWidth = 2
        innerPath.stroke()

        // Highlight corners with extra sparkle
        drawCornerSparkles(frame, cornerRadius: cornerRadius, phase: glowPhase)
    }

    private func drawCornerSparkles(_ frame: CGRect, cornerRadius: CGFloat, phase: CGFloat) {
        let sparkleSize: CGFloat = 6
        let sparkleIntensity = 0.4 + 0.6 * sin(phase * 3)

        let corners = [
            CGPoint(x: frame.minX + cornerRadius, y: frame.minY + cornerRadius),
            CGPoint(x: frame.maxX - cornerRadius, y: frame.minY + cornerRadius),
            CGPoint(x: frame.minX + cornerRadius, y: frame.maxY - cornerRadius),
            CGPoint(x: frame.maxX - cornerRadius, y: frame.maxY - cornerRadius),
        ]

        for (index, corner) in corners.enumerated() {
            let phaseOffset = phase + CGFloat(index) * .pi / 2
            let alpha = sparkleIntensity * (0.5 + 0.5 * sin(phaseOffset))

            let sparklePath = NSBezierPath()
            sparklePath.move(to: CGPoint(x: corner.x - sparkleSize, y: corner.y))
            sparklePath.line(to: CGPoint(x: corner.x + sparkleSize, y: corner.y))
            sparklePath.move(to: CGPoint(x: corner.x, y: corner.y - sparkleSize))
            sparklePath.line(to: CGPoint(x: corner.x, y: corner.y + sparkleSize))

            NSColor(calibratedHue: 0.52, saturation: 0.9, brightness: 1.0, alpha: alpha).setStroke()
            sparklePath.lineWidth = 2
            sparklePath.lineCapStyle = .round
            sparklePath.stroke()
        }
    }

    private func calculateZoneFrames(in bounds: CGRect) -> [(String, CGRect)] {
        let xSplit = bounds.minX + bounds.width * splitX
        // NSView coordinates: y=0 at bottom, so we need to invert splitY
        let ySplit = bounds.minY + bounds.height * (1.0 - splitY)

        let leftW = xSplit - bounds.minX
        let rightW = bounds.maxX - xSplit
        let topH = bounds.maxY - ySplit  // top is above ySplit in NSView
        let bottomH = ySplit - bounds.minY  // bottom is below ySplit in NSView

        // In NSView: minY is bottom, maxY is top
        let tl = CGRect(x: bounds.minX, y: ySplit, width: leftW, height: topH)
        let tr = CGRect(x: xSplit, y: ySplit, width: rightW, height: topH)
        let bl = CGRect(x: bounds.minX, y: bounds.minY, width: leftW, height: bottomH)
        let br = CGRect(x: xSplit, y: bounds.minY, width: rightW, height: bottomH)

        switch mergeMode {
        case .grid:
            return [
                ("top-left", tl),
                ("top-right", tr),
                ("bottom-left", bl),
                ("bottom-right", br),
            ]
        case .leftColumn:
            let left = CGRect(x: bounds.minX, y: bounds.minY, width: leftW, height: bounds.height)
            return [
                ("left", left),
                ("top-right", tr),
                ("bottom-right", br),
            ]
        case .rightColumn:
            let right = CGRect(x: xSplit, y: bounds.minY, width: rightW, height: bounds.height)
            return [
                ("top-left", tl),
                ("bottom-left", bl),
                ("right", right),
            ]
        case .topRow:
            let top = CGRect(x: bounds.minX, y: ySplit, width: bounds.width, height: topH)
            return [
                ("top", top),
                ("bottom-left", bl),
                ("bottom-right", br),
            ]
        case .bottomRow:
            let bottom = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bottomH)
            return [
                ("top-left", tl),
                ("top-right", tr),
                ("bottom", bottom),
            ]
        case .leftRight:
            let left = CGRect(x: bounds.minX, y: bounds.minY, width: leftW, height: bounds.height)
            let right = CGRect(x: xSplit, y: bounds.minY, width: rightW, height: bounds.height)
            return [
                ("left", left),
                ("right", right),
            ]
        case .topBottom:
            let top = CGRect(x: bounds.minX, y: ySplit, width: bounds.width, height: topH)
            let bottom = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bottomH)
            return [
                ("top", top),
                ("bottom", bottom),
            ]
        case .threeColumns:
            let thirdW = bounds.width / 3
            let c1 = CGRect(x: bounds.minX, y: bounds.minY, width: thirdW, height: bounds.height)
            let c2 = CGRect(x: bounds.minX + thirdW, y: bounds.minY, width: thirdW, height: bounds.height)
            let c3 = CGRect(x: bounds.minX + thirdW * 2, y: bounds.minY, width: thirdW, height: bounds.height)
            return [
                ("col-left", c1),
                ("col-center", c2),
                ("col-right", c3),
            ]
        case .threeRows:
            let thirdH = bounds.height / 3
            let r1 = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: thirdH)
            let r2 = CGRect(x: bounds.minX, y: bounds.minY + thirdH, width: bounds.width, height: thirdH)
            let r3 = CGRect(x: bounds.minX, y: bounds.minY + thirdH * 2, width: bounds.width, height: thirdH)
            return [
                ("row-top", r1),
                ("row-center", r2),
                ("row-bottom", r3),
            ]
        }
    }

    private func startGlowAnimation() {
        stopGlowAnimation()
        glowPhase = 0
        glowAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.glowPhase += 0.15
                self.needsDisplay = true
            }
        }
    }

    private func stopGlowAnimation() {
        glowAnimationTimer?.invalidate()
        glowAnimationTimer = nil
        glowPhase = 0
    }

    private func drawHandle(for divider: Divider) {
        let rect = handleRect(for: divider)

        guard let safe = safeRect(rect, minWidth: 4, minHeight: 4) else { return }

        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 4
        shadow.set()

        let path = NSBezierPath(roundedRect: safe, xRadius: handleThickness / 2, yRadius: handleThickness / 2)
        NSColor.white.withAlphaComponent(0.92).setFill()
        path.fill()
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private func handleRect(for divider: Divider) -> NSRect {
        if divider.isVertical {
            return NSRect(
                x: divider.center.x - handleThickness / 2,
                y: divider.center.y - handleLength / 2,
                width: handleThickness,
                height: handleLength
            )
        } else {
            return NSRect(
                x: divider.center.x - handleLength / 2,
                y: divider.center.y - handleThickness / 2,
                width: handleLength,
                height: handleThickness
            )
        }
    }

    private func hitRect(for divider: Divider) -> NSRect {
        handleRect(for: divider).insetBy(dx: -handleHitPadding, dy: -handleHitPadding)
    }

    /// Called from a global mouse monitor to update hover state without owning events
    func updateHoverState(at point: NSPoint) {
        let newHovered = findDividerIndex(at: point)
        if newHovered != hoveredDividerIndex {
            hoveredDividerIndex = newHovered
            needsDisplay = true
            // Always enable events when near a divider to ensure clicks work
            onHoverChanged?(newHovered != nil)
        }
    }

    /// Check if point is near any divider (for event routing)
    /// Only returns true when inside the visible handle area (plus tiny padding).
    func isNearDivider(at point: NSPoint) -> Bool {
        for divider in dividers {
            if hitRect(for: divider).contains(point) {
                return true
            }
        }
        return false
    }

    // MARK: - Mouse Tracking

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let newHovered = findDividerIndex(at: location)

        if newHovered != hoveredDividerIndex {
            hoveredDividerIndex = newHovered
            needsDisplay = true
            if newHovered != nil {
                NSCursor.resizeLeftRight.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        if hoveredDividerIndex != nil {
            hoveredDividerIndex = nil
            needsDisplay = true
            NSCursor.arrow.set()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if findDividerIndex(at: point) != nil {
            return self
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        draggingDividerIndex = findDividerIndex(at: location)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragIndex = draggingDividerIndex, dragIndex < dividers.count else { return }
        guard let inset = sanitizedInsetBounds() else { return }

        let location = convert(event.locationInWindow, from: nil)
        let divider = dividers[dragIndex]

        var newX = splitX
        var newY = splitY

        if divider.isVertical {
            newX = (location.x - inset.minX) / inset.width
        } else {
            // NSView coordinates: y=0 at bottom, increases upward
            // We need to invert for AX coordinates: y=0 at top, increases downward
            newY = 1.0 - (location.y - inset.minY) / inset.height
        }

        splitX = clampSplit(newX)
        splitY = clampSplit(newY)
        onSplitChanged?(splitX, splitY, false)
    }

    override func mouseUp(with event: NSEvent) {
        guard draggingDividerIndex != nil else { return }
        draggingDividerIndex = nil
        onSplitChanged?(splitX, splitY, true)
    }

    private func findDividerIndex(at point: NSPoint) -> Int? {
        for (index, divider) in dividers.enumerated() {
            if hitRect(for: divider).contains(point) {
                return index
            }
        }
        return nil
    }

    private func clampSplit(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0.5 }
        return max(0.2, min(0.8, value))
    }

    private func sanitizedInsetBounds() -> CGRect? {
        safeRect(bounds.insetBy(dx: 10, dy: 10), minWidth: 2, minHeight: 2)
    }

    private func safeRect(_ rect: CGRect, minWidth: CGFloat, minHeight: CGFloat) -> CGRect? {
        guard rect.origin.x.isFinite,
              rect.origin.y.isFinite,
              rect.width.isFinite,
              rect.height.isFinite else {
            return nil
        }
        let standardized = rect.standardized
        guard standardized.width >= minWidth, standardized.height >= minHeight else {
            return nil
        }
        return standardized
    }
}

@MainActor
private final class SidebarItemView: NSView {
    let section: WorkbenchSection
    var isSelected: Bool = false {
        didSet { needsDisplay = true }
    }
    var onTap: ((WorkbenchSection) -> Void)?

    init(section: WorkbenchSection) {
        self.section = section
        super.init(frame: NSRect(x: 0, y: 0, width: 196, height: 36))
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 36).isActive = true
        wantsLayer = true
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private var isHovered = false

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let pillRect = bounds.insetBy(dx: 4, dy: 2)
        let pill = NSBezierPath(roundedRect: pillRect, xRadius: 8, yRadius: 8)

        if isSelected {
            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
            pill.fill()
        } else if isHovered {
            NSColor.labelColor.withAlphaComponent(0.06).setFill()
            pill.fill()
        }

        let iconSize: CGFloat = 18
        let iconX: CGFloat = 16
        let iconY = (bounds.height - iconSize) / 2
        if let image = NSImage(systemSymbolName: section.symbolName, accessibilityDescription: section.title) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let tinted = image.withSymbolConfiguration(config) ?? image
            let color = isSelected ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
            tinted.lockFocus()
            color.set()
            NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize))
        }

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: isSelected ? .semibold : .regular),
            .foregroundColor: isSelected ? NSColor.controlAccentColor : NSColor.labelColor
        ]
        section.title.draw(
            in: NSRect(x: 42, y: (bounds.height - 16) / 2, width: bounds.width - 54, height: 16),
            withAttributes: textAttrs
        )
    }

    override func mouseDown(with event: NSEvent) {
        onTap?(section)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }
}

@MainActor
private final class LayoutModeGridOverlayView: NSView {
    var activeMode: DesktopMergeMode = .grid {
        didSet { needsDisplay = true }
    }
    var onModeSelected: ((DesktopMergeMode) -> Void)?

    private struct Cell {
        let mode: DesktopMergeMode
        let rect: NSRect
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        "布局九宫格".draw(
            in: NSRect(x: 20, y: bounds.maxY - 34, width: bounds.width - 40, height: 22),
            withAttributes: titleAttrs
        )
        "按住 ⌥⌘L 显示，松开隐藏".draw(
            in: NSRect(x: 20, y: bounds.maxY - 52, width: bounds.width - 40, height: 16),
            withAttributes: subtitleAttrs
        )

        let gridRect = bounds.insetBy(dx: 18, dy: 20).offsetBy(dx: 0, dy: -18)
        let spacing: CGFloat = 10
        let columns: CGFloat = 3
        let rows: CGFloat = 3
        let cellWidth = (gridRect.width - (columns - 1) * spacing) / columns
        let cellHeight = (gridRect.height - (rows - 1) * spacing) / rows

        for cell in layoutCells(
            in: gridRect,
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            spacing: spacing
        ) {
            let cellRect = cell.rect
            let mode = cell.mode
            drawCell(mode: mode, in: cellRect, isActive: mode == activeMode)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let gridRect = bounds.insetBy(dx: 18, dy: 20).offsetBy(dx: 0, dy: -18)
        let spacing: CGFloat = 10
        let columns: CGFloat = 3
        let rows: CGFloat = 3
        let cellWidth = (gridRect.width - (columns - 1) * spacing) / columns
        let cellHeight = (gridRect.height - (rows - 1) * spacing) / rows

        if let hit = layoutCells(in: gridRect, cellWidth: cellWidth, cellHeight: cellHeight, spacing: spacing)
            .first(where: { $0.rect.contains(location) }) {
            onModeSelected?(hit.mode)
            return
        }
        super.mouseDown(with: event)
    }

    private func layoutCells(in gridRect: NSRect, cellWidth: CGFloat, cellHeight: CGFloat, spacing: CGFloat) -> [Cell] {
        var cells: [Cell] = []
        for (index, mode) in DesktopMergeMode.allCases.enumerated() {
            let row = CGFloat(index / 3)
            let col = CGFloat(index % 3)
            let x = gridRect.minX + col * (cellWidth + spacing)
            let y = gridRect.maxY - (row + 1) * cellHeight - row * spacing
            let cellRect = NSRect(x: x, y: y, width: cellWidth, height: cellHeight)
            cells.append(Cell(mode: mode, rect: cellRect))
        }
        return cells
    }

    private func drawCell(mode: DesktopMergeMode, in rect: NSRect, isActive: Bool) {
        let bgColor = isActive
            ? NSColor.systemBlue.withAlphaComponent(0.28)
            : NSColor.windowBackgroundColor.withAlphaComponent(0.25)
        let borderColor = isActive
            ? NSColor.systemBlue.withAlphaComponent(0.95)
            : NSColor.separatorColor.withAlphaComponent(0.9)

        let card = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        bgColor.setFill()
        card.fill()
        borderColor.setStroke()
        card.lineWidth = isActive ? 2.2 : 1
        card.stroke()

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: isActive ? .semibold : .medium),
            .foregroundColor: isActive ? NSColor.systemBlue : NSColor.labelColor
        ]
        mode.title.draw(
            in: NSRect(x: rect.minX + 8, y: rect.minY + 6, width: rect.width - 16, height: 14),
            withAttributes: titleAttrs
        )

        let iconRect = NSRect(x: rect.minX + 8, y: rect.minY + 24, width: rect.width - 16, height: rect.height - 32)
        drawLayoutIcon(for: mode, in: iconRect, isActive: isActive)
    }

    private func drawLayoutIcon(for mode: DesktopMergeMode, in rect: NSRect, isActive: Bool) {
        let framePath = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.withAlphaComponent(0.55).setFill()
        framePath.fill()
        NSColor.separatorColor.withAlphaComponent(0.8).setStroke()
        framePath.lineWidth = 1
        framePath.stroke()

        let zones = iconZones(for: mode, in: rect.insetBy(dx: 4, dy: 4))
        let zoneFill = isActive
            ? NSColor.systemBlue.withAlphaComponent(0.62)
            : NSColor.systemGray.withAlphaComponent(0.45)

        for zone in zones {
            let zonePath = NSBezierPath(roundedRect: zone.insetBy(dx: 1.5, dy: 1.5), xRadius: 4, yRadius: 4)
            zoneFill.setFill()
            zonePath.fill()
            NSColor.white.withAlphaComponent(0.22).setStroke()
            zonePath.lineWidth = 0.8
            zonePath.stroke()
        }
    }

    private func iconZones(for mode: DesktopMergeMode, in rect: NSRect) -> [NSRect] {
        let splitX = rect.midX
        let splitY = rect.midY

        let tl = NSRect(x: rect.minX, y: splitY, width: splitX - rect.minX, height: rect.maxY - splitY)
        let tr = NSRect(x: splitX, y: splitY, width: rect.maxX - splitX, height: rect.maxY - splitY)
        let bl = NSRect(x: rect.minX, y: rect.minY, width: splitX - rect.minX, height: splitY - rect.minY)
        let br = NSRect(x: splitX, y: rect.minY, width: rect.maxX - splitX, height: splitY - rect.minY)

        switch mode {
        case .grid:
            return [tl, tr, bl, br]
        case .leftColumn:
            let left = NSRect(x: rect.minX, y: rect.minY, width: splitX - rect.minX, height: rect.height)
            return [left, tr, br]
        case .rightColumn:
            let right = NSRect(x: splitX, y: rect.minY, width: rect.maxX - splitX, height: rect.height)
            return [tl, bl, right]
        case .topRow:
            let top = NSRect(x: rect.minX, y: splitY, width: rect.width, height: rect.maxY - splitY)
            return [top, bl, br]
        case .bottomRow:
            let bottom = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: splitY - rect.minY)
            return [tl, tr, bottom]
        case .leftRight:
            let left = NSRect(x: rect.minX, y: rect.minY, width: splitX - rect.minX, height: rect.height)
            let right = NSRect(x: splitX, y: rect.minY, width: rect.maxX - splitX, height: rect.height)
            return [left, right]
        case .topBottom:
            let top = NSRect(x: rect.minX, y: splitY, width: rect.width, height: rect.maxY - splitY)
            let bottom = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: splitY - rect.minY)
            return [top, bottom]
        case .threeColumns:
            let thirdW = rect.width / 3
            let c1 = NSRect(x: rect.minX, y: rect.minY, width: thirdW, height: rect.height)
            let c2 = NSRect(x: rect.minX + thirdW, y: rect.minY, width: thirdW, height: rect.height)
            let c3 = NSRect(x: rect.minX + thirdW * 2, y: rect.minY, width: thirdW, height: rect.height)
            return [c1, c2, c3]
        case .threeRows:
            let thirdH = rect.height / 3
            let r1 = NSRect(x: rect.minX, y: rect.minY + thirdH * 2, width: rect.width, height: thirdH)
            let r2 = NSRect(x: rect.minX, y: rect.minY + thirdH, width: rect.width, height: thirdH)
            let r3 = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: thirdH)
            return [r1, r2, r3]
        }
    }
}
