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
enum DesktopWorkbenchLauncher {
    private static var runtimeHolder: DesktopWorkbenchRuntime?

    static func open(
        windowController: WindowController,
        stackManager: StackManager,
        layoutCoordinator: DesktopLayoutCoordinator,
        layoutStore: DesktopLayoutStore,
        screenManager: ScreenManager,
        focusedLayoutName: String? = nil
    ) {
        let app = NSApplication.shared
        let runtime = DesktopWorkbenchRuntime(
            windowController: windowController,
            stackManager: stackManager,
            layoutCoordinator: layoutCoordinator,
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
    private lazy var zoneManager = DesktopZoneManager(
        windowController: windowController,
        screenManager: screenManager,
        stackManager: stackManager
    )

    private var focusedLayoutName: String?
    private var appConfig = DesktopConfig.load()
    private var mergeMode: DesktopMergeMode = .leftColumn
    private var leftBucketEnabled = true
    private var autoScanEnabled = false
    private var selectedLayoutName: String?
    private var lastExternalWindowIdentity: WindowIdentity?

    private var window: NSWindow?
    private var desktopView: DesktopContainerView?
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
    private var zoneAssignmentByWindowNumber: [Int: String] = [:]
    private var lastWindowFramesByNumber: [Int: CGRect] = [:]
    private var isProgrammaticZoneTransfer = false
    private var desktopOverlayEditingEnabled = false

    init(
        windowController: WindowController,
        stackManager: StackManager,
        layoutCoordinator: DesktopLayoutCoordinator,
        layoutStore: DesktopLayoutStore,
        screenManager: ScreenManager,
        focusedLayoutName: String?
    ) {
        self.windowController = windowController
        self.stackManager = stackManager
        self.layoutCoordinator = layoutCoordinator
        self.layoutStore = layoutStore
        self.screenManager = screenManager
        self.focusedLayoutName = focusedLayoutName
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

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root

        let title = NSTextField(labelWithString: "WinCtlManager Studio")
        title.font = NSFont.systemFont(ofSize: 30, weight: .bold)

        let subtitle = NSTextField(labelWithString: "实时编排桌面分区、窗口堆叠与布局切换")
        subtitle.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        subtitle.textColor = .secondaryLabelColor

        let header = NSStackView(views: [title, subtitle])
        header.orientation = .vertical
        header.spacing = 2

        let shortcutsRow = NSStackView()
        shortcutsRow.orientation = .horizontal
        shortcutsRow.spacing = 8
        shortcutsRow.distribution = .fill
        shortcutsRow.alignment = .centerY

        shortcutsRow.addArrangedSubview(makeButton("左半屏 ⌥⌘←", action: #selector(tileFrontmostLeft)))
        shortcutsRow.addArrangedSubview(makeButton("右半屏 ⌥⌘→", action: #selector(tileFrontmostRight)))
        shortcutsRow.addArrangedSubview(makeButton("上半屏 ⌥⌘↑", action: #selector(tileFrontmostTop)))
        shortcutsRow.addArrangedSubview(makeButton("下半屏 ⌥⌘↓", action: #selector(tileFrontmostBottom)))
        shortcutsRow.addArrangedSubview(makeButton("加入左桶", action: #selector(addFrontmostToLeftBucket)))

        let bucketToggle = NSButton(checkboxWithTitle: "左半屏使用桶堆叠", target: self, action: #selector(toggleLeftBucket))
        bucketToggle.state = .on
        shortcutsRow.addArrangedSubview(bucketToggle)
        shortcutsRow.addArrangedSubview(makeButton("立即扫描", action: #selector(runAutoScan)))
        let overlayToggle = makeButton("桌面边界编辑：关", action: #selector(toggleDesktopOverlayEditing))
        desktopOverlayToggleButton = overlayToggle
        shortcutsRow.addArrangedSubview(overlayToggle)
        shortcutsRow.addArrangedSubview(makeButton("设置", action: #selector(openSettingsWindow)))
        let shortcutHintLabel = NSTextField(labelWithString: "")
        shortcutHintLabel.textColor = .secondaryLabelColor
        self.shortcutHintLabel = shortcutHintLabel
        shortcutsRow.addArrangedSubview(shortcutHintLabel)

        let launcherRow = NSStackView()
        launcherRow.orientation = .horizontal
        launcherRow.spacing = 8
        launcherRow.distribution = .fill
        launcherRow.alignment = .centerY

        let appBundleIdField = NSTextField(string: "com.google.Chrome")
        appBundleIdField.placeholderString = "Bundle ID，例如 com.google.Chrome"
        appBundleIdField.translatesAutoresizingMaskIntoConstraints = false
        appBundleIdField.widthAnchor.constraint(equalToConstant: 320).isActive = true
        self.appBundleIdField = appBundleIdField
        launcherRow.addArrangedSubview(appBundleIdField)
        launcherRow.addArrangedSubview(makeButton("打开 App", action: #selector(launchAppFromInput)))

        let chromeCountField = NSTextField(string: "3")
        chromeCountField.placeholderString = "窗口数"
        chromeCountField.alignment = .right
        chromeCountField.translatesAutoresizingMaskIntoConstraints = false
        chromeCountField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        self.chromeWindowCountField = chromeCountField
        launcherRow.addArrangedSubview(chromeCountField)
        launcherRow.addArrangedSubview(makeButton("多开 Chrome", action: #selector(openMultipleChromeWindows)))

        let mergeControl = NSSegmentedControl(
            labels: DesktopMergeMode.allCases.map(\.title),
            trackingMode: .selectOne,
            target: self,
            action: #selector(changeMergeMode(_:))
        )
        mergeControl.segmentStyle = .rounded
        mergeControl.selectedSegment = mergeMode.rawValue
        self.mergeControl = mergeControl

        let desktopView = DesktopContainerView(displayFrame: screenManager.mainVisibleFrame())
        desktopView.translatesAutoresizingMaskIntoConstraints = false
        desktopView.heightAnchor.constraint(equalToConstant: 460).isActive = true
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

        let saveRow = NSStackView()
        saveRow.orientation = .horizontal
        saveRow.spacing = 8

        let nameField = NSTextField(string: focusedLayoutName ?? "workspace_\(dateSuffix())")
        nameField.placeholderString = "布局名称"
        self.layoutNameField = nameField
        saveRow.addArrangedSubview(nameField)

        saveRow.addArrangedSubview(makeButton("保存当前布局", action: #selector(saveCurrentLayout)))
        saveRow.addArrangedSubview(makeButton("刷新布局列表", action: #selector(reloadLayoutCards)))

        let noteStack = NSStackView()
        noteStack.orientation = .horizontal
        noteStack.spacing = 10
        noteStack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        noteStack.alignment = .top
        // NSScrollView documentView needs a concrete frame width to avoid
        // transient width=0 auto-resizing constraints fighting fixed card widths.
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

        let modeRow = NSStackView(views: [
            NSTextField(labelWithString: "布局模式"),
            mergeControl
        ])
        modeRow.orientation = .horizontal
        modeRow.spacing = 10
        modeRow.alignment = .centerY
        if let label = modeRow.arrangedSubviews.first as? NSTextField {
            label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            label.textColor = .secondaryLabelColor
        }

        root.addArrangedSubview(header)
        root.addArrangedSubview(makeGlassCard(containing: shortcutsRow))
        root.addArrangedSubview(makeGlassCard(containing: launcherRow))
        root.addArrangedSubview(makeGlassCard(containing: modeRow))
        root.addArrangedSubview(makeGlassCard(containing: desktopView, insets: NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)))
        root.addArrangedSubview(makeGlassCard(containing: statusLabel, insets: NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)))
        root.addArrangedSubview(makeGlassCard(containing: saveRow))
        root.addArrangedSubview(makeGlassCard(containing: noteScroll, insets: NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)))

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
        splitApplyWorkItem?.cancel()
        settingsWindow?.close()
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
        let frontmostBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let allStacks = stackManager.listStacks()

        for stack in allStacks {
            guard let panel = stackPanels[stack.name], !stack.windows.isEmpty else { continue }
            let safeIndex = stack.activeIndex < stack.windows.count ? stack.activeIndex : 0
            let activeWindow = stack.windows[safeIndex]
            if let bundleId = frontmostBundleId, activeWindow.bundleId == bundleId {
                panel.orderFront(nil)
            } else {
                panel.orderBack(nil)
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
            guard let self else { return event }
            let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
            if self.isShowingLayoutOverlay && !self.shortcutFlagsSatisfied(flags: flags) {
                self.hideLayoutModeOverlay()
            }
            return event
        }

        keyboardMonitors = [keyDownMonitor, keyUpMonitor, flagsChangedMonitor].compactMap { $0 }
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
        }

        let leftBucket = stackManager.stack(named: leftBucketName)
        desktopView?.update(
            windows: windows,
            leftBucket: leftBucket,
            mergeMode: mergeMode,
            leftBucketEnabled: leftBucketEnabled
        )
        desktopOverlayView?.update(
            windows: windows,
            leftBucket: leftBucket,
            mergeMode: mergeMode,
            leftBucketEnabled: leftBucketEnabled
        )
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
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hasShadow = false

        let overlay = DesktopContainerView(displayFrame: frame)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.onBucketTabSelected = { [weak self] index in
            self?.switchLeftBucket(to: index)
        }
        overlay.onSplitChanged = { [weak self] x, y, isFinal in
            guard let self else { return }
            self.handleSplitChanged(x: x, y: y, isFinal: isFinal)
            self.desktopView?.applyExternalSplit(x: x, y: y)
        }

        let content = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        content.material = .hudWindow
        content.blendingMode = .withinWindow
        content.state = .active
        content.autoresizingMask = [.width, .height]
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = content
        content.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: content.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        desktopOverlayView = overlay
        desktopPartitionPanel = panel
        panel.orderOut(nil)
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
        desktopOverlayToggleButton?.title = enabled ? "桌面边界编辑：开" : "桌面边界编辑：关"

        guard let panel = desktopPartitionPanel else { return }
        panel.ignoresMouseEvents = !enabled
        if enabled {
            panel.orderFrontRegardless()
            setStatus("已开启桌面边界编辑（可在桌面直接拖拽分区）", error: false)
        } else {
            panel.orderOut(nil)
            setStatus("已关闭桌面边界编辑", error: false)
        }
    }

    private func handleSplitChanged(x: CGFloat, y: CGFloat, isFinal: Bool) {
        desktopView?.applyExternalSplit(x: x, y: y)
        desktopOverlayView?.applyExternalSplit(x: x, y: y)
        zoneManager.splitX = x
        zoneManager.splitY = y

        splitApplyWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.applyCurrentZoneFramesToStacks()
            self.refreshAllStackPanels()
        }
        splitApplyWorkItem = work

        if isFinal {
            DispatchQueue.main.async(execute: work)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: work)
        }
    }

    private func applyCurrentZoneFramesToStacks() {
        let zoneMap = Dictionary(uniqueKeysWithValues: zoneManager.zoneDefinitions(mergeMode: mergeMode).map { ($0.name, $0.frame) })
        for stack in stackManager.listStacks() {
            guard let frame = zoneMap[stack.name] else { continue }
            do {
                try stackManager.resizeStack(name: stack.name, frame: frame)
            } catch {
                setStatus("同步分区失败：\(error.localizedDescription)", error: true)
            }
        }
    }

    private func applyWindowZoneTransfers(_ windows: [WindowInfo]) {
        guard !isProgrammaticZoneTransfer else { return }

        let visibleNumbers = Set(windows.map(\.windowNumber))
        zoneAssignmentByWindowNumber = zoneAssignmentByWindowNumber.filter { visibleNumbers.contains($0.key) }
        lastWindowFramesByNumber = lastWindowFramesByNumber.filter { visibleNumbers.contains($0.key) }

        let zoneMap = Dictionary(uniqueKeysWithValues: zoneManager.zoneDefinitions(mergeMode: mergeMode).map { ($0.name, $0.frame) })
        for window in windows {
            let number = window.windowNumber
            let frame = window.frame.cgRect
            let center = CGPoint(x: frame.midX, y: frame.midY)
            guard let targetZone = zoneManager.zoneFor(point: center, mergeMode: mergeMode)?.name else {
                lastWindowFramesByNumber[number] = frame
                continue
            }

            if zoneAssignmentByWindowNumber[number] == nil {
                zoneAssignmentByWindowNumber[number] = targetZone
                lastWindowFramesByNumber[number] = frame
                continue
            }

            defer { lastWindowFramesByNumber[number] = frame }

            guard let previousFrame = lastWindowFramesByNumber[number] else { continue }
            let movedDistance = abs(previousFrame.minX - frame.minX) + abs(previousFrame.minY - frame.minY)
            guard movedDistance > 6 else { continue }

            let currentZone = zoneAssignmentByWindowNumber[number]
            guard currentZone != targetZone, let targetFrame = zoneMap[targetZone] else { continue }

            isProgrammaticZoneTransfer = true
            defer { isProgrammaticZoneTransfer = false }

            do {
                let identity = WindowIdentity(
                    bundleId: window.bundleId,
                    title: window.title,
                    windowNumber: window.windowNumber
                )
                _ = try stackManager.putWindowInStack(name: targetZone, frame: targetFrame, window: identity)
                zoneAssignmentByWindowNumber[number] = targetZone
                setStatus("窗口已进入分区：\(targetZone)", error: false)
            } catch {
                setStatus("窗口转移分区失败：\(error.localizedDescription)", error: true)
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
            try zoneManager.autoAssign(mergeMode: mergeMode)
            partitionModelInitialized = true

            let windows = windowController.listWindows(onScreenOnly: true)
            zoneAssignmentByWindowNumber.removeAll()
            lastWindowFramesByNumber.removeAll()
            for window in windows {
                let center = CGPoint(x: window.frame.cgRect.midX, y: window.frame.cgRect.midY)
                if let zone = zoneManager.zoneFor(point: center, mergeMode: mergeMode)?.name {
                    zoneAssignmentByWindowNumber[window.windowNumber] = zone
                }
                lastWindowFramesByNumber[window.windowNumber] = window.frame.cgRect
            }

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
            }
        }
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
