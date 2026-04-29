import AppKit
import Carbon
import Foundation
import ServiceManagement

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
    case quickDrop
    case unconstrained
    case previews
    case liquidGlass
    case settings

    var title: String {
        switch self {
        case .layouts: return "布局"
        case .stacks: return "堆叠"
        case .quickDrop: return "快捷键"
        case .unconstrained: return "临时窗口"
        case .previews: return "预览"
        case .liquidGlass: return "液态玻璃"
        case .settings: return "设置"
        }
    }

    var symbolName: String {
        switch self {
        case .layouts: return "square.split.2x2.fill"
        case .stacks: return "square.3.layers.3d.top.filled"
        case .quickDrop: return "keyboard.fill"
        case .unconstrained: return "sparkles.rectangle.stack.fill"
        case .previews: return "rectangle.stack.fill"
        case .liquidGlass: return "circle.hexagongrid.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

private enum WorkbenchShortcutAction: String, CaseIterable {
    case layoutHUD
    case windowSwitcher
    case quickDropLeftPrimary
    case quickDropRightPrimary
    case quickDropLeftSecondary
    case quickDropRightSecondary
    case tileLeft
    case tileRight
    case tileTop
    case tileBottom

    var title: String {
        switch self {
        case .layoutHUD: return "布局九宫格 HUD"
        case .windowSwitcher: return "窗口搜索 / Switcher"
        case .quickDropLeftPrimary: return "移到左侧主块"
        case .quickDropRightPrimary: return "移到右侧主块"
        case .quickDropLeftSecondary: return "移到左侧次块"
        case .quickDropRightSecondary: return "移到右侧次块"
        case .tileLeft: return "平铺到左侧"
        case .tileRight: return "平铺到右侧"
        case .tileTop: return "平铺到上方"
        case .tileBottom: return "平铺到下方"
        }
    }

    var detail: String {
        switch self {
        case .layoutHUD:
            return "按住时显示九宫格，松开隐藏"
        case .windowSwitcher:
            return "打开全局窗口搜索，回车聚焦选中窗口"
        case .quickDropLeftPrimary, .quickDropRightPrimary:
            return "把当前聚焦窗口送入左右两侧最大候选块"
        case .quickDropLeftSecondary, .quickDropRightSecondary:
            return "默认投到上半区；按住 Shift 触发下半区"
        case .tileLeft, .tileRight, .tileTop, .tileBottom:
            return "直接把当前聚焦窗口贴到屏幕边缘"
        }
    }

    var defaultShortcut: DesktopConfig.Shortcut {
        switch self {
        case .layoutHUD:
            return .init(keyCode: 37, command: true, option: true, shift: false, control: false)
        case .windowSwitcher:
            return .init(keyCode: 49, command: true, option: true, shift: false, control: false)
        case .quickDropLeftPrimary:
            return .init(keyCode: 123, command: true, option: false, shift: false, control: true)
        case .quickDropRightPrimary:
            return .init(keyCode: 124, command: true, option: false, shift: false, control: true)
        case .quickDropLeftSecondary:
            return .init(keyCode: 123, command: true, option: true, shift: false, control: true)
        case .quickDropRightSecondary:
            return .init(keyCode: 124, command: true, option: true, shift: false, control: true)
        case .tileLeft:
            return .init(keyCode: 123, command: true, option: true, shift: false, control: false)
        case .tileRight:
            return .init(keyCode: 124, command: true, option: true, shift: false, control: false)
        case .tileTop:
            return .init(keyCode: 126, command: true, option: true, shift: false, control: false)
        case .tileBottom:
            return .init(keyCode: 125, command: true, option: true, shift: false, control: false)
        }
    }
}

private enum WorkbenchChrome {
    static let sidebarWidth: CGFloat = 244
    static let pageInsets = NSEdgeInsets(top: 20, left: 20, bottom: 24, right: 20)
    static let sectionSpacing: CGFloat = 14
    static let groupSpacing: CGFloat = 12
    static let cardInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
    static let compactCardInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
    static let cardCornerRadius: CGFloat = 14
}

private struct ShortcutConflict {
    let title: String
    let detail: String
}

private struct InstalledApplicationRoute {
    let bundleId: String
    let appName: String
    let appURL: URL?
    let icon: NSImage?
}

private struct AppRoutingItem {
    let bundleId: String
    let appName: String
    let appURL: URL?
    let icon: NSImage?
    let windowCount: Int
    let isRoutingLocked: Bool
}

private struct WindowSwitcherResult {
    let window: WindowInfo
    let browserURL: String?
    let browserKind: String?
    let icon: NSImage?

    var primaryTitle: String {
        let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? window.appName : title
    }

    var windowTitle: String {
        let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Untitled Window" : title
    }

    var appTitle: String {
        let app = window.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        return app.isEmpty ? window.bundleId : app
    }

    var detailText: String {
        var parts = ["\(appTitle) #\(window.windowNumber)"]
        if let browserURL, !browserURL.isEmpty {
            if let host = URL(string: browserURL)?.host {
                parts.append(host)
            } else {
                parts.append(browserURL)
            }
        }
        return parts.joined(separator: " · ")
    }

    func matches(_ query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return true }
        return [
            window.appName,
            window.bundleId,
            window.title,
            String(window.windowNumber),
            "#\(window.windowNumber)",
            browserURL ?? "",
            browserKind ?? ""
        ]
        .map { $0.lowercased() }
        .contains { $0.contains(normalized) }
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

        app.setActivationPolicy(.accessory)
        app.delegate = runtime
        app.activate(ignoringOtherApps: true)
        app.run()

        runtimeHolder = nil
    }
}

@MainActor
private final class DesktopWorkbenchRuntime: NSObject, NSApplicationDelegate, NSWindowDelegate, NSSearchFieldDelegate {
    private let leftBucketName = "left"
    private struct ShortcutKeyOption {
        let title: String
        let keyCode: UInt16
    }
    private enum QuickDropTarget {
        case leftPrimary
        case rightPrimary
        case leftSecondary
        case rightSecondary
    }

    private let windowController: WindowController
    private let previewProvider = WindowPreviewProvider()
    private let dockPreviewResolver = DockPreviewResolver()
    private let browserRestorer = BrowserPageRestorer()
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
    private var installedApplicationsCache: [InstalledApplicationRoute]?
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
    private var displayWakePanel: NSPanel?
    private var shortcutKeyPopup: NSPopUpButton?
    private var shortcutCommandToggle: NSButton?
    private var shortcutOptionToggle: NSButton?
    private var shortcutShiftToggle: NSButton?
    private var shortcutControlToggle: NSButton?
    private var shortcutCurrentLabel: NSTextField?
    private var appearancePopup: NSPopUpButton?
    private var desktopViewAspectConstraint: NSLayoutConstraint?
    private var splitApplyWorkItem: DispatchWorkItem?
    private let interactiveSplitApplyInterval: TimeInterval = 0.04
    private var lastInteractiveSplitApplyTime: TimeInterval = 0
    private var partitionModelInitialized = false
    private var lastWindowFramesByNumber: [Int: CGRect] = [:]
    private var isProgrammaticZoneTransfer = false
    private var desktopOverlayEditingEnabled = true
    private var isOptionDragTransferMode = false
    private var currentSection: WorkbenchSection = .layouts
    private var rootBackgroundView: TitaniumBackgroundView?
    private var contentContainer: NSView?
    private var sidebarItems: [SidebarItemView] = []
    private var unconstrainedFrontmostLabel: NSTextField?
    private var addFocusedWindowRuleButton: NSButton?
    private var focusedRoutingWindow: WindowInfo?
    private var appRoutingListStackView: NSStackView?
    private var titleRuleListStackView: NSStackView?
    private var temporaryMatchListStackView: NSStackView?
    private var recordingShortcutAction: WorkbenchShortcutAction?
    private var accessibilityPermissionStatusLabel: NSTextField?
    private var screenRecordingPermissionStatusLabel: NSTextField?
    private var dockPreviewStatusLabel: NSTextField?
    private var dockPreviewMenuItem: NSMenuItem?
    private var launchAtLoginStatusLabel: NSTextField?
    private var statusItem: NSStatusItem?
    private var dockPreviewPanel: NSPanel?
    private var dockPreviewCurrentBundleId: String?
    private var dockPreviewCurrentItemFrame: CGRect?
    private var dockPreviewLastRefresh = Date.distantPast
    private var dockPreviewCachedWindows: [WindowInfo] = []
    private var dockPreviewLastWindowScan = Date.distantPast
    private var dockPreviewLastHoverCheck = Date.distantPast
    private var dockPreviewHideWorkItem: DispatchWorkItem?
    private var windowSwitcherPanel: NSPanel?
    private var windowSwitcherSearchField: WindowSwitcherSearchField?
    private var windowSwitcherResultsStackView: NSStackView?
    private var windowSwitcherAllResults: [WindowSwitcherResult] = []
    private var windowSwitcherVisibleResults: [WindowSwitcherResult] = []
    private var windowSwitcherSelectedIndex = 0
    private var isQuitting = false

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
            screenManager: screenManager,
            partitionState: partitionState
        )
        self.appConfig = config
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 80, width: 1320, height: 900),
            styleMask: [.titled, .resizable, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WinCtlManager"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unifiedCompact
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 1100, height: 760)
        window.backgroundColor = NSColor.windowBackgroundColor
        window.center()
        window.delegate = self
        self.window = window

        let backgroundView = TitaniumBackgroundView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        self.rootBackgroundView = backgroundView
        window.contentView = backgroundView

        // Root split view: sidebar (220pt fixed) + content area
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor)
        ])

        let sidebar = makeSidebarView()
        splitView.addArrangedSubview(sidebar)
        let contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        self.contentContainer = contentContainer
        splitView.addArrangedSubview(contentContainer)

        // Sidebar fixed at 220 pt
        sidebar.widthAnchor.constraint(equalToConstant: WorkbenchChrome.sidebarWidth).isActive = true
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        splitView.setPosition(WorkbenchChrome.sidebarWidth, ofDividerAt: 0)
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
        desktopView.onSplitChanged = { [weak self] x, y, isFinal in
            guard let self else { return }
            self.handleSplitChanged(x: x, y: y, isFinal: isFinal)
        }
        desktopView.onWindowDroppedIntoZone = { [weak self] window, zoneName in
            self?.movePreviewWindow(window, toZoneNamed: zoneName)
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
        noteStack.frame = NSRect(x: 0, y: 0, width: 900, height: LayoutNoteCardView.cardSize.height + 16)
        self.noteStackView = noteStack

        let noteScroll = NSScrollView()
        noteScroll.drawsBackground = false
        noteScroll.hasHorizontalScroller = true
        noteScroll.hasVerticalScroller = false
        noteScroll.autohidesScrollers = true
        noteScroll.documentView = noteStack
        noteScroll.translatesAutoresizingMaskIntoConstraints = false
        noteScroll.heightAnchor.constraint(equalToConstant: LayoutNoteCardView.cardSize.height + 32).isActive = true
        self.noteScrollView = noteScroll

        applyWorkbenchAppearance(reloadSection: false)
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
        refreshPermissionStatus()
        refreshDockPreviewStatus()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard isQuitting else {
            hideAppPanel()
            return false
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanupRuntimeResources()
    }

    private func cleanupRuntimeResources() {
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
        dockPreviewHideWorkItem?.cancel()
        layoutOverlayPanel?.close()
        desktopPartitionPanel?.close()
        displayWakePanel?.close()
        dockPreviewPanel?.close()
        windowSwitcherPanel?.close()
        for panel in stackPanels.values { panel.close() }
        stackPanels.removeAll()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    private func installStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            button.toolTip = "WinCtlManager"
            if let image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "WinCtlManager") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "WinCtl"
            }
        }

        let menu = NSMenu(title: "WinCtlManager")
        menu.autoenablesItems = false

        let showItem = NSMenuItem(title: "显示 APP 面板", action: #selector(showAppPanel), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let switcherItem = NSMenuItem(title: "窗口搜索 / Switcher", action: #selector(showWindowSwitcher), keyEquivalent: "")
        switcherItem.target = self
        menu.addItem(switcherItem)

        let hideItem = NSMenuItem(title: "隐藏 APP 面板", action: #selector(hideAppPanelFromMenu), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)

        let dockPreviewItem = NSMenuItem(title: dockPreviewMenuTitle(), action: #selector(toggleDockPreviewFromMenu), keyEquivalent: "")
        dockPreviewItem.target = self
        dockPreviewMenuItem = dockPreviewItem
        menu.addItem(dockPreviewItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出程序", action: #selector(quitApplication), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc
    private func showAppPanel() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if desktopOverlayEditingEnabled {
            desktopPartitionPanel?.orderFrontRegardless()
        }
        refreshWorkbench()
    }

    @objc
    private func hideAppPanelFromMenu() {
        hideAppPanel()
    }

    private func hideAppPanel() {
        window?.orderOut(nil)
        settingsWindow?.orderOut(nil)
        layoutOverlayPanel?.orderOut(nil)
        displayWakePanel?.orderOut(nil)
        desktopPartitionPanel?.orderOut(nil)
        setStatus("已隐藏 APP 面板，可从菜单栏重新打开", error: false)
    }

    private func dockPreviewMenuTitle() -> String {
        appConfig.dockPreviewEnabled ? "关闭 Dock Preview" : "开启 Dock Preview"
    }

    @objc
    private func toggleDockPreviewFromMenu() {
        setDockPreviewEnabled(!appConfig.dockPreviewEnabled)
    }

    @objc
    private func quitApplication() {
        isQuitting = true
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

            if let recordingAction = self.recordingShortcutAction {
                self.captureShortcut(from: event, for: recordingAction)
                return nil
            }

            guard let action = self.shortcutAction(matching: flags, keyCode: event.keyCode) else {
                return event
            }
            self.performShortcutAction(action, event: event)
            return nil
        }

        let globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
            guard let action = self.shortcutAction(matching: flags, keyCode: event.keyCode),
                  action == .windowSwitcher
            else {
                return
            }
            self.performShortcutAction(action, event: event)
        }

        let keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == self.shortcut(for: .layoutHUD).keyCode {
                self.hideLayoutModeOverlay()
                return nil
            }
            if self.recordingShortcutAction == .layoutHUD {
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

        keyboardMonitors = [keyDownMonitor, globalKeyDownMonitor, keyUpMonitor, flagsChangedMonitor, flagsChangedGlobalMonitor].compactMap { $0 }
    }

    private func handleFlagsChanged(_ modifierFlags: NSEvent.ModifierFlags) {
        let flags = modifierFlags.intersection([.command, .option, .shift, .control])
        if self.isShowingLayoutOverlay && !self.shortcutFlagsSatisfied(flags: flags, shortcut: shortcut(for: .layoutHUD)) {
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
        let visibleNumbers = Set(windows.map(\.windowNumber))
        partitionState.unconstrainedWindowNumbers = currentUnconstrainedWindowNumbers(in: windows).intersection(visibleNumbers)
        partitionState.zoneAssignmentsByWindowNumber = partitionState.zoneAssignmentsByWindowNumber.filter {
            visibleNumbers.contains($0.key) && !partitionState.unconstrainedWindowNumbers.contains($0.key)
        }
        lastWindowFramesByNumber = lastWindowFramesByNumber.filter {
            visibleNumbers.contains($0.key) && !partitionState.unconstrainedWindowNumbers.contains($0.key)
        }
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
        refreshUnconstrainedWindowList(with: windows)
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
        mousePollingTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
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

        updateDockPreviewHover(at: screenPoint)
    }

    private func updateDockPreviewHover(at screenPoint: CGPoint) {
        guard appConfig.dockPreviewEnabled else {
            hideDockPreviewPanel()
            return
        }

        let now = Date()
        if now.timeIntervalSince(dockPreviewLastHoverCheck) < 0.08 {
            return
        }
        dockPreviewLastHoverCheck = now

        if isPointInsideDockPreviewPanel(screenPoint) {
            dockPreviewHideWorkItem?.cancel()
            return
        }

        let windows = dockPreviewVisibleWindows()
        guard let match = dockPreviewResolver.matchHover(at: screenPoint, windows: windows) else {
            scheduleDockPreviewHide()
            return
        }
        dockPreviewHideWorkItem?.cancel()
        dockPreviewCurrentItemFrame = match.itemFrame

        let matchingWindows = windows
            .filter { $0.bundleId == match.bundleId }
            .sorted { lhs, rhs in
                let leftTitle = lhs.title.isEmpty ? lhs.appName : lhs.title
                let rightTitle = rhs.title.isEmpty ? rhs.appName : rhs.title
                if leftTitle == rightTitle {
                    return lhs.windowNumber < rhs.windowNumber
                }
                return leftTitle.localizedCaseInsensitiveCompare(rightTitle) == .orderedAscending
            }

        guard !matchingWindows.isEmpty else {
            scheduleDockPreviewHide()
            return
        }

        let shouldRebuild = dockPreviewCurrentBundleId != match.bundleId
            || Date().timeIntervalSince(dockPreviewLastRefresh) > 2.0
        if shouldRebuild {
            showDockPreviewPanel(for: match, windows: matchingWindows)
        } else {
            positionDockPreviewPanel(for: match)
        }
    }

    private func dockPreviewVisibleWindows() -> [WindowInfo] {
        let now = Date()
        if now.timeIntervalSince(dockPreviewLastWindowScan) < 0.20 {
            return dockPreviewCachedWindows
        }
        dockPreviewLastWindowScan = now
        dockPreviewCachedWindows = windowController.listWindows(onScreenOnly: true).filter(\.isControllable)
        return dockPreviewCachedWindows
    }

    private func showDockPreviewPanel(for match: DockHoverMatch, windows: [WindowInfo]) {
        dockPreviewHideWorkItem?.cancel()
        dockPreviewCurrentBundleId = match.bundleId
        dockPreviewLastRefresh = Date()

        let snapshots = previewProvider.snapshots(for: Array(windows.prefix(6)))
        guard !snapshots.isEmpty else {
            hideDockPreviewPanel()
            return
        }

        let panel = dockPreviewPanel ?? makeDockPreviewPanel()
        let content = makeDockPreviewContent(match: match, snapshots: snapshots, totalWindowCount: windows.count)
        panel.contentView = content
        panel.setContentSize(content.fittingSize)
        dockPreviewPanel = panel
        positionDockPreviewPanel(for: match)
        panel.orderFrontRegardless()
    }

    private func makeDockPreviewPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 210),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }

    private func makeDockPreviewContent(match: DockHoverMatch, snapshots: [WindowPreviewSnapshot], totalWindowCount: Int) -> NSView {
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true
        effect.translatesAutoresizingMaskIntoConstraints = false

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        root.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            root.topAnchor.constraint(equalTo: effect.topAnchor),
            root.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])

        let title = NSTextField(labelWithString: totalWindowCount > snapshots.count ? "\(match.appName) · \(totalWindowCount) 个窗口" : match.appName)
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        root.addArrangedSubview(title)

        let cards = NSStackView()
        cards.orientation = .horizontal
        cards.spacing = 10
        cards.alignment = .centerY
        for snapshot in snapshots {
            let card = DockWindowPreviewCardView(snapshot: snapshot)
            card.onFocus = { [weak self] window in
                self?.hideDockPreviewPanel()
                self?.focusPreviewWindow(window)
            }
            cards.addArrangedSubview(card)
        }
        root.addArrangedSubview(cards)

        let width = cards.arrangedSubviews.reduce(CGFloat(0)) { $0 + $1.fittingSize.width }
            + CGFloat(max(0, snapshots.count - 1)) * 10
            + 24
        let height = DockWindowPreviewCardView.cardHeight + 58
        NSLayoutConstraint.activate([
            effect.widthAnchor.constraint(equalToConstant: max(240, width)),
            effect.heightAnchor.constraint(equalToConstant: height)
        ])

        return effect
    }

    private func positionDockPreviewPanel(for match: DockHoverMatch) {
        guard let panel = dockPreviewPanel else { return }
        let size = panel.frame.size
        let screenFrame = (NSScreen.screens.first { $0.frame.intersects(match.dockFrame) } ?? NSScreen.main)?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let padding: CGFloat = 12
        let origin: CGPoint

        switch match.edge {
        case .bottom:
            let x = clamp(match.itemFrame.midX - size.width / 2, min: screenFrame.minX + padding, max: screenFrame.maxX - size.width - padding)
            let y = clamp(match.itemFrame.maxY + padding, min: screenFrame.minY + padding, max: screenFrame.maxY - size.height - padding)
            origin = CGPoint(x: x, y: y)
        case .left:
            let x = clamp(match.itemFrame.maxX + padding, min: screenFrame.minX + padding, max: screenFrame.maxX - size.width - padding)
            let y = clamp(match.itemFrame.midY - size.height / 2, min: screenFrame.minY + padding, max: screenFrame.maxY - size.height - padding)
            origin = CGPoint(x: x, y: y)
        case .right:
            let x = clamp(match.itemFrame.minX - size.width - padding, min: screenFrame.minX + padding, max: screenFrame.maxX - size.width - padding)
            let y = clamp(match.itemFrame.midY - size.height / 2, min: screenFrame.minY + padding, max: screenFrame.maxY - size.height - padding)
            origin = CGPoint(x: x, y: y)
        }

        panel.setFrameOrigin(origin)
    }

    private func scheduleDockPreviewHide() {
        guard dockPreviewPanel?.isVisible == true else { return }
        dockPreviewHideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self,
                      !self.isPointInsideDockPreviewPanel(NSEvent.mouseLocation),
                      !self.isPointInsideCurrentDockTarget(NSEvent.mouseLocation)
                else {
                    return
                }
                self.hideDockPreviewPanel()
            }
        }
        dockPreviewHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func hideDockPreviewPanel() {
        dockPreviewHideWorkItem?.cancel()
        dockPreviewPanel?.orderOut(nil)
        dockPreviewCurrentBundleId = nil
        dockPreviewCurrentItemFrame = nil
    }

    private func isPointInsideDockPreviewPanel(_ screenPoint: CGPoint) -> Bool {
        guard let panel = dockPreviewPanel, panel.isVisible else { return false }
        return panel.frame.insetBy(dx: -10, dy: -10).contains(screenPoint)
    }

    private func isPointInsideCurrentDockTarget(_ screenPoint: CGPoint) -> Bool {
        guard let frame = dockPreviewCurrentItemFrame else { return false }
        return frame.insetBy(dx: -8, dy: -8).contains(screenPoint)
    }

    private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        guard maxValue >= minValue else { return minValue }
        return Swift.min(Swift.max(value, minValue), maxValue)
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
            self.lastInteractiveSplitApplyTime = Date.timeIntervalSinceReferenceDate
            self.applySplitToDesktopWindows(
                behavior: .interactiveResize,
                statusText: isFinal ? "已同步分区大小到桌面窗口" : "正在实时调整分区窗口"
            )
        }
        splitApplyWorkItem = work

        if isFinal {
            DispatchQueue.main.async(execute: work)
            return
        }

        let now = Date.timeIntervalSinceReferenceDate
        let elapsed = now - lastInteractiveSplitApplyTime
        let delay = max(0, interactiveSplitApplyInterval - elapsed)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func applySplitToDesktopWindows(behavior: ZoneApplyBehavior, statusText: String) {
        let windows = windowController.listWindows(onScreenOnly: true)
        let unconstrained = currentUnconstrainedWindowNumbers(in: windows)
        partitionState.unconstrainedWindowNumbers = unconstrained
        do {
            try zoneManager.applyForcedZones(
                windows: windows,
                mergeMode: mergeMode,
                excludingWindowNumbers: unconstrained,
                behavior: behavior
            )
            refreshAllStackPanels()
            setStatus(statusText, error: false)
        } catch {
            setStatus("同步分区窗口失败：\(error.localizedDescription)", error: true)
        }
    }

    private func movePreviewWindow(_ window: WindowInfo, toZoneNamed zoneName: String) {
        let windows = windowController.listWindows(onScreenOnly: true)
        let visibleNumbers = Set(windows.map(\.windowNumber))
        guard visibleNumbers.contains(window.windowNumber) else {
            setStatus("目标窗口已不在当前桌面可见区域", error: true)
            refreshWorkbench()
            return
        }
        guard window.isControllable else {
            setStatus("该窗口缺少可控 App 身份，已作为不可控窗口跳过", error: true)
            refreshWorkbench()
            return
        }
        guard let targetZone = zoneManager.zoneDefinitions(mergeMode: mergeMode).first(where: { $0.name == zoneName }) else {
            setStatus("未找到目标分区：\(zoneName)", error: true)
            return
        }

        do {
            try windowController.setWindowFrame(
                bundleId: window.bundleId,
                windowNumber: window.windowNumber,
                frame: targetZone.frame
            )
            partitionState.zoneAssignmentsByWindowNumber[window.windowNumber] = zoneName
            lastWindowFramesByNumber[window.windowNumber] = targetZone.frame
            partitionModelInitialized = true

            let updatedWindows = windowController.listWindows(onScreenOnly: true)
            let unconstrained = currentUnconstrainedWindowNumbers(in: updatedWindows)
            partitionState.unconstrainedWindowNumbers = unconstrained
            try zoneManager.applyForcedZones(
                windows: updatedWindows,
                mergeMode: mergeMode,
                excludingWindowNumbers: unconstrained
            )
            setStatus("已将 \(window.appName) 移到 \(zoneName)", error: false)
            refreshWorkbench()
        } catch {
            setStatus("移动窗口到分区失败：\(error.localizedDescription)", error: true)
        }
    }

    private func applyWindowZoneTransfers(_ windows: [WindowInfo]) {
        guard !isProgrammaticZoneTransfer else { return }
        guard isOptionDragTransferMode else { return }  // Only transfer when Command+Shift is held

        let visibleNumbers = Set(windows.map(\.windowNumber))
        partitionState.unconstrainedWindowNumbers = currentUnconstrainedWindowNumbers(in: windows).intersection(visibleNumbers)
        partitionState.zoneAssignmentsByWindowNumber = partitionState.zoneAssignmentsByWindowNumber.filter {
            visibleNumbers.contains($0.key) && !partitionState.unconstrainedWindowNumbers.contains($0.key)
        }
        lastWindowFramesByNumber = lastWindowFramesByNumber.filter {
            visibleNumbers.contains($0.key) && !partitionState.unconstrainedWindowNumbers.contains($0.key)
        }

        let unconstrained = partitionState.unconstrainedWindowNumbers
        let assignments = zoneManager.currentZoneAssignments(
            windows: windows,
            mergeMode: mergeMode,
            excludingWindowNumbers: unconstrained
        )
        desktopHandleOverlayView?.activeZoneNames = []

        for window in windows {
            let number = window.windowNumber
            guard !unconstrained.contains(number) else { continue }
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
                try zoneManager.applyForcedZones(
                    windows: windows,
                    mergeMode: mergeMode,
                    excludingWindowNumbers: unconstrained
                )
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
            guard window.isControllable else { continue }
            if partitionState.unconstrainedWindowNumbers.contains(number) {
                continue
            }
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

    @objc
    private func quickDropToLeftPrimary() {
        quickDropFrontmost(to: .leftPrimary)
    }

    @objc
    private func quickDropToRightPrimary() {
        quickDropFrontmost(to: .rightPrimary)
    }

    @objc
    private func quickDropToLeftSecondary() {
        quickDropFrontmost(to: .leftSecondary)
    }

    @objc
    private func quickDropToRightSecondary() {
        quickDropFrontmost(to: .rightSecondary)
    }

    @objc
    private func showShortcutSection() {
        switchSection(.quickDrop, animated: true)
    }

    private func quickDropFrontmost(to target: QuickDropTarget, preferLowerSecondary explicitPreference: Bool? = nil) {
        guard let identity = targetWindowIdentity() else {
            setStatus("未找到可操作的目标窗口（先点一次目标 App）", error: true)
            return
        }

        let preferLowerSecondary = explicitPreference ?? (NSApp.currentEvent?.modifierFlags.contains(.shift) == true)
        guard let zone = quickDropZone(for: target, preferLowerSecondary: preferLowerSecondary) else {
            let hint: String
            switch target {
            case .leftSecondary, .rightSecondary:
                hint = "当前布局没有可用的次块，请切换到四分/左二右大/左大右二后再试。"
            default:
                hint = "当前布局没有可用目标块。"
            }
            setStatus(hint, error: true)
            return
        }

        let windows = windowController.listWindows(onScreenOnly: true)
        guard let window = resolveTargetWindowInfo(identity: identity, windows: windows) else {
            setStatus("未找到目标窗口实例，请先激活目标窗口。", error: true)
            return
        }

        do {
            try windowController.setWindowFrame(
                bundleId: window.bundleId,
                windowNumber: window.windowNumber,
                frame: zone.frame
            )
            partitionState.zoneAssignmentsByWindowNumber[window.windowNumber] = zone.name
            lastWindowFramesByNumber[window.windowNumber] = zone.frame
            partitionModelInitialized = true

            let updatedWindows = windowController.listWindows(onScreenOnly: true)
            let unconstrained = currentUnconstrainedWindowNumbers(in: updatedWindows)
            partitionState.unconstrainedWindowNumbers = unconstrained
            try zoneManager.applyForcedZones(
                windows: updatedWindows,
                mergeMode: mergeMode,
                excludingWindowNumbers: unconstrained
            )

            setStatus("已将 \(window.appName) 投放到 \(zone.name)", error: false)
            refreshWorkbench()
        } catch {
            setStatus("快捷投放失败：\(error.localizedDescription)", error: true)
        }
    }

    private func quickDropZone(for target: QuickDropTarget, preferLowerSecondary: Bool) -> DesktopZone? {
        let zones = zoneManager.zoneDefinitions(mergeMode: mergeMode)
        guard !zones.isEmpty else { return nil }

        let screenMidX = screenManager.mainVisibleFrameInScreenCoordinates().midX
        let leftZones = zones.filter { $0.frame.midX <= screenMidX }
        let rightZones = zones.filter { $0.frame.midX > screenMidX }

        func primaryZone(in candidates: [DesktopZone], fallbackTo all: [DesktopZone], preferLeft: Bool) -> DesktopZone? {
            let pool = candidates.isEmpty ? all : candidates
            guard !pool.isEmpty else { return nil }
            return pool.max { lhs, rhs in
                let leftArea = lhs.frame.width * lhs.frame.height
                let rightArea = rhs.frame.width * rhs.frame.height
                if leftArea == rightArea {
                    return preferLeft ? lhs.frame.midX > rhs.frame.midX : lhs.frame.midX < rhs.frame.midX
                }
                return leftArea < rightArea
            }
        }

        func secondaryZone(in candidates: [DesktopZone]) -> DesktopZone? {
            guard candidates.count >= 2 else { return nil }
            let sorted = candidates.sorted { $0.frame.midY < $1.frame.midY } // AX: smaller y = upper half
            return preferLowerSecondary ? sorted.last : sorted.first
        }

        switch target {
        case .leftPrimary:
            if let named = zones.first(where: { $0.name == "left" }) { return named }
            return primaryZone(in: leftZones, fallbackTo: zones, preferLeft: true)
        case .rightPrimary:
            if let named = zones.first(where: { $0.name == "right" }) { return named }
            return primaryZone(in: rightZones, fallbackTo: zones, preferLeft: false)
        case .leftSecondary:
            return secondaryZone(in: leftZones)
        case .rightSecondary:
            return secondaryZone(in: rightZones)
        }
    }

    private func resolveTargetWindowInfo(identity: WindowIdentity, windows: [WindowInfo]) -> WindowInfo? {
        if let number = identity.windowNumber,
           let exact = windows.first(where: { $0.windowNumber == number }) {
            return exact
        }

        if !identity.title.isEmpty,
           let exactTitle = windows.first(where: { $0.bundleId == identity.bundleId && $0.title == identity.title }) {
            return exactTitle
        }

        return windows.first(where: { $0.bundleId == identity.bundleId })
    }

    private func windowRoutingType(for window: WindowInfo) -> WindowRoutingType {
        guard window.isControllable else { return .uncontrollable }
        if let titleRule = partitionState.titleRoutingRules.last(where: { rule in
            rule.bundleId == window.bundleId
                && !rule.title.isEmpty
                && !window.title.isEmpty
                && window.title.localizedCaseInsensitiveContains(rule.title)
        }) {
            return titleRule.type
        }
        return partitionState.appRoutingTypesByBundleId[window.bundleId] ?? .managed
    }

    private func currentUnconstrainedWindowNumbers(in windows: [WindowInfo]) -> Set<Int> {
        Set(
            windows
                .filter { windowRoutingType(for: $0).isExcludedFromLayout }
                .map(\.windowNumber)
        )
    }

    private func scanInstalledApps(with windows: [WindowInfo]) -> [AppRoutingItem] {
        let windowCounts = Dictionary(grouping: windows, by: \.bundleId).mapValues(\.count)
        var appsByBundleId = Dictionary(
            uniqueKeysWithValues: installedApplications().map { ($0.bundleId, $0) }
        )

        let selfBundle = Bundle.main.bundleIdentifier
        for runningApp in NSWorkspace.shared.runningApplications {
            guard runningApp.activationPolicy == .regular,
                  let bundleId = runningApp.bundleIdentifier,
                  bundleId != selfBundle else { continue }
            if appsByBundleId[bundleId] == nil {
                appsByBundleId[bundleId] = InstalledApplicationRoute(
                    bundleId: bundleId,
                    appName: runningApp.localizedName ?? bundleId,
                    appURL: runningApp.bundleURL,
                    icon: runningApp.icon
                )
            }
        }

        for window in windows where !window.isControllable {
            if appsByBundleId[window.bundleId] == nil {
                appsByBundleId[window.bundleId] = InstalledApplicationRoute(
                    bundleId: window.bundleId,
                    appName: window.appName.isEmpty ? "不可识别窗口" : window.appName,
                    appURL: nil,
                    icon: NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "不可控窗口")
                )
            }
        }

        return appsByBundleId.values
            .map {
                AppRoutingItem(
                    bundleId: $0.bundleId,
                    appName: $0.appName,
                    appURL: $0.appURL,
                    icon: $0.icon,
                    windowCount: windowCounts[$0.bundleId] ?? 0,
                    isRoutingLocked: $0.bundleId == WindowInfo.unknownBundleId
                )
            }
            .sorted {
                if $0.windowCount == $1.windowCount {
                    return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
                }
                return $0.windowCount > $1.windowCount
            }
    }

    private func installedApplications() -> [InstalledApplicationRoute] {
        if let installedApplicationsCache {
            return installedApplicationsCache
        }

        let fileManager = FileManager.default
        var roots = Set<URL>()
        for domain in [FileManager.SearchPathDomainMask.localDomainMask, .systemDomainMask, .userDomainMask] {
            fileManager.urls(for: .applicationDirectory, in: domain).forEach { roots.insert($0) }
        }
        roots.insert(URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true))
        roots.insert(URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true))

        let selfBundle = Bundle.main.bundleIdentifier
        var appsByBundleId: [String: InstalledApplicationRoute] = [:]

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension.localizedCaseInsensitiveCompare("app") == .orderedSame else { continue }
                guard let appBundle = Bundle(url: url),
                      let bundleId = appBundle.bundleIdentifier,
                      bundleId != selfBundle else { continue }

                let displayName = appBundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                let bundleName = appBundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                let appName = displayName ?? bundleName ?? url.deletingPathExtension().lastPathComponent
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 24, height: 24)

                if appsByBundleId[bundleId] == nil {
                    appsByBundleId[bundleId] = InstalledApplicationRoute(
                        bundleId: bundleId,
                        appName: appName,
                        appURL: url,
                        icon: icon
                    )
                }
            }
        }

        let apps = Array(appsByBundleId.values)
        installedApplicationsCache = apps
        return apps
    }

    private func resolveFocusedRoutingWindow(in windows: [WindowInfo]) -> WindowInfo? {
        if let focusedRoutingWindow,
           windows.contains(where: { $0.windowNumber == focusedRoutingWindow.windowNumber }) {
            return focusedRoutingWindow
        }

        if let identity = targetWindowIdentity(),
           let resolved = resolveTargetWindowInfo(identity: identity, windows: windows) {
            return resolved
        }

        if let lastExternalWindowIdentity,
           let resolved = resolveTargetWindowInfo(identity: lastExternalWindowIdentity, windows: windows) {
            return resolved
        }

        return nil
    }

    private func matchedTitleRule(for window: WindowInfo) -> WindowTitleRoutingRule? {
        partitionState.titleRoutingRules.last(where: { rule in
            rule.bundleId == window.bundleId
                && !rule.title.isEmpty
                && !window.title.isEmpty
                && window.title.localizedCaseInsensitiveContains(rule.title)
        })
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
    private func addFrontmostToUnconstrained() {
        let windows = windowController.listWindows(onScreenOnly: true)
        let resolved = resolveFocusedRoutingWindow(in: windows)

        guard let window = resolved else {
            setStatus("未找到可操作的目标窗口（先点一次目标 App）", error: true)
            return
        }

        let windowTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !windowTitle.isEmpty else {
            setStatus("当前窗口标题为空，无法创建标题匹配规则", error: true)
            return
        }

        if let idx = partitionState.titleRoutingRules.firstIndex(where: {
            $0.bundleId == window.bundleId && $0.title.caseInsensitiveCompare(windowTitle) == .orderedSame
        }) {
            partitionState.titleRoutingRules[idx].type = .temporary
        } else {
            partitionState.titleRoutingRules.append(
                WindowTitleRoutingRule(
                    bundleId: window.bundleId,
                    appName: window.appName,
                    title: windowTitle,
                    type: .temporary
                )
            )
        }

        setStatus("已添加标题规则：\(windowTitle) · \(window.appName) -> 临时窗口", error: false)
        refreshWorkbench()
    }

    @objc
    private func clearUnconstrainedWindows() {
        partitionState.titleRoutingRules.removeAll()
        setStatus("已清空窗口标题规则", error: false)
        refreshWorkbench()
    }

    @objc
    private func changeAppRoutingType(_ sender: BundleRoutingTypePopupButton) {
        let selected = WindowRoutingType.allCases[safe: sender.indexOfSelectedItem] ?? .managed
        if selected == .managed {
            partitionState.appRoutingTypesByBundleId.removeValue(forKey: sender.bundleId)
        } else {
            partitionState.appRoutingTypesByBundleId[sender.bundleId] = selected
        }
        refreshWorkbench()
    }

    @objc
    private func changeTitleRuleRoutingType(_ sender: TitleRuleRoutingTypePopupButton) {
        guard let ruleId = sender.ruleId,
              let idx = partitionState.titleRoutingRules.firstIndex(where: { $0.id == ruleId }) else {
            return
        }
        let selected = WindowRoutingType.allCases[safe: sender.indexOfSelectedItem] ?? .managed
        partitionState.titleRoutingRules[idx].type = selected
        refreshWorkbench()
    }

    @objc
    private func removeTitleRoutingRule(_ sender: RoutingRuleRemoveButton) {
        guard let ruleId = sender.ruleId else { return }
        partitionState.titleRoutingRules.removeAll { $0.id == ruleId }
        setStatus("已删除窗口标题规则", error: false)
        refreshWorkbench()
    }

    @objc
    private func resetAllAppRoutingTypes() {
        partitionState.appRoutingTypesByBundleId.removeAll()
        setStatus("已重置 App 级窗口类型为管理窗口", error: false)
        refreshWorkbench()
    }

    @objc
    private func refreshWindowRoutingRules() {
        installedApplicationsCache = nil
        refreshUnconstrainedWindowList(with: windowController.listWindows(onScreenOnly: true))
        setStatus("已刷新系统 App 与窗口扫描结果", error: false)
    }

    private func refreshUnconstrainedWindowList(with windows: [WindowInfo]) {
        let unconstrainedNumbers = currentUnconstrainedWindowNumbers(in: windows)
        partitionState.unconstrainedWindowNumbers = unconstrainedNumbers

        let focusedWindow = resolveFocusedRoutingWindow(in: windows)
        focusedRoutingWindow = focusedWindow

        if let frontmost = focusedWindow {
            let focusedTitle = frontmost.title.isEmpty ? "（无标题窗口）" : frontmost.title
            unconstrainedFrontmostLabel?.stringValue = "\(focusedTitle) · \(frontmost.appName)"
            addFocusedWindowRuleButton?.title = "添加当前聚焦窗口：\(focusedTitle) · \(frontmost.appName)  【添加为临时窗口】"
            addFocusedWindowRuleButton?.isEnabled = frontmost.isControllable
                && !frontmost.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            unconstrainedFrontmostLabel?.stringValue = "-"
            addFocusedWindowRuleButton?.title = "添加当前聚焦窗口：-  【添加为临时窗口】"
            addFocusedWindowRuleButton?.isEnabled = false
        }

        if let appStack = appRoutingListStackView {
            appStack.arrangedSubviews.forEach {
                appStack.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }

            let apps = scanInstalledApps(with: windows)
            if apps.isEmpty {
                let emptyLabel = NSTextField(labelWithString: "未扫描到可管理的系统 App")
                emptyLabel.textColor = .tertiaryLabelColor
                addFullWidthArrangedSubview(emptyLabel, to: appStack)
            } else {
                for app in apps {
                    let popup = BundleRoutingTypePopupButton(frame: .zero, pullsDown: false)
                    popup.bundleId = app.bundleId
                    popup.addItems(withTitles: WindowRoutingType.allCases.map(\.title))
                    let selected = partitionState.appRoutingTypesByBundleId[app.bundleId]
                        ?? (app.bundleId == WindowInfo.unknownBundleId ? .uncontrollable : .managed)
                    if let idx = WindowRoutingType.allCases.firstIndex(of: selected) {
                        popup.selectItem(at: idx)
                    }
                    popup.isEnabled = !app.isRoutingLocked
                    if app.isRoutingLocked {
                        popup.toolTip = "自动识别的不可控窗口不可修改类型"
                    }
                    popup.target = self
                    popup.action = #selector(changeAppRoutingType(_:))
                    popup.translatesAutoresizingMaskIntoConstraints = false
                    popup.widthAnchor.constraint(equalToConstant: 120).isActive = true
                    addFullWidthArrangedSubview(makeAppRoutingRow(app: app, popup: popup), to: appStack)
                }
            }
        }

        if let titleRuleStack = titleRuleListStackView {
            titleRuleStack.arrangedSubviews.forEach {
                titleRuleStack.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }

            if partitionState.titleRoutingRules.isEmpty {
                let emptyLabel = NSTextField(labelWithString: "暂无窗口标题规则")
                emptyLabel.textColor = .tertiaryLabelColor
                addFullWidthArrangedSubview(emptyLabel, to: titleRuleStack)
            } else {
                for rule in partitionState.titleRoutingRules {
                    let popup = TitleRuleRoutingTypePopupButton(frame: .zero, pullsDown: false)
                    popup.ruleId = rule.id
                    popup.addItems(withTitles: WindowRoutingType.allCases.map(\.title))
                    if let idx = WindowRoutingType.allCases.firstIndex(of: rule.type) {
                        popup.selectItem(at: idx)
                    }
                    popup.target = self
                    popup.action = #selector(changeTitleRuleRoutingType(_:))
                    popup.translatesAutoresizingMaskIntoConstraints = false
                    popup.widthAnchor.constraint(equalToConstant: 120).isActive = true

                    let removeButton = RoutingRuleRemoveButton(title: "删除", target: self, action: #selector(removeTitleRoutingRule(_:)))
                    removeButton.ruleId = rule.id
                    removeButton.controlSize = .small
                    addFullWidthArrangedSubview(makeActionRow(
                        title: rule.title,
                        detail: rule.appName,
                        controls: [popup, removeButton]
                    ), to: titleRuleStack)
                }
            }
        }

        if let temporaryStack = temporaryMatchListStackView {
            temporaryStack.arrangedSubviews.forEach {
                temporaryStack.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }

            let matchedNonManagedWindows = windows
                .filter { unconstrainedNumbers.contains($0.windowNumber) }
                .sorted {
                    if $0.bundleId == $1.bundleId {
                        return $0.windowNumber < $1.windowNumber
                    }
                    return $0.bundleId < $1.bundleId
                }

            if matchedNonManagedWindows.isEmpty {
                let emptyLabel = NSTextField(labelWithString: "当前没有命中非管理规则的窗口")
                emptyLabel.textColor = .tertiaryLabelColor
                addFullWidthArrangedSubview(emptyLabel, to: temporaryStack)
            } else {
                for window in matchedNonManagedWindows {
                    let routingType = windowRoutingType(for: window)
                    let reason: String
                    if !window.isControllable {
                        reason = "自动识别：缺少可控 App 身份"
                    } else if let titleRule = matchedTitleRule(for: window) {
                        reason = "标题规则：\(titleRule.title)"
                    } else {
                        reason = "App 规则"
                    }

                    let title = window.title.isEmpty ? window.bundleId : window.title
                    addFullWidthArrangedSubview(makeActionRow(
                        title: title,
                        detail: window.appName,
                        controls: [],
                        trailingNote: "\(routingType.title) · \(reason)",
                        muted: !window.isControllable
                    ), to: temporaryStack)
                }
            }
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

    @objc
    private func changeWorkbenchAppearance(_ sender: NSPopUpButton) {
        let options = DesktopConfig.WorkbenchAppearance.allCases
        let selected = options[safe: sender.indexOfSelectedItem] ?? .system
        appConfig.workbenchAppearance = selected
        do {
            try appConfig.save()
            applyWorkbenchAppearance(reloadSection: true)
            setStatus("外观已切换：\(selected.title)", error: false)
        } catch {
            setStatus("保存外观失败：\(error.localizedDescription)", error: true)
        }
    }

    private func applyWorkbenchAppearance(reloadSection: Bool) {
        switch appConfig.workbenchAppearance {
        case .system:
            window?.appearance = nil
        case .titaniumLight:
            window?.appearance = NSAppearance(named: .aqua)
        case .titaniumDark:
            window?.appearance = NSAppearance(named: .darkAqua)
        }
        rootBackgroundView?.appearanceMode = appConfig.workbenchAppearance
        statusLabel?.textColor = .secondaryLabelColor
        if reloadSection {
            switchSection(currentSection, animated: false)
        }
    }

    private func shortcut(for action: WorkbenchShortcutAction) -> DesktopConfig.Shortcut {
        if action == .layoutHUD {
            return appConfig.layoutHUDShortcut
        }
        return appConfig.shortcutBindings[action.rawValue] ?? action.defaultShortcut
    }

    private func setShortcut(_ shortcut: DesktopConfig.Shortcut, for action: WorkbenchShortcutAction) {
        if action == .layoutHUD {
            appConfig.layoutHUDShortcut = shortcut
        } else {
            appConfig.shortcutBindings[action.rawValue] = shortcut
        }
        appConfig.shortcutConflictOverrides[action.rawValue] = false
    }

    private func shortcutFlagsSatisfied(flags: NSEvent.ModifierFlags, shortcut: DesktopConfig.Shortcut) -> Bool {
        if shortcut.command && !flags.contains(.command) { return false }
        if shortcut.option && !flags.contains(.option) { return false }
        if shortcut.shift && !flags.contains(.shift) { return false }
        if shortcut.control && !flags.contains(.control) { return false }
        return true
    }

    private func shortcutMatches(_ shortcut: DesktopConfig.Shortcut, flags: NSEvent.ModifierFlags, keyCode: UInt16) -> Bool {
        keyCode == shortcut.keyCode
            && flags.contains(.command) == shortcut.command
            && flags.contains(.option) == shortcut.option
            && flags.contains(.shift) == shortcut.shift
            && flags.contains(.control) == shortcut.control
    }

    private func shortcutAction(matching flags: NSEvent.ModifierFlags, keyCode: UInt16) -> WorkbenchShortcutAction? {
        WorkbenchShortcutAction.allCases.first { action in
            shortcutMatches(shortcut(for: action), flags: flags, keyCode: keyCode)
        }
    }

    private func performShortcutAction(_ action: WorkbenchShortcutAction, event: NSEvent) {
        if event.isARepeat && action == .layoutHUD {
            return
        }

        switch action {
        case .layoutHUD:
            showLayoutModeOverlay()
        case .windowSwitcher:
            showWindowSwitcher()
        case .quickDropLeftPrimary:
            quickDropFrontmost(to: .leftPrimary)
        case .quickDropRightPrimary:
            quickDropFrontmost(to: .rightPrimary)
        case .quickDropLeftSecondary:
            let shortcut = shortcut(for: action)
            let preferLower = event.modifierFlags.contains(.shift) && !shortcut.shift
            quickDropFrontmost(to: .leftSecondary, preferLowerSecondary: preferLower)
        case .quickDropRightSecondary:
            let shortcut = shortcut(for: action)
            let preferLower = event.modifierFlags.contains(.shift) && !shortcut.shift
            quickDropFrontmost(to: .rightSecondary, preferLowerSecondary: preferLower)
        case .tileLeft:
            tileFrontmost(position: .left)
        case .tileRight:
            tileFrontmost(position: .right)
        case .tileTop:
            tileFrontmost(position: .top)
        case .tileBottom:
            tileFrontmost(position: .bottom)
        }
    }

    private func captureShortcut(from event: NSEvent, for action: WorkbenchShortcutAction) {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        guard flags.contains(.command) || flags.contains(.option) || flags.contains(.shift) || flags.contains(.control) else {
            setStatus("快捷键至少需要一个修饰键：⌘ / ⌥ / ⇧ / ⌃", error: true)
            return
        }

        let shortcut = DesktopConfig.Shortcut(
            keyCode: event.keyCode,
            command: flags.contains(.command),
            option: flags.contains(.option),
            shift: flags.contains(.shift),
            control: flags.contains(.control)
        )

        setShortcut(shortcut, for: action)
        recordingShortcutAction = nil
        do {
            try appConfig.save()
            installKeyboardShortcuts()
            updateShortcutHintLabel()
            let conflict = shortcutConflict(for: action, shortcut: shortcut)
            if let conflict {
                setStatus("已录入 \(action.title)：\(shortcutDisplayText(for: shortcut))，但检测到冲突：\(conflict.title)", error: true)
            } else {
                setStatus("已录入 \(action.title)：\(shortcutDisplayText(for: shortcut))", error: false)
            }
            switchSection(.quickDrop, animated: false)
        } catch {
            setStatus("保存快捷键失败：\(error.localizedDescription)", error: true)
        }
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
            .init(title: "9", keyCode: 25),
            .init(title: "←", keyCode: 123), .init(title: "→", keyCode: 124),
            .init(title: "↓", keyCode: 125), .init(title: "↑", keyCode: 126),
            .init(title: "Space", keyCode: 49), .init(title: "Tab", keyCode: 48),
            .init(title: "Return", keyCode: 36), .init(title: "Esc", keyCode: 53),
            .init(title: "-", keyCode: 27), .init(title: "=", keyCode: 24),
            .init(title: "[", keyCode: 33), .init(title: "]", keyCode: 30),
            .init(title: ";", keyCode: 41), .init(title: "'", keyCode: 39),
            .init(title: ",", keyCode: 43), .init(title: ".", keyCode: 47),
            .init(title: "/", keyCode: 44), .init(title: "\\", keyCode: 42),
            .init(title: "`", keyCode: 50)
        ]
    }

    private func keyTitle(for keyCode: UInt16) -> String {
        shortcutKeyOptions().first(where: { $0.keyCode == keyCode })?.title ?? "KeyCode \(keyCode)"
    }

    private func shortcutDisplayText() -> String {
        shortcutDisplayText(for: shortcut(for: .layoutHUD))
    }

    private func shortcutDisplayText(for shortcut: DesktopConfig.Shortcut) -> String {
        var parts: [String] = []
        if shortcut.control { parts.append("⌃") }
        if shortcut.option { parts.append("⌥") }
        if shortcut.shift { parts.append("⇧") }
        if shortcut.command { parts.append("⌘") }
        parts.append(keyTitle(for: shortcut.keyCode))
        return parts.joined()
    }

    private func shortcutDisplayParts(for shortcut: DesktopConfig.Shortcut) -> [String] {
        var parts: [String] = []
        if shortcut.control { parts.append("⌃") }
        if shortcut.option { parts.append("⌥") }
        if shortcut.shift { parts.append("⇧") }
        if shortcut.command { parts.append("⌘") }
        parts.append(keyTitle(for: shortcut.keyCode))
        return parts
    }

    private func updateShortcutHintLabel() {
        shortcutHintLabel?.stringValue = "按住 \(shortcutDisplayText()) 显示布局九宫格"
    }

    private func shortcutConflict(for action: WorkbenchShortcutAction, shortcut candidate: DesktopConfig.Shortcut) -> ShortcutConflict? {
        if let duplicate = WorkbenchShortcutAction.allCases.first(where: { other in
            other != action && shortcutsEqual(shortcut(for: other), candidate)
        }) {
            return ShortcutConflict(title: "与「\(duplicate.title)」重复", detail: "同一个组合键已经分配给另一个 WinCtlManager 动作。")
        }

        if !canRegisterGlobalShortcut(candidate) {
            return ShortcutConflict(title: "本机快捷键已被占用", detail: "macOS 或其他 App 已占用这个组合键；你可以覆盖使用，或重新录入。")
        }

        return nil
    }

    private func shortcutsEqual(_ lhs: DesktopConfig.Shortcut, _ rhs: DesktopConfig.Shortcut) -> Bool {
        lhs.keyCode == rhs.keyCode
            && lhs.command == rhs.command
            && lhs.option == rhs.option
            && lhs.shift == rhs.shift
            && lhs.control == rhs.control
    }

    private func canRegisterGlobalShortcut(_ shortcut: DesktopConfig.Shortcut) -> Bool {
        var hotKeyRef: EventHotKeyRef?
        let signature = OSType(0x57434D48) // "WCMH"
        let hotKeyID = EventHotKeyID(signature: signature, id: UInt32(shortcut.keyCode))
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            carbonModifiers(for: shortcut),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr, let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            return true
        }
        return false
    }

    private func carbonModifiers(for shortcut: DesktopConfig.Shortcut) -> UInt32 {
        var modifiers: UInt32 = 0
        if shortcut.command { modifiers |= UInt32(cmdKey) }
        if shortcut.option { modifiers |= UInt32(optionKey) }
        if shortcut.shift { modifiers |= UInt32(shiftKey) }
        if shortcut.control { modifiers |= UInt32(controlKey) }
        return modifiers
    }

    @objc
    private func handleShortcutStatusButton(_ sender: ShortcutActionButton) {
        let action = sender.shortcutAction
        let shortcut = shortcut(for: action)
        guard let conflict = shortcutConflict(for: action, shortcut: shortcut) else {
            beginRecordingShortcut(for: action)
            return
        }

        let alert = NSAlert()
        alert.messageText = "快捷键冲突：\(action.title)"
        alert.informativeText = "\(shortcutDisplayText(for: shortcut)) \(conflict.detail)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "覆盖使用")
        alert.addButton(withTitle: "重新设置")
        alert.addButton(withTitle: "取消")
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            appConfig.shortcutConflictOverrides[action.rawValue] = true
            do {
                try appConfig.save()
                setStatus("已覆盖使用 \(action.title)：\(shortcutDisplayText(for: shortcut))", error: false)
                switchSection(.quickDrop, animated: false)
            } catch {
                setStatus("保存覆盖选择失败：\(error.localizedDescription)", error: true)
            }
        case .alertSecondButtonReturn:
            beginRecordingShortcut(for: action)
        default:
            break
        }
    }

    private func beginRecordingShortcut(for action: WorkbenchShortcutAction) {
        recordingShortcutAction = action
        setStatus("正在录入「\(action.title)」：请直接按下新的组合键，例如 ⌘⇧↑", error: false)
        switchSection(.quickDrop, animated: false)
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
            let layout = try layoutCoordinator.saveCurrentDesktop(name: name, description: description)
            selectedLayoutName = name
            let displayNote = layout.preferredDisplay.map { " · 默认屏幕：\($0.name)" } ?? ""
            setStatus("已保存布局：\(name)\(displayNote)", error: false)
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
                self?.selectedLayoutName = selectedName
                self?.layoutNameField?.stringValue = selectedName
                self?.wakeLayout(named: selectedName)
            }
            card.onDelete = { [weak self] selectedName in
                self?.confirmDeleteLayout(named: selectedName)
            }
            noteStackView.addArrangedSubview(card)
        }

        // Keep document width in sync with content to prevent Auto Layout conflicts
        // inside NSStackView when cards have fixed widths.
        let cardWidth: CGFloat = LayoutNoteCardView.cardSize.width
        let spacing: CGFloat = noteStackView.spacing
        let insets = noteStackView.edgeInsets
        let count = CGFloat(layouts.count)
        let cardsTotal = count * cardWidth + max(0, count - 1) * spacing
        let minimumVisibleWidth = noteScrollView?.contentSize.width ?? 420
        let targetWidth = max(minimumVisibleWidth, insets.left + cardsTotal + insets.right)
        noteStackView.frame = NSRect(x: 0, y: 0, width: targetWidth, height: LayoutNoteCardView.cardSize.height + 16)
    }

    private func confirmDeleteLayout(named name: String) {
        let alert = NSAlert()
        alert.messageText = "删除布局「\(name)」？"
        alert.informativeText = "这个操作会移除已保存的布局文件，不能在应用内撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.deleteLayout(named: name)
        }

        if let window {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    private func deleteLayout(named name: String) {
        do {
            try layoutCoordinator.deleteDesktop(name: name)
            if selectedLayoutName == name {
                selectedLayoutName = nil
                layoutNameField?.stringValue = "workspace_\(dateSuffix())"
            }
            setStatus("已删除布局：\(name)", error: false)
            reloadLayoutCards()
        } catch {
            setStatus("删除布局失败：\(error.localizedDescription)", error: true)
        }
    }

    private func wakeLayout(named name: String) {
        let displays = screenManager.displaySnapshots()
        if displays.count > 1 {
            do {
                let layout = try layoutCoordinator.loadDesktop(name: name)
                showDisplayWakePanel(layout: layout, displays: displays)
            } catch {
                setStatus(error.localizedDescription, error: true)
            }
            return
        }

        wakeLayout(named: name, targetDisplayId: displays.first?.id)
    }

    private func wakeLayout(named name: String, targetDisplayId: UInt32?) {
        do {
            try layoutCoordinator.wakeDesktop(name: name, targetDisplayId: targetDisplayId)
            partitionModelInitialized = true
            closeDisplayWakePanel()
            setStatus("已唤醒布局：\(name)", error: false)
            refreshWorkbench()
        } catch {
            setStatus(error.localizedDescription, error: true)
        }
    }

    private func showDisplayWakePanel(layout: DesktopLayout, displays: [LayoutDisplaySnapshot]) {
        closeDisplayWakePanel()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "选择唤醒屏幕"
        panel.isReleasedWhenClosed = false

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .withinWindow
        effect.state = .active
        effect.translatesAutoresizingMaskIntoConstraints = false

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 20, right: 24)
        root.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            root.topAnchor.constraint(equalTo: effect.topAnchor),
            root.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])

        let title = NSTextField(labelWithString: "唤醒「\(layout.name)」到哪个屏幕？")
        title.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        title.alignment = .left
        root.addArrangedSubview(title)

        let subtitle = NSTextField(labelWithString: "保存布局时的 preferredDisplayId 会作为默认提示；点击任意屏幕即可恢复浏览器 URL 并排布窗口。")
        subtitle.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .left
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.maximumNumberOfLines = 2
        root.addArrangedSubview(subtitle)

        let mapView = DisplayWakeMapView(displays: displays, preferredDisplayId: layout.preferredDisplay?.id)
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.heightAnchor.constraint(equalToConstant: 210).isActive = true
        mapView.onSelect = { [weak self] display in
            self?.wakeLayout(named: layout.name, targetDisplayId: display.id)
        }
        root.addArrangedSubview(mapView)

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 10
        let spacer = NSView()
        actions.addArrangedSubview(spacer)
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelDisplayWakeSelection))
        cancel.bezelStyle = .rounded
        actions.addArrangedSubview(cancel)
        root.addArrangedSubview(actions)

        panel.contentView = effect
        displayWakePanel = panel
        if let window {
            window.beginSheet(panel)
        } else {
            panel.center()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    @objc
    private func cancelDisplayWakeSelection() {
        closeDisplayWakePanel()
    }

    private func closeDisplayWakePanel() {
        guard let panel = displayWakePanel else { return }
        if let sheetParent = panel.sheetParent {
            sheetParent.endSheet(panel)
        } else {
            panel.close()
        }
        displayWakePanel = nil
    }

    private func makeSidebarView() -> NSView {
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .withinWindow
        sidebar.state = .active
        sidebar.wantsLayer = true
        sidebar.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.10).cgColor
        sidebar.layer?.borderWidth = 0.5
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 0
        container.edgeInsets = NSEdgeInsets(top: 26, left: 0, bottom: 20, right: 0)
        container.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            container.topAnchor.constraint(equalTo: sidebar.topAnchor),
            container.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor)
        ])

        let appTitle = NSTextField(labelWithString: "WinCtlManager")
        appTitle.font = NSFont.systemFont(ofSize: 19, weight: .semibold)
        appTitle.alignment = .left
        appTitle.textColor = .labelColor
        let titleRow = NSStackView()
        titleRow.orientation = .vertical
        titleRow.spacing = 4
        titleRow.edgeInsets = NSEdgeInsets(top: 0, left: 22, bottom: 0, right: 20)
        titleRow.addArrangedSubview(appTitle)

        let subtitle = NSTextField(labelWithString: "Desktop workbench")
        subtitle.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .left
        titleRow.addArrangedSubview(subtitle)
        container.addArrangedSubview(titleRow)

        let spacer1 = NSView()
        spacer1.translatesAutoresizingMaskIntoConstraints = false
        spacer1.heightAnchor.constraint(equalToConstant: 22).isActive = true
        container.addArrangedSubview(spacer1)

        let navStack = NSStackView()
        navStack.orientation = .vertical
        navStack.spacing = 6
        navStack.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
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
        case .quickDrop: newPanel = makeQuickDropPanel()
        case .unconstrained: newPanel = makeUnconstrainedWindowsPanel()
        case .previews: newPanel = makeWindowPreviewsPanel()
        case .liquidGlass: newPanel = makeLiquidGlassPanel()
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
            newPanel.bottomAnchor.constraint(lessThanOrEqualTo: contentContainer!.bottomAnchor)
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
        let root = makePanelRoot()
        addFullWidthArrangedSubview(makeSectionTitle("布局", subtitle: "保存、切换与调整当前桌面分区。"), to: root)

        var heroRows: [NSView] = []
        if let nameField = layoutNameField {
            nameField.translatesAutoresizingMaskIntoConstraints = false
            nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
            let saveBtn = makeButton("保存当前布局", action: #selector(saveCurrentLayout))
            saveBtn.contentTintColor = .controlAccentColor
            let saveControls = [nameField, saveBtn]
            heroRows.append(makeActionRow(
                title: "项目名称",
                detail: selectedLayoutName ?? "当前工作区快照",
                controls: saveControls
            ))
        }

        var modeControls: [NSView] = []
        if let mergeControl { modeControls.append(mergeControl) }
        let overlayToggle = makeButton("桌面分区柄：显示", action: #selector(toggleDesktopOverlayEditing))
        desktopOverlayToggleButton = overlayToggle
        modeControls.append(overlayToggle)
        heroRows.append(makeActionRow(
            title: "布局模式",
            detail: mergeMode.title,
            controls: modeControls,
            trailingNote: "\(partitionState.stackThreshold) 阈值"
        ))

        heroRows.append(makeActionRow(
            title: "分区扫描",
            detail: "重新计算窗口归属。",
            controls: [makeButton("立即扫描", action: #selector(runAutoScan))]
        ))

        let statusStack = NSStackView()
        statusStack.orientation = .horizontal
        statusStack.spacing = 12
        statusStack.alignment = .centerY
        applyFullWidthAlignment(to: statusStack)
        if let statusLabel {
            statusLabel.lineBreakMode = .byTruncatingTail
            statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            statusStack.addArrangedSubview(statusLabel)
        }
        let shortcutHintLabel = NSTextField(labelWithString: "")
        shortcutHintLabel.textColor = .secondaryLabelColor
        shortcutHintLabel.font = NSFont.systemFont(ofSize: 11)
        self.shortcutHintLabel = shortcutHintLabel
        updateShortcutHintLabel()
        statusStack.addArrangedSubview(shortcutHintLabel)
        heroRows.append(statusStack)

        addFullWidthArrangedSubview(makeSectionGroup(
            title: "当前桌面",
            subtitle: "把当前布局的保存、模式切换和状态信息集中到同一组，减少零碎面板。",
            views: heroRows
        ), to: root)

        if let desktopView {
            desktopViewAspectConstraint?.isActive = false
            let aspectConstraint = desktopView.heightAnchor.constraint(equalTo: desktopView.widthAnchor, multiplier: desktopView.heightToWidthRatio)
            aspectConstraint.priority = .required
            aspectConstraint.isActive = true
            desktopViewAspectConstraint = aspectConstraint

            addFullWidthArrangedSubview(makeGlassCard(
                containing: desktopView,
                insets: WorkbenchChrome.compactCardInsets
            ), to: root)
        }

        if let noteScrollView {
            addFullWidthArrangedSubview(makeGlassCard(
                containing: noteScrollView,
                insets: WorkbenchChrome.compactCardInsets
            ), to: root)
        }

        return root
    }

    private func makeStacksPanel() -> NSView {
        let root = makePanelRoot()
        addFullWidthArrangedSubview(makeSectionTitle("堆叠", subtitle: "把前台窗口收纳到固定区域或标签桶。"), to: root)

        let tileControls = [
            makeButton("左半屏", action: #selector(tileFrontmostLeft)),
            makeButton("右半屏", action: #selector(tileFrontmostRight)),
            makeButton("上半屏", action: #selector(tileFrontmostTop)),
            makeButton("下半屏", action: #selector(tileFrontmostBottom))
        ]
        addFullWidthArrangedSubview(makeSectionGroup(
            title: "快捷平铺",
            subtitle: "保留桌面窗口管理的方向键直觉，把常用动作合并在同一组。",
            views: [makeActionRow(
                title: "窗口平铺",
                detail: "Command + Option + 方向键",
                controls: tileControls
            )]
        ), to: root)

        let bucketToggle = NSButton(checkboxWithTitle: "左半屏使用桶堆叠", target: self, action: #selector(toggleLeftBucket))
        bucketToggle.state = leftBucketEnabled ? .on : .off
        addFullWidthArrangedSubview(makeSectionGroup(
            title: "左侧标签桶",
            subtitle: "把左半屏从普通平铺切换为可切换标签桶。",
            views: [makeActionRow(
                title: "左侧标签桶",
                detail: leftBucketEnabled ? "当前开启" : "当前关闭",
                controls: [makeButton("加入左桶", action: #selector(addFrontmostToLeftBucket)), bucketToggle]
            )]
        ), to: root)

        let stacks = stackManager.listStacks()
        let activeViews: [NSView]
        if stacks.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "暂无活跃堆叠")
            emptyLabel.textColor = .tertiaryLabelColor
            activeViews = [emptyLabel]
        } else {
            activeViews = stacks.map { stack in
                makeActionRow(
                    title: stack.name,
                    detail: stack.windows.first?.title ?? "窗口堆叠",
                    controls: [],
                    trailingNote: "\(stack.windows.count) 窗口"
                )
            }
        }
        addFullWidthArrangedSubview(makeSectionGroup(
            title: "活跃堆叠",
            subtitle: "用连续列表显示当前堆叠状态，避免每条记录单独漂浮。",
            views: activeViews
        ), to: root)

        return root
    }

    private func makeQuickDropPanel() -> NSView {
        let root = makePanelRoot()
        addFullWidthArrangedSubview(makeSectionTitle(
            "快捷键",
            subtitle: "点击右侧 ↻ 重新录入；检测到本机或内部冲突时显示 ❗️，可选择覆盖使用或重新设置。"
        ), to: root)

        let groups: [(title: String, note: String, actions: [WorkbenchShortcutAction])] = [
            ("窗口搜索", "打开全局 Switcher，搜索当前可控窗口并用 Return 聚焦。", [
                .windowSwitcher
            ]),
            ("窗口投放", "次块默认上半；按住 Shift 执行动作时会改投下半区。", [
                .quickDropLeftPrimary,
                .quickDropRightPrimary,
                .quickDropLeftSecondary,
                .quickDropRightSecondary
            ]),
            ("键盘平铺", "保留原来的方向键直觉，也可以改成你自己的组合。", [
                .tileLeft,
                .tileRight,
                .tileTop,
                .tileBottom
            ]),
            ("布局辅助", "HUD 是按住式快捷键，松开主按键后自动隐藏。", [
                .layoutHUD
            ])
        ]

        for group in groups {
            let rows: [NSView] = group.actions.map { makeShortcutActionRow(for: $0) }
            addFullWidthArrangedSubview(makeSectionGroup(
                title: group.title,
                subtitle: group.note,
                views: rows
            ), to: root)
        }

        if let statusLabel {
            addFullWidthArrangedSubview(statusLabel, to: root)
        }

        return root
    }

    private func makeUnconstrainedWindowsPanel() -> NSView {
        let root = makePanelRoot()
        addFullWidthArrangedSubview(makeSectionTitle("窗口类型策略", subtitle: "App 是基础规则，窗口标题规则优先级更高；不可控窗口会自动排除出布局管理。"), to: root)

        let frontmostLabel = NSTextField(labelWithString: "-")
        frontmostLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        frontmostLabel.textColor = .secondaryLabelColor
        frontmostLabel.alignment = .left
        unconstrainedFrontmostLabel = frontmostLabel
        let focusedButton = makeButton("添加当前聚焦窗口：-  【添加为临时窗口】", action: #selector(addFrontmostToUnconstrained))
        focusedButton.lineBreakMode = .byTruncatingMiddle
        addFocusedWindowRuleButton = focusedButton

        addFullWidthArrangedSubview(makeSectionGroup(
            title: "基础操作",
            subtitle: "先扫描 App 规则，再用当前聚焦窗口快速追加更高优先级的标题覆盖规则。",
            views: [
                makeActionRow(
                    title: "App 基础规则",
                    detail: "扫描系统中的 App 并设置默认窗口类型",
                    controls: [
                        makeButton("刷新扫描", action: #selector(refreshWindowRoutingRules)),
                        makeButton("重置 App 类型", action: #selector(resetAllAppRoutingTypes))
                    ]
                ),
                makeActionRow(
                    title: "当前聚焦窗口",
                    detail: "取 WinCtlManager 操作窗口之外的最顶层窗口；点击后添加标题覆盖规则",
                    controls: [frontmostLabel, focusedButton]
                )
            ]
        ), to: root)

        let appRoutingStack = NSStackView()
        appRoutingStack.orientation = .vertical
        appRoutingStack.spacing = 8
        appRoutingStack.alignment = .width
        applyFullWidthAlignment(to: appRoutingStack)
        appRoutingListStackView = appRoutingStack
        addFullWidthArrangedSubview(makeSectionGroup(
            title: "App 基础规则",
            subtitle: "用连续列表管理每个 App 的默认窗口类型。",
            views: [makeBoundedScrollView(containing: appRoutingStack, height: 320)],
            insets: WorkbenchChrome.compactCardInsets
        ), to: root)

        addFullWidthArrangedSubview(makeActionRow(
            title: "窗口标题规则",
            detail: "标题规则优先于 App 规则",
            controls: [makeButton("清空标题规则", action: #selector(clearUnconstrainedWindows))]
        ), to: root)

        let titleRuleStack = NSStackView()
        titleRuleStack.orientation = .vertical
        titleRuleStack.spacing = 8
        titleRuleStack.alignment = .width
        applyFullWidthAlignment(to: titleRuleStack)
        titleRuleListStackView = titleRuleStack
        addFullWidthArrangedSubview(makeSectionGroup(
            title: "窗口标题规则",
            subtitle: "匹配 App 与窗口标题，对单个窗口做更精细覆盖。",
            views: [titleRuleStack]
        ), to: root)

        let temporaryMatchStack = NSStackView()
        temporaryMatchStack.orientation = .vertical
        temporaryMatchStack.spacing = 8
        temporaryMatchStack.alignment = .width
        applyFullWidthAlignment(to: temporaryMatchStack)
        temporaryMatchListStackView = temporaryMatchStack
        addFullWidthArrangedSubview(makeSectionGroup(
            title: "当前命中非管理规则的窗口",
            subtitle: "实时查看哪些窗口被 App 规则或标题规则排除出布局管理。",
            views: [temporaryMatchStack]
        ), to: root)

        refreshUnconstrainedWindowList(with: windowController.listWindows(onScreenOnly: true))
        return root
    }

    private func makeWindowPreviewsPanel() -> NSView {
        let root = makePanelRoot()
        addFullWidthArrangedSubview(makeSectionTitle("窗口预览", subtitle: "Dock Preview 的底层预览管线：先在 Workbench 中检查当前窗口缩略图。"), to: root)

        let screenStatus = NSTextField(labelWithString: screenRecordingPermissionStatusText())
        screenStatus.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        screenStatus.textColor = screenRecordingPermissionStatusColor()
        screenStatus.alignment = .left
        screenStatus.lineBreakMode = .byWordWrapping
        screenStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        screenRecordingPermissionStatusLabel = screenStatus

        addFullWidthArrangedSubview(makeSectionGroup(
            title: "预览权限",
            subtitle: "窗口缩略图依赖屏幕录制权限；未授权时只能显示窗口标题和 App 名。",
            views: [makeActionRow(
                title: "屏幕录制权限",
                detail: "用于生成窗口缩略图，不会保存截图到磁盘。",
                controls: [
                    screenStatus,
                    makeButton("请求权限", action: #selector(requestScreenRecordingPermission)),
                    makeButton("刷新预览", action: #selector(refreshWindowPreviews))
                ]
            )]
        ), to: root)

        let windows = windowController.listWindows(onScreenOnly: true)
            .filter(\.isControllable)
            .sorted { lhs, rhs in
                if lhs.appName == rhs.appName {
                    return lhs.windowNumber < rhs.windowNumber
                }
                return lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
            }
        let snapshots = previewProvider.snapshots(for: windows)

        if snapshots.isEmpty {
            addFullWidthArrangedSubview(makeSectionGroup(
                title: "当前窗口",
                views: [makeEmptyStateLabel("没有找到可预览的窗口。")]
            ), to: root)
            return root
        }

        let grid = NSGridView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 14
        grid.columnSpacing = 14
        grid.xPlacement = .fill
        grid.yPlacement = .fill

        for pairStart in stride(from: 0, to: snapshots.count, by: 2) {
            let left = WindowPreviewCardView(snapshot: snapshots[pairStart])
            left.onFocus = { [weak self] window in
                self?.focusPreviewWindow(window)
            }

            let right: NSView
            if pairStart + 1 < snapshots.count {
                let card = WindowPreviewCardView(snapshot: snapshots[pairStart + 1])
                card.onFocus = { [weak self] window in
                    self?.focusPreviewWindow(window)
                }
                right = card
            } else {
                right = NSView()
            }

            let row = grid.addRow(with: [left, right])
            row.height = 210
        }

        for columnIndex in 0..<grid.numberOfColumns {
            grid.column(at: columnIndex).width = 360
        }

        addFullWidthArrangedSubview(makeSectionGroup(
            title: "当前窗口",
            subtitle: "点击预览卡片可聚焦对应窗口；这一步后续会接入 Switcher 和 Dock hover。",
            views: [grid]
        ), to: root)

        return root
    }

    private func makeLiquidGlassPanel() -> NSView {
        let root = makePanelRoot()
        addFullWidthArrangedSubview(makeSectionTitle(
            "液态玻璃",
            subtitle: "选择桌面堆叠标签栏的 GlassStyle；只影响桌面 stack 标签栏，不改变操作页面布局。"
        ), to: root)

        addFullWidthArrangedSubview(makeSectionGroup(
            title: "使用说明",
            views: [
                makeActionRow(title: "控制层限定", detail: "GlassStyle 只用于浮在窗口上方的标签栏控制层。", controls: []),
                makeActionRow(title: "即时预览", detail: "点击样式卡后立即保存，并刷新当前桌面上的 stack 标签栏。", controls: []),
                makeActionRow(title: "可读优先", detail: "复杂桌面建议用标准磨砂或深烟灰，干净背景可以用清透玻璃。", controls: [])
            ]
        ), to: root)

        let grid = NSGridView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        applyFullWidthAlignment(to: grid)

        let styles = DesktopConfig.StackTabGlassStyle.allCases
        for rowIndex in stride(from: 0, to: styles.count, by: 2) {
            let leftStyle = styles[rowIndex]
            let left = StackTabGlassStylePreviewCard(
                style: leftStyle,
                selected: leftStyle == appConfig.stackTabGlassStyle
            )
            left.onSelect = { [weak self] style in
                self?.selectStackTabGlassStyle(style)
            }

            let right: NSView
            if rowIndex + 1 < styles.count {
                let rightStyle = styles[rowIndex + 1]
                let card = StackTabGlassStylePreviewCard(
                    style: rightStyle,
                    selected: rightStyle == appConfig.stackTabGlassStyle
                )
                card.onSelect = { [weak self] style in
                    self?.selectStackTabGlassStyle(style)
                }
                right = card
            } else {
                right = NSView()
            }

            let row = grid.addRow(with: [left, right])
            row.height = 148
        }
        for columnIndex in 0..<grid.numberOfColumns {
            grid.column(at: columnIndex).width = 320
        }

        addFullWidthArrangedSubview(makeSectionGroup(
            title: "GlassStyle 选择",
            views: [grid]
        ), to: root)

        if let statusLabel {
            addFullWidthArrangedSubview(statusLabel, to: root)
        }

        return root
    }

    private func selectStackTabGlassStyle(_ style: DesktopConfig.StackTabGlassStyle) {
        appConfig.stackTabGlassStyle = style
        do {
            try appConfig.save()
            refreshAllStackPanels()
            switchSection(.liquidGlass, animated: false)
            setStatus("GlassStyle 已切换：\(style.title)", error: false)
        } catch {
            setStatus("保存 GlassStyle 失败：\(error.localizedDescription)", error: true)
        }
    }

    private func makeSettingsPanel() -> NSView {
        let root = makePanelRoot()
        addFullWidthArrangedSubview(makeSectionTitle("设置", subtitle: "外观、快捷键和高级工具。"), to: root)

        let permissionStatus = NSTextField(labelWithString: accessibilityPermissionStatusText())
        permissionStatus.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        permissionStatus.textColor = accessibilityPermissionStatusColor()
        permissionStatus.alignment = .left
        permissionStatus.lineBreakMode = .byWordWrapping
        permissionStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        accessibilityPermissionStatusLabel = permissionStatus

        let dockPreviewStatus = NSTextField(labelWithString: dockPreviewStatusText())
        dockPreviewStatus.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        dockPreviewStatus.textColor = dockPreviewStatusColor()
        dockPreviewStatus.alignment = .left
        dockPreviewStatus.lineBreakMode = .byWordWrapping
        dockPreviewStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        dockPreviewStatusLabel = dockPreviewStatus

        let dockPreviewToggle = NSButton(
            checkboxWithTitle: "启用 Dock Preview",
            target: self,
            action: #selector(toggleDockPreviewFromCheckbox(_:))
        )
        dockPreviewToggle.state = appConfig.dockPreviewEnabled ? .on : .off

        addFullWidthArrangedSubview(makeSectionGroup(
            title: "权限健康",
            subtitle: "窗口管理依赖 macOS 辅助功能权限；屏幕录制权限会在预览管线阶段启用。",
            views: [
                makeActionRow(
                    title: "辅助功能权限",
                    detail: "允许 WinCtlManager 读取并控制窗口位置和大小。",
                    controls: [
                        permissionStatus,
                        makeButton("重新检测", action: #selector(refreshPermissionStatusAction)),
                        makeButton("打开系统设置", action: #selector(openAccessibilitySettings))
                    ]
                ),
                makeActionRow(
                    title: "屏幕录制权限",
                    detail: "用于窗口缩略图、Switcher 和未来 Dock Preview。",
                    controls: [
                        NSTextField(labelWithString: screenRecordingPermissionStatusText()),
                        makeButton("打开预览", action: #selector(showWindowPreviewsSection)),
                        makeButton("请求权限", action: #selector(requestScreenRecordingPermission))
                    ]
                ),
                makeActionRow(
                    title: "Dock Preview",
                    detail: "鼠标悬停在 macOS Dock 区域时，显示对应 App 的窗口缩略图。",
                    controls: [
                        dockPreviewStatus,
                        dockPreviewToggle
                    ]
                )
            ]
        ), to: root)

        let loginStatus = NSTextField(labelWithString: launchAtLoginStatusText())
        loginStatus.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        loginStatus.textColor = launchAtLoginStatusColor()
        loginStatus.alignment = .left
        loginStatus.lineBreakMode = .byWordWrapping
        loginStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        launchAtLoginStatusLabel = loginStatus

        addFullWidthArrangedSubview(makeSectionGroup(
            title: "常驻启动",
            subtitle: "让 WinCtlManager 登录后自动进入菜单栏，适合日常窗口编排。",
            views: [
                makeActionRow(
                    title: "开机启动",
                    detail: "需要以 .app bundle 方式运行；开发期裸 swift run 可能无法注册。",
                    controls: [
                        loginStatus,
                        makeButton("启用", action: #selector(enableLaunchAtLogin)),
                        makeButton("关闭", action: #selector(disableLaunchAtLogin)),
                        makeButton("刷新", action: #selector(refreshLaunchAtLoginStatusAction))
                    ]
                )
            ]
        ), to: root)

        let appearancePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        appearancePopup.addItems(withTitles: DesktopConfig.WorkbenchAppearance.allCases.map(\.title))
        if let idx = DesktopConfig.WorkbenchAppearance.allCases.firstIndex(of: appConfig.workbenchAppearance) {
            appearancePopup.selectItem(at: idx)
        }
        appearancePopup.target = self
        appearancePopup.action = #selector(changeWorkbenchAppearance(_:))
        appearancePopup.translatesAutoresizingMaskIntoConstraints = false
        appearancePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        self.appearancePopup = appearancePopup
        addFullWidthArrangedSubview(makeSectionGroup(
            title: "外观",
            subtitle: "钛金属浅色 / 深色 / 跟随系统。",
            views: [makeActionRow(
                title: "Workbench 外观",
                detail: "切换主工作台的整体 chrome 与钛金属底色。",
                controls: [appearancePopup]
            )]
        ), to: root)

        addFullWidthArrangedSubview(makeSectionGroup(
            title: "快捷键",
            subtitle: "HUD、窗口投放和平铺快捷键已移到单独页面统一配置。",
            views: [makeActionRow(
                title: "统一快捷键配置",
                detail: "集中在侧边栏\"快捷键\"页面中维护。",
                controls: [makeButton("打开快捷键", action: #selector(showShortcutSection))]
            )]
        ), to: root)

        return root
    }

    private func accessibilityPermissionStatusText() -> String {
        windowController.hasAccessibilityPermission() ? "已授权" : "未授权"
    }

    private func accessibilityPermissionStatusColor() -> NSColor {
        windowController.hasAccessibilityPermission() ? .systemGreen : .systemOrange
    }

    @objc
    private func refreshPermissionStatusAction() {
        refreshPermissionStatus()
    }

    private func refreshPermissionStatus() {
        let hasPermission = windowController.hasAccessibilityPermission()
        accessibilityPermissionStatusLabel?.stringValue = hasPermission ? "已授权" : "未授权"
        accessibilityPermissionStatusLabel?.textColor = hasPermission ? .systemGreen : .systemOrange
        let message = hasPermission
            ? "辅助功能权限正常"
            : "辅助功能权限未授权，请在系统设置中允许 WinCtlManager"
        setStatus(message, error: !hasPermission)
    }

    @objc
    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        _ = windowController.ensureAccessibilityPermission(prompt: true)
        refreshPermissionStatus()
    }

    private func launchAtLoginStatusText() -> String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "已启用"
        case .notRegistered:
            return "未启用"
        case .requiresApproval:
            return "需要系统批准"
        case .notFound:
            return "未找到 App Bundle"
        @unknown default:
            return "未知状态"
        }
    }

    private func launchAtLoginStatusColor() -> NSColor {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .systemGreen
        case .requiresApproval:
            return .systemOrange
        case .notRegistered, .notFound:
            return .secondaryLabelColor
        @unknown default:
            return .secondaryLabelColor
        }
    }

    @objc
    private func enableLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
            refreshLaunchAtLoginStatus()
            setStatus("已启用开机启动", error: false)
        } catch {
            refreshLaunchAtLoginStatus()
            setStatus("启用开机启动失败：\(error.localizedDescription)", error: true)
        }
    }

    @objc
    private func disableLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLoginStatus()
            setStatus("已关闭开机启动", error: false)
        } catch {
            refreshLaunchAtLoginStatus()
            setStatus("关闭开机启动失败：\(error.localizedDescription)", error: true)
        }
    }

    @objc
    private func refreshLaunchAtLoginStatusAction() {
        refreshLaunchAtLoginStatus()
        setStatus("已刷新开机启动状态：\(launchAtLoginStatusText())", error: false)
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLoginStatusLabel?.stringValue = launchAtLoginStatusText()
        launchAtLoginStatusLabel?.textColor = launchAtLoginStatusColor()
    }

    private func screenRecordingPermissionStatusText() -> String {
        previewProvider.hasScreenRecordingPermission() ? "已授权" : "未授权"
    }

    private func screenRecordingPermissionStatusColor() -> NSColor {
        previewProvider.hasScreenRecordingPermission() ? .systemGreen : .systemOrange
    }

    private func dockPreviewStatusText() -> String {
        appConfig.dockPreviewEnabled ? "已开启" : "已关闭"
    }

    private func dockPreviewStatusColor() -> NSColor {
        appConfig.dockPreviewEnabled ? .systemGreen : .secondaryLabelColor
    }

    @objc
    private func toggleDockPreviewFromCheckbox(_ sender: NSButton) {
        setDockPreviewEnabled(sender.state == .on)
    }

    private func setDockPreviewEnabled(_ enabled: Bool) {
        appConfig.dockPreviewEnabled = enabled
        do {
            try appConfig.save()
            refreshDockPreviewStatus()
            if !enabled {
                hideDockPreviewPanel()
            }
            setStatus(enabled ? "Dock Preview 已开启；移动到 Dock 上方即可预览窗口" : "Dock Preview 已关闭", error: false)
        } catch {
            setStatus("保存 Dock Preview 设置失败：\(error.localizedDescription)", error: true)
        }
    }

    private func refreshDockPreviewStatus() {
        dockPreviewStatusLabel?.stringValue = dockPreviewStatusText()
        dockPreviewStatusLabel?.textColor = dockPreviewStatusColor()
        dockPreviewMenuItem?.title = dockPreviewMenuTitle()
    }

    @objc
    private func requestScreenRecordingPermission() {
        _ = previewProvider.requestScreenRecordingPermission()
        refreshScreenRecordingPermissionStatus()
        setStatus("已请求屏幕录制权限；如刚授权，请重新打开 App 以刷新系统授权状态", error: !previewProvider.hasScreenRecordingPermission())
    }

    private func refreshScreenRecordingPermissionStatus() {
        screenRecordingPermissionStatusLabel?.stringValue = screenRecordingPermissionStatusText()
        screenRecordingPermissionStatusLabel?.textColor = screenRecordingPermissionStatusColor()
    }

    @objc
    private func refreshWindowPreviews() {
        refreshScreenRecordingPermissionStatus()
        switchSection(.previews, animated: false)
        setStatus("已刷新窗口预览", error: false)
    }

    @objc
    private func showWindowPreviewsSection() {
        switchSection(.previews, animated: true)
    }

    private func focusPreviewWindow(_ window: WindowInfo) {
        do {
            try windowController.raiseWindow(bundleId: window.bundleId, windowNumber: window.windowNumber)
            try? stackManager.syncActiveStackWindow(windowNumber: window.windowNumber)
            setStatus("已聚焦 \(window.title.isEmpty ? window.appName : window.title)", error: false)
            refreshWorkbench()
        } catch {
            setStatus("聚焦预览窗口失败：\(error.localizedDescription)", error: true)
        }
    }

    @objc
    private func showWindowSwitcher() {
        hideDockPreviewPanel()
        windowSwitcherAllResults = buildWindowSwitcherResults()
        windowSwitcherSelectedIndex = 0

        let panel = windowSwitcherPanel ?? makeWindowSwitcherPanel()
        windowSwitcherPanel = panel
        panel.contentView = makeWindowSwitcherContent()
        panel.setContentSize(NSSize(width: 720, height: 560))
        centerWindowSwitcherPanel(panel)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.level = .floating
        if let field = windowSwitcherSearchField {
            panel.makeFirstResponder(field)
        }
        applyWindowSwitcherFilter()
        setStatus("窗口搜索已打开：输入 App、标题、URL 或窗口编号", error: false)
    }

    private func makeWindowSwitcherPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Window Switcher"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func centerWindowSwitcherPanel(_ panel: NSPanel) {
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = panel.frame.size
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        )
        panel.setFrameOrigin(origin)
    }

    private func makeWindowSwitcherContent() -> NSView {
        let root = NSVisualEffectView()
        root.material = .menu
        root.blendingMode = .withinWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = 26
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        root.layer?.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
        root.layer?.borderWidth = 0.8
        root.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        root.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 22, bottom: 22, right: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        let searchField = WindowSwitcherSearchField()
        searchField.placeholderString = "搜索窗口、App、URL 或 #编号"
        searchField.font = NSFont.systemFont(ofSize: 18, weight: .medium)
        searchField.controlSize = .large
        searchField.wantsLayer = true
        searchField.layer?.cornerRadius = 14
        searchField.layer?.cornerCurve = .continuous
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.heightAnchor.constraint(equalToConstant: 46).isActive = true
        searchField.onMoveSelection = { [weak self] delta in
            self?.moveWindowSwitcherSelection(delta)
        }
        searchField.onCommit = { [weak self] in
            self?.focusSelectedWindowSwitcherResult()
        }
        searchField.onCancel = { [weak self] in
            self?.windowSwitcherPanel?.orderOut(nil)
        }
        windowSwitcherSearchField = searchField
        stack.addArrangedSubview(searchField)

        let hint = NSTextField(labelWithString: "↑↓ 选择 · Return 聚焦 · Esc 关闭 · 当前仅索引窗口和浏览器 active tab")
        hint.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .left
        hint.lineBreakMode = .byTruncatingTail
        stack.addArrangedSubview(hint)

        let resultsStack = NSStackView()
        resultsStack.orientation = .vertical
        resultsStack.spacing = 6
        resultsStack.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        resultsStack.translatesAutoresizingMaskIntoConstraints = false
        windowSwitcherResultsStackView = resultsStack

        let documentContainer = NSView()
        documentContainer.translatesAutoresizingMaskIntoConstraints = false
        documentContainer.addSubview(resultsStack)
        NSLayoutConstraint.activate([
            resultsStack.leadingAnchor.constraint(equalTo: documentContainer.leadingAnchor),
            resultsStack.trailingAnchor.constraint(equalTo: documentContainer.trailingAnchor),
            resultsStack.topAnchor.constraint(equalTo: documentContainer.topAnchor),
            resultsStack.bottomAnchor.constraint(equalTo: documentContainer.bottomAnchor)
        ])

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = documentContainer
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 440).isActive = true
        stack.addArrangedSubview(scrollView)
        documentContainer.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor).isActive = true

        return root
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === windowSwitcherSearchField else { return }
        applyWindowSwitcherFilter()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === windowSwitcherSearchField else { return false }
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            moveWindowSwitcherSelection(-1)
            return true
        }
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            moveWindowSwitcherSelection(1)
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            focusSelectedWindowSwitcherResult()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            windowSwitcherPanel?.orderOut(nil)
            return true
        }
        return false
    }

    private func buildWindowSwitcherResults() -> [WindowSwitcherResult] {
        windowController.listWindows(onScreenOnly: true)
            .filter(\.isControllable)
            .map { window in
                let page = browserRestorer.browserKind(for: window.bundleId).flatMap { _ in
                    browserRestorer.capturedPage(for: window.bundleId, windowTitle: window.title)
                }
                return WindowSwitcherResult(
                    window: window,
                    browserURL: page?.url,
                    browserKind: page?.kind,
                    icon: iconForBundleId(window.bundleId)
                )
            }
    }

    private func iconForBundleId(_ bundleId: String) -> NSImage? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 34, height: 34)
        return icon
    }

    private func applyWindowSwitcherFilter() {
        let query = windowSwitcherSearchField?.stringValue ?? ""
        windowSwitcherVisibleResults = windowSwitcherAllResults.filter { $0.matches(query) }
        if windowSwitcherSelectedIndex >= windowSwitcherVisibleResults.count {
            windowSwitcherSelectedIndex = max(0, windowSwitcherVisibleResults.count - 1)
        }
        reloadWindowSwitcherRows()
    }

    private func reloadWindowSwitcherRows() {
        guard let stack = windowSwitcherResultsStackView else { return }
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        guard !windowSwitcherVisibleResults.isEmpty else {
            let empty = NSTextField(labelWithString: "没有匹配的窗口。")
            empty.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            empty.textColor = .secondaryLabelColor
            empty.alignment = .center
            empty.translatesAutoresizingMaskIntoConstraints = false
            empty.heightAnchor.constraint(equalToConstant: 84).isActive = true
            stack.addArrangedSubview(empty)
            return
        }

        for (index, result) in windowSwitcherVisibleResults.enumerated() {
            let row = WindowSwitcherResultRowView(result: result)
            row.isSelected = index == windowSwitcherSelectedIndex
            row.onSelect = { [weak self] in
                self?.windowSwitcherSelectedIndex = index
                self?.focusSelectedWindowSwitcherResult()
            }
            stack.addArrangedSubview(row)
        }
    }

    private func moveWindowSwitcherSelection(_ delta: Int) {
        guard !windowSwitcherVisibleResults.isEmpty else { return }
        let count = windowSwitcherVisibleResults.count
        windowSwitcherSelectedIndex = (windowSwitcherSelectedIndex + delta + count) % count
        reloadWindowSwitcherRows()
    }

    private func focusSelectedWindowSwitcherResult() {
        guard windowSwitcherSelectedIndex >= 0,
              windowSwitcherSelectedIndex < windowSwitcherVisibleResults.count
        else {
            return
        }
        let result = windowSwitcherVisibleResults[windowSwitcherSelectedIndex]
        windowSwitcherPanel?.orderOut(nil)
        focusPreviewWindow(result.window)
    }

    private func makeButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        return button
    }

    private func makeEmptyStateLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .left
        label.lineBreakMode = .byWordWrapping
        return label
    }

    private func makeShortcutActionRow(for action: WorkbenchShortcutAction) -> NSView {
        let shortcut = shortcut(for: action)
        let conflict = shortcutConflict(for: action, shortcut: shortcut)
        let isRecording = recordingShortcutAction == action

        let statusButton = ShortcutActionButton(
            shortcutAction: action,
            title: conflict == nil ? "↻" : "❗️",
            target: self,
            action: #selector(handleShortcutStatusButton(_:))
        )
        statusButton.toolTip = conflict == nil ? "重新录入快捷键" : "检测到冲突，点击处理"
        statusButton.bezelStyle = .rounded
        statusButton.controlSize = .small
        statusButton.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        if let conflict {
            let overridden = appConfig.shortcutConflictOverrides[action.rawValue] == true ? "（已覆盖）" : ""
            statusButton.toolTip = "\(conflict.title)\(overridden)：点击处理"
        }

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY
        applyFullWidthAlignment(to: row)

        let titleLabel = NSTextField(labelWithString: action.title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .left
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(titleLabel)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)

        let shortcutDisplay = makeShortcutDisplay(for: shortcut, isRecording: isRecording)
        row.addArrangedSubview(shortcutDisplay)
        row.addArrangedSubview(statusButton)

        return row
    }

    private func makeShortcutDisplay(for shortcut: DesktopConfig.Shortcut, isRecording: Bool) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        stack.setContentHuggingPriority(.required, for: .horizontal)

        if isRecording {
            stack.addArrangedSubview(makeShortcutToken("录入中", emphasized: true))
        } else {
            shortcutDisplayParts(for: shortcut).forEach {
                stack.addArrangedSubview(makeShortcutToken($0, emphasized: $0 == keyTitle(for: shortcut.keyCode)))
            }
        }
        return stack
    }

    private func makeShortcutToken(_ text: String, emphasized: Bool) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = emphasized
            ? NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
            : NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = emphasized ? .labelColor : .secondaryLabelColor
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.cornerRadius = 5
        label.layer?.masksToBounds = true
        label.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(emphasized ? 0.10 : 0.06).cgColor
        label.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.20).cgColor
        label.layer?.borderWidth = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(greaterThanOrEqualToConstant: max(24, CGFloat(text.count * 8 + 12))).isActive = true
        label.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return label
    }

    private func makePanelRoot() -> NSStackView {
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = WorkbenchChrome.sectionSpacing
        root.alignment = .leading
        root.distribution = .fill
        root.edgeInsets = WorkbenchChrome.pageInsets
        applyFullWidthAlignment(to: root)
        return root
    }

    private func addFullWidthArrangedSubview(_ subview: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(subview)
        subview.translatesAutoresizingMaskIntoConstraints = false
        let horizontalInset = stack.edgeInsets.left + stack.edgeInsets.right
        if stack.orientation == .vertical {
            subview.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -horizontalInset).isActive = true
        } else {
            subview.heightAnchor.constraint(equalTo: stack.heightAnchor, constant: -(stack.edgeInsets.top + stack.edgeInsets.bottom)).isActive = true
        }
    }

    private func makeSectionGroup(title: String? = nil, subtitle: String? = nil, views: [NSView], insets: NSEdgeInsets = WorkbenchChrome.cardInsets) -> NSVisualEffectView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = WorkbenchChrome.groupSpacing
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        applyFullWidthAlignment(to: stack)

        if title != nil || subtitle != nil {
            addFullWidthArrangedSubview(makeGroupHeader(title: title, subtitle: subtitle), to: stack)
        }
        views.forEach { addFullWidthArrangedSubview($0, to: stack) }
        return makeGlassCard(containing: stack, insets: insets)
    }

    private func makeGroupHeader(title: String? = nil, subtitle: String? = nil) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 4
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        applyFullWidthAlignment(to: stack)

        if let title {
            let titleLabel = NSTextField(labelWithString: title)
            titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            titleLabel.textColor = .labelColor
            titleLabel.alignment = .left
            addFullWidthArrangedSubview(titleLabel, to: stack)
        }

        if let subtitle {
            let subtitleLabel = NSTextField(labelWithString: subtitle)
            subtitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            subtitleLabel.textColor = .secondaryLabelColor
            subtitleLabel.alignment = .left
            subtitleLabel.lineBreakMode = .byWordWrapping
            subtitleLabel.maximumNumberOfLines = 3
            addFullWidthArrangedSubview(subtitleLabel, to: stack)
        }

        return stack
    }

    private func makeSectionTitle(_ title: String, subtitle: String? = nil) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 3
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        applyFullWidthAlignment(to: stack)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .left
        addFullWidthArrangedSubview(titleLabel, to: stack)

        if let subtitle {
            let subtitleLabel = NSTextField(labelWithString: subtitle)
            subtitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
            subtitleLabel.textColor = .secondaryLabelColor
            subtitleLabel.alignment = .left
            subtitleLabel.lineBreakMode = .byWordWrapping
            subtitleLabel.maximumNumberOfLines = 2
            addFullWidthArrangedSubview(subtitleLabel, to: stack)
        }

        return stack
    }

    private func makeControlCluster(_ controls: [NSView]) -> NSStackView {
        let cluster = NSStackView()
        cluster.orientation = .horizontal
        cluster.spacing = 8
        cluster.alignment = .centerY
        cluster.setContentHuggingPriority(.required, for: .horizontal)
        controls.forEach { cluster.addArrangedSubview($0) }
        return cluster
    }

    private func makeAppRoutingRow(app: AppRoutingItem, popup: NSPopUpButton) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 14
        row.alignment = .centerY
        applyFullWidthAlignment(to: row)
        row.alphaValue = app.isRoutingLocked ? 0.62 : 1.0

        let iconView = NSImageView()
        iconView.image = app.icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 26).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 26).isActive = true

        let labels = NSStackView()
        labels.orientation = .vertical
        labels.spacing = 2
        labels.alignment = .leading
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let titleLabel = NSTextField(labelWithString: app.appName)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = app.isRoutingLocked ? .tertiaryLabelColor : .labelColor
        titleLabel.alignment = .left
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.toolTip = app.bundleId
        labels.addArrangedSubview(titleLabel)

        let bundleLabel = NSTextField(labelWithString: app.bundleId)
        bundleLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        bundleLabel.textColor = .tertiaryLabelColor
        bundleLabel.alignment = .left
        bundleLabel.lineBreakMode = .byTruncatingMiddle
        labels.addArrangedSubview(bundleLabel)

        row.addArrangedSubview(iconView)
        row.addArrangedSubview(labels)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)

        row.addArrangedSubview(popup)

        let note = app.isRoutingLocked ? "只读" : (app.windowCount > 0 ? "运行中 \(app.windowCount)" : "未打开")
        let noteLabel = NSTextField(labelWithString: note)
        noteLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        noteLabel.textColor = app.isRoutingLocked || app.windowCount == 0 ? .tertiaryLabelColor : .secondaryLabelColor
        noteLabel.alignment = .left
        noteLabel.setContentHuggingPriority(.required, for: .horizontal)
        row.addArrangedSubview(noteLabel)

        return row
    }

    private func makeActionRow(
        title: String,
        detail: String? = nil,
        controls: [NSView],
        trailingNote: String? = nil,
        muted: Bool = false
    ) -> NSView {
        let row = NSStackView()
        row.orientation = .vertical
        row.spacing = controls.isEmpty ? 4 : 8
        row.alignment = .width
        applyFullWidthAlignment(to: row)
        row.alphaValue = muted ? 0.62 : 1.0

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.spacing = 3
        textStack.alignment = .leading
        applyFullWidthAlignment(to: textStack)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = muted ? .tertiaryLabelColor : .labelColor
        titleLabel.alignment = .left
        titleLabel.lineBreakMode = .byTruncatingTail
        addFullWidthArrangedSubview(titleLabel, to: textStack)

        if let detail {
            let detailLabel = NSTextField(labelWithString: detail)
            detailLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            detailLabel.textColor = muted ? .tertiaryLabelColor : .secondaryLabelColor
            detailLabel.alignment = .left
            detailLabel.lineBreakMode = .byWordWrapping
            detailLabel.maximumNumberOfLines = 2
            addFullWidthArrangedSubview(detailLabel, to: textStack)
        }

        if let trailingNote {
            let noteLabel = NSTextField(labelWithString: trailingNote)
            noteLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            noteLabel.textColor = .tertiaryLabelColor
            noteLabel.alignment = .left
            noteLabel.lineBreakMode = .byWordWrapping
            noteLabel.maximumNumberOfLines = 2
            addFullWidthArrangedSubview(noteLabel, to: textStack)
        }

        addFullWidthArrangedSubview(textStack, to: row)

        if !controls.isEmpty {
            let controlsRow = makeControlCluster(controls)
            controlsRow.alignment = .leading
            addFullWidthArrangedSubview(controlsRow, to: row)
        }

        return row
    }

    private func makeSettingRow(title: String, detail: String? = nil, control: NSView) -> NSView {
        makeGlassCard(containing: makeActionRow(title: title, detail: detail, controls: [control]))
    }

    private func makeBoundedScrollView(containing content: NSView, height: CGFloat) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: height).isActive = true
        applyFullWidthAlignment(to: scrollView)

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        content.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            content.topAnchor.constraint(equalTo: documentView.topAnchor),
            content.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        return scrollView
    }

    private func makeGlassCard(containing content: NSView, insets: NSEdgeInsets = WorkbenchChrome.cardInsets) -> NSVisualEffectView {
        let card = NSVisualEffectView()
        card.material = .contentBackground
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = WorkbenchChrome.cardCornerRadius
        card.layer?.cornerCurve = .continuous
        card.layer?.masksToBounds = true
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.12).cgColor
        card.layer?.borderWidth = 0.5
        card.translatesAutoresizingMaskIntoConstraints = false
        applyFullWidthAlignment(to: card)

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

    private func applyFullWidthAlignment(to view: NSView) {
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
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
            let unconstrained = currentUnconstrainedWindowNumbers(in: windows)
            partitionState.unconstrainedWindowNumbers = unconstrained
            try zoneManager.applyForcedZones(
                windows: windows,
                mergeMode: mergeMode,
                excludingWindowNumbers: unconstrained
            )
            partitionState.zoneAssignmentsByWindowNumber = zoneManager.currentZoneAssignments(
                windows: windows,
                mergeMode: mergeMode,
                excludingWindowNumbers: unconstrained
            )
            lastWindowFramesByNumber.removeAll()
            for window in windows {
                if unconstrained.contains(window.windowNumber) {
                    continue
                }
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

        if let effect = panel.contentView as? NSVisualEffectView {
            effect.material = appConfig.stackTabGlassStyle.material
            effect.layer?.borderColor = appConfig.stackTabGlassStyle.borderColor.cgColor
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
            let label = identity.tabDisplayTitle()
            let btn = StackTabButton(title: label, target: self, action: #selector(selectStackTab(_:)))
            btn.stackName = stack.name
            btn.tabIndex = index
            btn.glassStyle = appConfig.stackTabGlassStyle
            btn.isActiveTab = index == stack.activeIndex
            btn.isBordered = false
            btn.controlSize = .small
            btn.font = NSFont.systemFont(ofSize: 11, weight: index == stack.activeIndex ? .semibold : .regular)
            btn.toolTip = identity.fullDisplayTitle
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
        effect.layer?.cornerRadius = 16
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        effect.layer?.borderWidth = 1
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
private final class WindowPreviewCardView: NSView {
    let snapshot: WindowPreviewSnapshot
    var onFocus: ((WindowInfo) -> Void)?
    private var isHovered = false

    init(snapshot: WindowPreviewSnapshot) {
        self.snapshot = snapshot
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 210))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 360).isActive = true
        heightAnchor.constraint(equalToConstant: 210).isActive = true
        wantsLayer = true
        toolTip = snapshot.window.title.isEmpty
            ? snapshot.window.appName
            : "\(snapshot.window.title) - \(snapshot.window.appName)"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onFocus?(snapshot.window)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let card = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12)
        (isHovered ? NSColor.controlAccentColor.withAlphaComponent(0.10) : NSColor.labelColor.withAlphaComponent(0.045)).setFill()
        path.fill()
        (isHovered ? NSColor.controlAccentColor.withAlphaComponent(0.42) : NSColor.separatorColor.withAlphaComponent(0.22)).setStroke()
        path.lineWidth = isHovered ? 1.4 : 1
        path.stroke()

        let imageRect = NSRect(x: 12, y: 48, width: bounds.width - 24, height: bounds.height - 64)
        let imagePath = NSBezierPath(roundedRect: imageRect, xRadius: 8, yRadius: 8)
        NSColor.black.withAlphaComponent(0.08).setFill()
        imagePath.fill()

        if let image = snapshot.image {
            image.draw(in: imageRect.insetBy(dx: 1, dy: 1), from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
        } else {
            let placeholder = "需要屏幕录制权限"
            placeholder.draw(
                in: imageRect.insetBy(dx: 16, dy: imageRect.height / 2 - 10),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: centeredParagraph()
                ]
            )
        }

        let title = snapshot.window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? snapshot.window.appName : title
        displayTitle.draw(
            in: NSRect(x: 14, y: 26, width: bounds.width - 28, height: 16),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: truncatingParagraph()
            ]
        )

        "\(snapshot.window.appName) · #\(snapshot.window.windowNumber)".draw(
            in: NSRect(x: 14, y: 10, width: bounds.width - 28, height: 13),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: truncatingParagraph()
            ]
        )
    }

    private func centeredParagraph() -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        return paragraph
    }

    private func truncatingParagraph() -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byTruncatingTail
        return paragraph
    }
}

@MainActor
private final class DockWindowPreviewCardView: NSView {
    static let cardHeight: CGFloat = 142
    private static let minCardWidth: CGFloat = 160
    private static let maxCardWidth: CGFloat = 260

    let snapshot: WindowPreviewSnapshot
    var onFocus: ((WindowInfo) -> Void)?
    private var isHovered = false
    private let cardWidth: CGFloat

    init(snapshot: WindowPreviewSnapshot) {
        self.snapshot = snapshot
        let imageSize = snapshot.image?.size ?? snapshot.window.frame.cgRect.size
        let imageRatio = imageSize.height > 0 ? imageSize.width / imageSize.height : 16 / 10
        self.cardWidth = Swift.min(Self.maxCardWidth, Swift.max(Self.minCardWidth, imageRatio * 96 + 20))
        super.init(frame: NSRect(x: 0, y: 0, width: cardWidth, height: Self.cardHeight))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: cardWidth).isActive = true
        heightAnchor.constraint(equalToConstant: Self.cardHeight).isActive = true
        wantsLayer = true
        toolTip = snapshot.window.title.isEmpty
            ? snapshot.window.appName
            : "\(snapshot.window.title) - \(snapshot.window.appName)"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onFocus?(snapshot.window)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let card = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: card, xRadius: 10, yRadius: 10)
        (isHovered ? NSColor.controlAccentColor.withAlphaComponent(0.16) : NSColor.labelColor.withAlphaComponent(0.08)).setFill()
        path.fill()
        (isHovered ? NSColor.controlAccentColor.withAlphaComponent(0.50) : NSColor.separatorColor.withAlphaComponent(0.32)).setStroke()
        path.lineWidth = isHovered ? 1.4 : 1
        path.stroke()

        let imageRect = NSRect(x: 10, y: 34, width: bounds.width - 20, height: 96)
        let imagePath = NSBezierPath(roundedRect: imageRect, xRadius: 7, yRadius: 7)
        NSColor.black.withAlphaComponent(0.14).setFill()
        imagePath.fill()

        if let image = snapshot.image {
            image.draw(in: imageRect.insetBy(dx: 1, dy: 1), from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
        } else {
            "需要屏幕录制权限".draw(
                in: imageRect.insetBy(dx: 12, dy: imageRect.height / 2 - 9),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: centeredParagraph()
                ]
            )
        }

        let title = snapshot.window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? snapshot.window.appName : title
        displayTitle.draw(
            in: NSRect(x: 12, y: 17, width: bounds.width - 24, height: 14),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: truncatingParagraph()
            ]
        )

        snapshot.window.appName.draw(
            in: NSRect(x: 12, y: 5, width: bounds.width - 24, height: 12),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: truncatingParagraph()
            ]
        )
    }

    private func centeredParagraph() -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        return paragraph
    }

    private func truncatingParagraph() -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byTruncatingTail
        return paragraph
    }
}

@MainActor
private final class DisplayWakeButton: NSButton {
    let display: LayoutDisplaySnapshot

    init(display: LayoutDisplaySnapshot, isPreferred: Bool) {
        self.display = display
        super.init(frame: .zero)
        title = isPreferred ? "屏幕 \(display.index + 1)\n默认" : "屏幕 \(display.index + 1)"
        toolTip = "\(display.name) · displayId \(display.id)"
        bezelStyle = .regularSquare
        setButtonType(.momentaryPushIn)
        alignment = .center
        font = NSFont.systemFont(ofSize: 12, weight: isPreferred ? .semibold : .medium)
        lineBreakMode = .byWordWrapping
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        contentTintColor = isPreferred ? .controlAccentColor : .labelColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
private final class DisplayWakeMapView: NSView {
    let displays: [LayoutDisplaySnapshot]
    let preferredDisplayId: UInt32?
    var onSelect: ((LayoutDisplaySnapshot) -> Void)?

    private var buttons: [DisplayWakeButton] = []

    init(displays: [LayoutDisplaySnapshot], preferredDisplayId: UInt32?) {
        self.displays = displays
        self.preferredDisplayId = preferredDisplayId
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.045).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.22).cgColor
        layer?.borderWidth = 1

        for display in displays {
            let button = DisplayWakeButton(display: display, isPreferred: display.id == preferredDisplayId)
            button.target = self
            button.action = #selector(selectDisplay(_:))
            addSubview(button)
            buttons.append(button)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        guard !displays.isEmpty else { return }

        let frames = displays.map { $0.frame.cgRect }
        let union = frames.reduce(frames[0]) { $0.union($1) }
        guard union.width > 1, union.height > 1 else { return }

        let canvas = bounds.insetBy(dx: 22, dy: 18)
        let scale = min(canvas.width / union.width, canvas.height / union.height)
        let contentSize = CGSize(width: union.width * scale, height: union.height * scale)
        let origin = CGPoint(
            x: canvas.midX - contentSize.width / 2,
            y: canvas.midY - contentSize.height / 2
        )

        for (index, display) in displays.enumerated() {
            let frame = display.frame.cgRect
            let rect = NSRect(
                x: origin.x + (frame.minX - union.minX) * scale,
                y: origin.y + (frame.minY - union.minY) * scale,
                width: max(92, frame.width * scale),
                height: max(56, frame.height * scale)
            )
            buttons[index].frame = rect
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let guide = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 16, yRadius: 16)
        NSColor.controlAccentColor.withAlphaComponent(0.05).setFill()
        guide.fill()
    }

    @objc
    private func selectDisplay(_ sender: DisplayWakeButton) {
        onSelect?(sender.display)
    }
}

@MainActor
private final class LayoutNoteCardView: NSView {
    static let cardSize = NSSize(width: 336, height: 236)

    let desktopLayout: DesktopLayout
    var onSelect: ((String) -> Void)?
    var onApply: ((String) -> Void)?
    var onDelete: ((String) -> Void)?

    private let selected: Bool

    init(layout: DesktopLayout, selected: Bool) {
        self.desktopLayout = layout
        self.selected = selected
        super.init(frame: NSRect(origin: .zero, size: Self.cardSize))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: Self.cardSize.width).isActive = true
        heightAnchor.constraint(equalToConstant: Self.cardSize.height).isActive = true
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bg = selected ? NSColor.controlAccentColor.withAlphaComponent(0.16) : NSColor.labelColor.withAlphaComponent(0.045)
        let border = selected ? NSColor.controlAccentColor.withAlphaComponent(0.78) : NSColor.separatorColor.withAlphaComponent(0.36)

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
        desktopLayout.name.draw(in: NSRect(x: 12, y: bounds.height - 28, width: bounds.width - 168, height: 18), withAttributes: titleAttrs)

        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        layoutSubtitle.draw(
            in: NSRect(x: 12, y: bounds.height - 46, width: bounds.width - 24, height: 16),
            withAttributes: subAttrs
        )

        drawWakePill(in: wakeActionRect)
        drawDeletePill(in: deleteActionRect)

        let miniMap = NSRect(x: 12, y: bounds.height - 102, width: 92, height: 48)
        drawPreview(in: miniMap)

        let displayAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        preferredDisplayText.draw(
            in: NSRect(x: 114, y: bounds.height - 82, width: bounds.width - 126, height: 14),
            withAttributes: displayAttrs
        )
        savedAtText.draw(
            in: NSRect(x: 114, y: bounds.height - 100, width: bounds.width - 126, height: 14),
            withAttributes: displayAttrs
        )

        drawWindowList(in: NSRect(x: 12, y: 12, width: bounds.width - 24, height: bounds.height - 124))
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if deleteActionRect.contains(point) {
            onDelete?(desktopLayout.name)
            return
        }
        if wakeActionRect.contains(point) || event.clickCount >= 2 {
            onApply?(desktopLayout.name)
            return
        }

        onSelect?(desktopLayout.name)
    }

    private func drawPreview(in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor.textBackgroundColor.withAlphaComponent(0.72).setFill()
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

    private func drawWakePill(in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor.controlAccentColor.withAlphaComponent(selected ? 0.28 : 0.18).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.42).setStroke()
        path.lineWidth = 1
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.controlAccentColor
        ]
        "唤醒".draw(in: rect.insetBy(dx: 12, dy: 5), withAttributes: attrs)
    }

    private func drawDeletePill(in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor.systemRed.withAlphaComponent(selected ? 0.18 : 0.10).setFill()
        path.fill()
        NSColor.systemRed.withAlphaComponent(0.28).setStroke()
        path.lineWidth = 1
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.systemRed.withAlphaComponent(0.86)
        ]
        "删除".draw(in: rect.insetBy(dx: 12, dy: 5), withAttributes: attrs)
    }

    private func drawWindowList(in rect: NSRect) {
        let windows = previewWindows
        guard !windows.isEmpty else {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
            "这个布局没有保存可显示的窗口".draw(in: rect, withAttributes: attrs)
            return
        }

        let visibleRows = Array(windows.prefix(4))
        for (index, window) in visibleRows.enumerated() {
            let rowTop = rect.maxY - CGFloat(index + 1) * 35
            let row = NSRect(x: rect.minX, y: rowTop, width: rect.width, height: 30)
            drawWindowRow(window, in: row)
        }

        let hiddenCount = windows.count - visibleRows.count
        if hiddenCount > 0 {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
            "+\(hiddenCount) 个窗口".draw(
                in: NSRect(x: rect.minX + 2, y: rect.minY, width: rect.width - 4, height: 14),
                withAttributes: attrs
            )
        }
    }

    private func drawWindowRow(_ window: LayoutWindow, in rect: NSRect) {
        let bgPath = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        NSColor.labelColor.withAlphaComponent(0.035).setFill()
        bgPath.fill()

        let iconRect = NSRect(x: rect.minX + 6, y: rect.minY + 5, width: 20, height: 20)
        if let icon = icon(for: window) {
            icon.draw(in: iconRect)
        } else {
            let dot = NSBezierPath(roundedRect: iconRect, xRadius: 5, yRadius: 5)
            NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
            dot.fill()
            let initial = String(window.appName.prefix(1))
            initial.draw(in: iconRect.insetBy(dx: 5, dy: 3), withAttributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: NSColor.controlAccentColor
            ])
        }

        let title = window.title.isEmpty ? window.appName : window.title
        let detailParts = [
            window.appName,
            window.zoneName.map { "块：\($0)" },
            window.browserURL.flatMap { URL(string: $0)?.host ?? $0 }
        ].compactMap { $0 }

        title.draw(
            in: NSRect(x: rect.minX + 34, y: rect.minY + 14, width: rect.width - 42, height: 13),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
        )
        detailParts.joined(separator: " · ").draw(
            in: NSRect(x: rect.minX + 34, y: rect.minY + 3, width: rect.width - 42, height: 11),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 9, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
    }

    private var wakeActionRect: NSRect {
        NSRect(x: bounds.width - 72, y: bounds.height - 34, width: 60, height: 24)
    }

    private var deleteActionRect: NSRect {
        NSRect(x: bounds.width - 138, y: bounds.height - 34, width: 60, height: 24)
    }

    private var layoutSubtitle: String {
        "\(previewWindows.count) 窗口 / \(desktopLayout.stacks.count) 堆叠"
    }

    private var preferredDisplayText: String {
        desktopLayout.preferredDisplay.map { "默认屏幕：\($0.name)" } ?? "默认屏幕：未记录"
    }

    private var savedAtText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return "保存于 \(formatter.string(from: desktopLayout.createdAt))"
    }

    private var previewWindows: [LayoutWindow] {
        var seen = Set<String>()
        let combined = desktopLayout.windows + desktopLayout.stacks.flatMap(\.windows)
        return combined.filter { window in
            let key = "\(window.bundleId)|\(window.title)|\(window.frame.x)|\(window.frame.y)"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private func icon(for window: LayoutWindow) -> NSImage? {
        if let iconPath = window.iconPath, let image = NSImage(contentsOfFile: iconPath) {
            return image
        }
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: window.bundleId) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }
        return nil
    }

    private func occupiedQuadrants() -> Set<Int> {
        var result: Set<Int> = []
        let allFrames = previewWindows.map(\.frame.cgRect) + desktopLayout.stacks.map(\.frame.cgRect)
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
        var zoneName: String
        var title: String
        var frame: CGRect
        var isBucket: Bool
        var windows: [WindowInfo]
    }

    private struct WindowHitArea {
        var rect: CGRect
        var window: WindowInfo
        var sourceZoneName: String
    }

    private enum Quadrant: CaseIterable {
        case tl
        case tr
        case bl
        case br
    }

    private enum DragAxis { case horizontal, vertical, both }

    private struct PreviewDivider {
        let isVertical: Bool
        let start: NSPoint
        let end: NSPoint
        let center: NSPoint
    }

    private let displayFrame: CGRect
    private var sections: [Section] = []
    private var windowHitAreas: [WindowHitArea] = []
    private var cachedWindows: [WindowInfo] = []
    private var cachedLeftBucket: WindowStack?
    private var cachedLeftBucketEnabled = true
    var onSplitChanged: ((CGFloat, CGFloat, Bool) -> Void)?
    var onWindowDroppedIntoZone: ((WindowInfo, String) -> Void)?

    // Split ratios (0~1), default 0.5
    var splitX: CGFloat = 0.5
    var splitY: CGFloat = 0.5

    private var draggingAxis: DragAxis?
    private var draggingWindow: WindowInfo?
    private var draggingSourceZoneName: String?
    private var dragLocation: NSPoint?
    private var dragTargetZoneName: String?
    private let dividerHitWidth: CGFloat = 20
    private let previewZoneGap: CGFloat = 8
    private var currentMergeMode: DesktopMergeMode = .leftColumn

    init(displayFrame: CGRect) {
        self.displayFrame = displayFrame
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.95).cgColor
    }

    var heightToWidthRatio: CGFloat {
        guard displayFrame.width > 0 else { return 0.5625 }
        return displayFrame.height / displayFrame.width
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
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
            if descriptor.isLeftArea, hasVisibleLeftBucket {
                return Section(
                    zoneName: descriptor.zoneName,
                    title: descriptor.title + "（标签桶）",
                    frame: descriptor.frame,
                    isBucket: true,
                    windows: visibleLeftBucketWindows.isEmpty ? sectionWindows : visibleLeftBucketWindows
                )
            }

            return Section(
                zoneName: descriptor.zoneName,
                title: descriptor.title,
                frame: descriptor.frame,
                isBucket: false,
                windows: sectionWindows
            )
        }
    }

    private var hasVisibleLeftBucket: Bool {
        cachedLeftBucketEnabled && !(cachedLeftBucket?.windows.isEmpty ?? true)
    }

    private var visibleLeftBucketWindows: [WindowInfo] {
        guard let bucket = cachedLeftBucket else { return [] }
        return bucket.windows.compactMap { identity in
            if let windowNumber = identity.windowNumber,
               let exact = cachedWindows.first(where: { $0.windowNumber == windowNumber }) {
                return exact
            }
            if !identity.title.isEmpty,
               let titled = cachedWindows.first(where: { $0.bundleId == identity.bundleId && $0.title == identity.title }) {
                return titled
            }
            return cachedWindows.first(where: { $0.bundleId == identity.bundleId })
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawCanvasBackground()
        windowHitAreas.removeAll()
        for section in sections {
            drawSection(section)
        }

        drawPreviewDividers()
        drawDraggedWindowGhost()
    }

    private func drawPreviewDividers() {
        guard let inset = sanitizedInsetBounds() else { return }
        for divider in previewDividers(in: inset) {
            drawSplitHandle(at: divider.center, vertical: divider.isVertical)
        }
    }

    private func drawDraggedWindowGhost() {
        guard let draggingWindow, let dragLocation else { return }
        let label = draggingWindow.title.isEmpty ? draggingWindow.appName : "\(draggingWindow.title) - \(draggingWindow.appName)"
        let width = min(max(CGFloat(label.count) * 6.8 + 24, 140), 260)
        let rect = NSRect(x: dragLocation.x + 12, y: dragLocation.y - 12, width: width, height: 24)
        guard let safe = safeRect(rect, minWidth: 80, minHeight: 16) else { return }
        let path = NSBezierPath(roundedRect: safe, xRadius: 7, yRadius: 7)
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.72).setStroke()
        path.lineWidth = 1.2
        path.stroke()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        label.draw(in: safe.insetBy(dx: 8, dy: 5), withAttributes: attrs)
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

        if let hitArea = windowHitAreas.first(where: { $0.rect.contains(location) }) {
            draggingWindow = hitArea.window
            draggingSourceZoneName = hitArea.sourceZoneName
            dragLocation = location
            dragTargetZoneName = hitArea.sourceZoneName
            needsDisplay = true
            return
        }

        // Check divider hits
        guard let inset = sanitizedInsetBounds() else {
            super.mouseDown(with: event)
            return
        }
        let xDivider = inset.minX + inset.width * splitX
        let yDivider = visualYDivider(in: inset)

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
        if draggingWindow != nil {
            let location = convert(event.locationInWindow, from: nil)
            dragLocation = location
            dragTargetZoneName = section(at: location)?.zoneName
            needsDisplay = true
            return
        }

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
            let newY = 1.0 - ((location.y - inset.minY) / max(inset.height, 1))
            splitY = clampSplit(newY)
        }

        rebuildSections()
        needsDisplay = true
        onSplitChanged?(splitX, splitY, false)
    }

    override func mouseUp(with event: NSEvent) {
        if let draggingWindow {
            let targetZoneName = dragTargetZoneName
            let sourceZoneName = draggingSourceZoneName
            self.draggingWindow = nil
            draggingSourceZoneName = nil
            dragLocation = nil
            dragTargetZoneName = nil
            needsDisplay = true
            if let targetZoneName, targetZoneName != sourceZoneName {
                onWindowDroppedIntoZone?(draggingWindow, targetZoneName)
            }
            return
        }

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
        let yDivider = visualYDivider(in: inset)

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

    private func drawSection(_ section: Section) {
        guard let sectionRect = safeRect(section.frame, minWidth: 6, minHeight: 6) else { return }
        let path = NSBezierPath(roundedRect: sectionRect, xRadius: 10, yRadius: 10)
        let isDropTarget = draggingWindow != nil && dragTargetZoneName == section.zoneName
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.08)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 5
        shadow.set()

        let fillGradient: NSGradient?
        if isDropTarget {
            fillGradient = NSGradient(colors: [
                NSColor.controlAccentColor.withAlphaComponent(0.22),
                NSColor.controlAccentColor.withAlphaComponent(0.08)
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

        (isDropTarget ? NSColor.controlAccentColor.withAlphaComponent(0.80) : NSColor.systemGray.withAlphaComponent(0.40)).setStroke()
        path.lineWidth = isDropTarget ? 2 : 1.5
        path.stroke()
        NSGraphicsContext.current?.restoreGraphicsState()

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        section.title.draw(
            in: NSRect(x: sectionRect.minX + 10, y: sectionRect.maxY - 24, width: sectionRect.width - 20, height: 16),
            withAttributes: titleAttrs
        )

        windowHitAreas.append(contentsOf: drawStackList(
            section.windows,
            in: sectionRect.insetBy(dx: 10, dy: 28),
            zoneName: section.zoneName
        ))
    }

    private func drawStackList(_ windows: [WindowInfo], in rect: CGRect, zoneName: String) -> [WindowHitArea] {
        guard let safeArea = safeRect(rect, minWidth: 8, minHeight: 8) else { return [] }
        if windows.isEmpty {
            drawPlaceholder("空区域", in: safeArea)
            return []
        }
        var hitAreas: [WindowHitArea] = []
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        var y = safeArea.maxY - 22
        for window in windows.prefix(8) {
            let title = window.title.isEmpty ? window.appName : "\(window.title) - \(window.appName)"
            let rect = NSRect(x: safeArea.minX, y: y, width: safeArea.width - 4, height: 20)
            if let safeRect = safeRect(rect, minWidth: 40, minHeight: 12) {
                let pill = NSBezierPath(roundedRect: safeRect, xRadius: 5, yRadius: 5)
                NSColor.labelColor.withAlphaComponent(0.05).setFill()
                pill.fill()
                NSColor.separatorColor.withAlphaComponent(0.22).setStroke()
                pill.lineWidth = 1
                pill.stroke()
                title.draw(in: safeRect.insetBy(dx: 7, dy: 3), withAttributes: attrs)
                hitAreas.append(WindowHitArea(rect: safeRect, window: window, sourceZoneName: zoneName))
            }
            y -= 23
            if y < safeArea.minY { break }
        }
        return hitAreas
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
        let isTop = center.y < yMid

        switch (isTop, isRight) {
        case (true, false): return .tl
        case (true, true): return .tr
        case (false, false): return .bl
        case (false, true): return .br
        }
    }

    private func buildSections(for mode: DesktopMergeMode) -> [(zoneName: String, title: String, frame: CGRect, quadrants: [Quadrant], isLeftArea: Bool)] {
        guard let inset = sanitizedInsetBounds() else { return [] }

        let safeSplitX = clampSplit(splitX)
        let xSplit = inset.minX + inset.width * safeSplitX
        let ySplit = visualYDivider(in: inset)

        let leftW = xSplit - inset.minX
        let rightW = inset.maxX - xSplit
        let bottomH = ySplit - inset.minY
        let topH = inset.maxY - ySplit

        let tl = CGRect(x: inset.minX, y: ySplit, width: leftW, height: topH)
        let tr = CGRect(x: xSplit, y: ySplit, width: rightW, height: topH)
        let bl = CGRect(x: inset.minX, y: inset.minY, width: leftW, height: bottomH)
        let br = CGRect(x: xSplit, y: inset.minY, width: rightW, height: bottomH)
        let gap = previewZoneGap

        func insetTL(_ rect: CGRect) -> CGRect {
            previewZoneRect(CGRect(
                x: rect.minX,
                y: rect.minY + gap / 2,
                width: max(40, rect.width - gap / 2),
                height: max(40, rect.height - gap / 2)
            ))
        }

        func insetTR(_ rect: CGRect) -> CGRect {
            previewZoneRect(CGRect(
                x: rect.minX + gap / 2,
                y: rect.minY + gap / 2,
                width: max(40, rect.width - gap / 2),
                height: max(40, rect.height - gap / 2)
            ))
        }

        func insetBL(_ rect: CGRect) -> CGRect {
            previewZoneRect(CGRect(
                x: rect.minX,
                y: rect.minY,
                width: max(40, rect.width - gap / 2),
                height: max(40, rect.height - gap / 2)
            ))
        }

        func insetBR(_ rect: CGRect) -> CGRect {
            previewZoneRect(CGRect(
                x: rect.minX + gap / 2,
                y: rect.minY,
                width: max(40, rect.width - gap / 2),
                height: max(40, rect.height - gap / 2)
            ))
        }

        func insetLeftHalf(_ rect: CGRect) -> CGRect {
            previewZoneRect(CGRect(x: rect.minX, y: rect.minY, width: max(40, rect.width - gap / 2), height: rect.height))
        }

        func insetRightHalf(_ rect: CGRect) -> CGRect {
            previewZoneRect(CGRect(x: rect.minX + gap / 2, y: rect.minY, width: max(40, rect.width - gap / 2), height: rect.height))
        }

        func insetTopHalf(_ rect: CGRect) -> CGRect {
            previewZoneRect(CGRect(x: rect.minX, y: rect.minY + gap / 2, width: rect.width, height: max(40, rect.height - gap / 2)))
        }

        func insetBottomHalf(_ rect: CGRect) -> CGRect {
            previewZoneRect(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(40, rect.height - gap / 2)))
        }

        switch mode {
        case .grid:
            return [
                ("top-left", "左上", insetTL(tl), [.tl], true),
                ("top-right", "右上", insetTR(tr), [.tr], false),
                ("bottom-left", "左下", insetBL(bl), [.bl], true),
                ("bottom-right", "右下", insetBR(br), [.br], false)
            ]
        case .leftColumn:
            let left = CGRect(x: inset.minX, y: inset.minY, width: leftW, height: inset.height)
            return [
                ("left", "左侧大块", insetLeftHalf(left), [.tl, .bl], true),
                ("top-right", "右上", insetTR(tr), [.tr], false),
                ("bottom-right", "右下", insetBR(br), [.br], false)
            ]
        case .rightColumn:
            let right = CGRect(x: xSplit, y: inset.minY, width: rightW, height: inset.height)
            return [
                ("top-left", "左上", insetTL(tl), [.tl], true),
                ("bottom-left", "左下", insetBL(bl), [.bl], true),
                ("right", "右侧大块", insetRightHalf(right), [.tr, .br], false)
            ]
        case .topRow:
            let top = CGRect(x: inset.minX, y: ySplit, width: inset.width, height: topH)
            return [
                ("top", "上方大块", insetTopHalf(top), [.tl, .tr], true),
                ("bottom-left", "左下", insetBL(bl), [.bl], true),
                ("bottom-right", "右下", insetBR(br), [.br], false)
            ]
        case .bottomRow:
            let bottom = CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: bottomH)
            return [
                ("top-left", "左上", insetTL(tl), [.tl], true),
                ("top-right", "右上", insetTR(tr), [.tr], false),
                ("bottom", "下方大块", insetBottomHalf(bottom), [.bl, .br], true)
            ]
        case .leftRight:
            let left = CGRect(x: inset.minX, y: inset.minY, width: leftW, height: inset.height)
            let right = CGRect(x: xSplit, y: inset.minY, width: rightW, height: inset.height)
            return [
                ("left", "左侧", insetLeftHalf(left), [.tl, .bl], true),
                ("right", "右侧", insetRightHalf(right), [.tr, .br], false)
            ]
        case .topBottom:
            let top = CGRect(x: inset.minX, y: ySplit, width: inset.width, height: topH)
            let bottom = CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: bottomH)
            return [
                ("top", "上方", insetTopHalf(top), [.tl, .tr], true),
                ("bottom", "下方", insetBottomHalf(bottom), [.bl, .br], false)
            ]
        case .threeColumns:
            let thirdW = inset.width / 3
            let c1 = previewZoneRect(CGRect(x: inset.minX, y: inset.minY, width: max(40, thirdW - gap / 2), height: inset.height))
            let c2 = previewZoneRect(CGRect(x: inset.minX + thirdW + gap / 2, y: inset.minY, width: max(40, thirdW - gap), height: inset.height))
            let c3 = previewZoneRect(CGRect(x: inset.minX + thirdW * 2 + gap / 2, y: inset.minY, width: max(40, thirdW - gap / 2), height: inset.height))
            return [
                ("col-left", "左列", c1, [.tl, .bl], true),
                ("col-center", "中列", c2, [.tl, .bl, .tr, .br], false),
                ("col-right", "右列", c3, [.tr, .br], false)
            ]
        case .threeRows:
            let thirdH = inset.height / 3
            let r1 = previewZoneRect(CGRect(x: inset.minX, y: inset.minY + thirdH * 2 + gap / 2, width: inset.width, height: max(40, thirdH - gap / 2)))
            let r2 = previewZoneRect(CGRect(x: inset.minX, y: inset.minY + thirdH + gap / 2, width: inset.width, height: max(40, thirdH - gap)))
            let r3 = previewZoneRect(CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: max(40, thirdH - gap / 2)))
            return [
                ("row-top", "上行", r1, [.tl, .tr], true),
                ("row-center", "中行", r2, [.tl, .tr, .bl, .br], false),
                ("row-bottom", "下行", r3, [.bl, .br], false)
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

    private func visualYDivider(in inset: CGRect) -> CGFloat {
        inset.minY + inset.height * (1.0 - clampSplit(splitY))
    }

    private func previewDividers(in inset: CGRect) -> [PreviewDivider] {
        let xDivider = inset.minX + inset.width * clampSplit(splitX)
        let yDivider = visualYDivider(in: inset)

        switch currentMergeMode {
        case .leftRight:
            return [PreviewDivider(isVertical: true, start: NSPoint(x: xDivider, y: inset.minY), end: NSPoint(x: xDivider, y: inset.maxY), center: NSPoint(x: xDivider, y: inset.midY))]
        case .topBottom:
            return [PreviewDivider(isVertical: false, start: NSPoint(x: inset.minX, y: yDivider), end: NSPoint(x: inset.maxX, y: yDivider), center: NSPoint(x: inset.midX, y: yDivider))]
        case .leftColumn:
            return [
                PreviewDivider(isVertical: true, start: NSPoint(x: xDivider, y: inset.minY), end: NSPoint(x: xDivider, y: inset.maxY), center: NSPoint(x: xDivider, y: inset.midY)),
                PreviewDivider(isVertical: false, start: NSPoint(x: xDivider, y: yDivider), end: NSPoint(x: inset.maxX, y: yDivider), center: NSPoint(x: (xDivider + inset.maxX) / 2, y: yDivider))
            ]
        case .rightColumn:
            return [
                PreviewDivider(isVertical: true, start: NSPoint(x: xDivider, y: inset.minY), end: NSPoint(x: xDivider, y: inset.maxY), center: NSPoint(x: xDivider, y: inset.midY)),
                PreviewDivider(isVertical: false, start: NSPoint(x: inset.minX, y: yDivider), end: NSPoint(x: xDivider, y: yDivider), center: NSPoint(x: (inset.minX + xDivider) / 2, y: yDivider))
            ]
        case .topRow:
            return [
                PreviewDivider(isVertical: false, start: NSPoint(x: inset.minX, y: yDivider), end: NSPoint(x: inset.maxX, y: yDivider), center: NSPoint(x: inset.midX, y: yDivider)),
                PreviewDivider(isVertical: true, start: NSPoint(x: xDivider, y: inset.minY), end: NSPoint(x: xDivider, y: yDivider), center: NSPoint(x: xDivider, y: (inset.minY + yDivider) / 2))
            ]
        case .bottomRow:
            return [
                PreviewDivider(isVertical: false, start: NSPoint(x: inset.minX, y: yDivider), end: NSPoint(x: inset.maxX, y: yDivider), center: NSPoint(x: inset.midX, y: yDivider)),
                PreviewDivider(isVertical: true, start: NSPoint(x: xDivider, y: yDivider), end: NSPoint(x: xDivider, y: inset.maxY), center: NSPoint(x: xDivider, y: (yDivider + inset.maxY) / 2))
            ]
        case .grid:
            return [
                PreviewDivider(
                    isVertical: true,
                    start: NSPoint(x: xDivider, y: yDivider),
                    end: NSPoint(x: xDivider, y: inset.maxY),
                    center: NSPoint(x: xDivider, y: (yDivider + inset.maxY) / 2)
                ),
                PreviewDivider(
                    isVertical: true,
                    start: NSPoint(x: xDivider, y: inset.minY),
                    end: NSPoint(x: xDivider, y: yDivider),
                    center: NSPoint(x: xDivider, y: (inset.minY + yDivider) / 2)
                ),
                PreviewDivider(
                    isVertical: false,
                    start: NSPoint(x: inset.minX, y: yDivider),
                    end: NSPoint(x: xDivider, y: yDivider),
                    center: NSPoint(x: (inset.minX + xDivider) / 2, y: yDivider)
                ),
                PreviewDivider(
                    isVertical: false,
                    start: NSPoint(x: xDivider, y: yDivider),
                    end: NSPoint(x: inset.maxX, y: yDivider),
                    center: NSPoint(x: (xDivider + inset.maxX) / 2, y: yDivider)
                )
            ]
        case .threeColumns:
            let first = inset.minX + inset.width / 3
            let second = inset.minX + inset.width * 2 / 3
            return [
                PreviewDivider(isVertical: true, start: NSPoint(x: first, y: inset.minY), end: NSPoint(x: first, y: inset.maxY), center: NSPoint(x: first, y: inset.midY)),
                PreviewDivider(isVertical: true, start: NSPoint(x: second, y: inset.minY), end: NSPoint(x: second, y: inset.maxY), center: NSPoint(x: second, y: inset.midY))
            ]
        case .threeRows:
            let first = inset.minY + inset.height / 3
            let second = inset.minY + inset.height * 2 / 3
            return [
                PreviewDivider(isVertical: false, start: NSPoint(x: inset.minX, y: first), end: NSPoint(x: inset.maxX, y: first), center: NSPoint(x: inset.midX, y: first)),
                PreviewDivider(isVertical: false, start: NSPoint(x: inset.minX, y: second), end: NSPoint(x: inset.maxX, y: second), center: NSPoint(x: inset.midX, y: second))
            ]
        }
    }

    private func section(at point: NSPoint) -> Section? {
        sections.first { $0.frame.contains(point) }
    }

    private func previewZoneRect(_ rect: CGRect) -> CGRect {
        safeRect(rect, minWidth: 24, minHeight: 24) ?? rect.standardized
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

private extension DesktopConfig.StackTabGlassStyle {
    var material: NSVisualEffectView.Material {
        switch self {
        case .crystalClear: return .underWindowBackground
        case .softFrost: return .sidebar
        case .milkyTitanium: return .menu
        case .graphiteSmoke: return .hudWindow
        }
    }

    var tintColor: NSColor {
        switch self {
        case .crystalClear:
            return NSColor(calibratedRed: 0.62, green: 0.80, blue: 0.98, alpha: 1)
        case .softFrost:
            return NSColor(calibratedRed: 0.55, green: 0.66, blue: 0.82, alpha: 1)
        case .milkyTitanium:
            return NSColor(calibratedRed: 0.70, green: 0.74, blue: 0.80, alpha: 1)
        case .graphiteSmoke:
            return NSColor(calibratedRed: 0.56, green: 0.64, blue: 0.74, alpha: 1)
        }
    }

    var containerFillColor: NSColor {
        switch self {
        case .crystalClear: return NSColor.white.withAlphaComponent(0.08)
        case .softFrost: return NSColor(calibratedWhite: 0.92, alpha: 0.10)
        case .milkyTitanium: return NSColor(calibratedRed: 0.86, green: 0.89, blue: 0.93, alpha: 0.18)
        case .graphiteSmoke: return NSColor.black.withAlphaComponent(0.24)
        }
    }

    var tabFillColor: NSColor {
        switch self {
        case .crystalClear: return NSColor.white.withAlphaComponent(0.11)
        case .softFrost: return NSColor(calibratedWhite: 0.96, alpha: 0.10)
        case .milkyTitanium: return NSColor(calibratedRed: 0.91, green: 0.93, blue: 0.96, alpha: 0.20)
        case .graphiteSmoke: return NSColor.white.withAlphaComponent(0.08)
        }
    }

    var activeFillColor: NSColor {
        tintColor.withAlphaComponent(self == .graphiteSmoke ? 0.28 : 0.20)
    }

    var borderColor: NSColor {
        switch self {
        case .crystalClear: return NSColor.white.withAlphaComponent(0.34)
        case .softFrost: return NSColor.white.withAlphaComponent(0.22)
        case .milkyTitanium: return NSColor.white.withAlphaComponent(0.26)
        case .graphiteSmoke: return NSColor.white.withAlphaComponent(0.18)
        }
    }

    var textColor: NSColor {
        self == .graphiteSmoke ? .white : .labelColor
    }

    var secondaryTextColor: NSColor {
        self == .graphiteSmoke ? NSColor.white.withAlphaComponent(0.72) : .secondaryLabelColor
    }
}

private final class StackTabButton: NSButton {
    var stackName: String = ""
    var tabIndex: Int = 0
    var glassStyle: DesktopConfig.StackTabGlassStyle = .softFrost {
        didSet { needsDisplay = true }
    }
    var isActiveTab: Bool = false {
        didSet { needsDisplay = true }
    }
    private var isHovered = false

    override var intrinsicContentSize: NSSize {
        let base = super.intrinsicContentSize
        return NSSize(width: min(max(base.width + 18, 58), 180), height: 22)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        (isActiveTab ? glassStyle.activeFillColor : glassStyle.tabFillColor).setFill()
        path.fill()

        if isHovered && !isActiveTab {
            NSColor.white.withAlphaComponent(0.08).setFill()
            path.fill()
        }

        (isActiveTab ? glassStyle.tintColor.withAlphaComponent(0.62) : glassStyle.borderColor).setStroke()
        path.lineWidth = isActiveTab ? 1.2 : 1
        path.stroke()

        let glint = NSBezierPath()
        glint.move(to: NSPoint(x: rect.minX + 10, y: rect.maxY - 1))
        glint.line(to: NSPoint(x: rect.maxX - 10, y: rect.maxY - 1))
        NSColor.white.withAlphaComponent(isActiveTab ? 0.22 : 0.12).setStroke()
        glint.lineWidth = 1
        glint.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 11, weight: isActiveTab ? .semibold : .regular),
            .foregroundColor: isActiveTab ? glassStyle.textColor : glassStyle.secondaryTextColor,
            .paragraphStyle: {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                paragraph.lineBreakMode = .byTruncatingTail
                return paragraph
            }()
        ]
        title.draw(in: rect.insetBy(dx: 8, dy: 4), withAttributes: attrs)
    }
}

private final class StackTabGlassStylePreviewCard: NSView {
    let style: DesktopConfig.StackTabGlassStyle
    var selected: Bool {
        didSet { needsDisplay = true }
    }
    var onSelect: ((DesktopConfig.StackTabGlassStyle) -> Void)?
    private var isHovered = false

    init(style: DesktopConfig.StackTabGlassStyle, selected: Bool) {
        self.style = style
        self.selected = selected
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 148))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        heightAnchor.constraint(equalToConstant: 148).isActive = true
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        onSelect?(style)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16)
        style.containerFillColor.setFill()
        path.fill()
        if isHovered {
            NSColor.white.withAlphaComponent(0.055).setFill()
            path.fill()
        }
        (selected ? style.tintColor.withAlphaComponent(0.68) : style.borderColor).setStroke()
        path.lineWidth = selected ? 1.4 : 1
        path.stroke()

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: style.textColor
        ]
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: style.secondaryTextColor
        ]
        style.title.draw(in: NSRect(x: 16, y: bounds.height - 34, width: bounds.width - 96, height: 18), withAttributes: titleAttrs)
        style.subtitle.draw(in: NSRect(x: 16, y: bounds.height - 54, width: bounds.width - 32, height: 16), withAttributes: subtitleAttrs)

        if selected {
            "已选择".draw(
                in: NSRect(x: bounds.width - 66, y: bounds.height - 34, width: 50, height: 18),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: style.tintColor
                ]
            )
        }

        drawSampleTabBar(in: NSRect(x: 16, y: 20, width: bounds.width - 32, height: 42))
    }

    private func drawSampleTabBar(in rect: NSRect) {
        let shell = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16)
        style.containerFillColor.setFill()
        shell.fill()
        style.borderColor.setStroke()
        shell.lineWidth = 1
        shell.stroke()

        let labels = ["1. 文稿", "2. 浏览器", "3. 终端"]
        let widths: [CGFloat] = [74, 88, 76]
        var x = rect.minX + 8
        for index in labels.indices {
            let tab = NSRect(x: x, y: rect.minY + 8, width: widths[index], height: 26)
            let tabPath = NSBezierPath(roundedRect: tab, xRadius: 13, yRadius: 13)
            (index == 1 ? style.activeFillColor : style.tabFillColor).setFill()
            tabPath.fill()
            (index == 1 ? style.tintColor.withAlphaComponent(0.64) : style.borderColor).setStroke()
            tabPath.lineWidth = index == 1 ? 1.2 : 1
            tabPath.stroke()
            labels[index].draw(
                in: tab.insetBy(dx: 9, dy: 6),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: index == 1 ? .semibold : .medium),
                    .foregroundColor: index == 1 ? style.textColor : style.secondaryTextColor
                ]
            )
            x += widths[index] + 8
        }
    }
}

private final class TitaniumBackgroundView: NSView {
    var appearanceMode: DesktopConfig.WorkbenchAppearance = .system {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let isDark: Bool
        switch appearanceMode {
        case .system:
            isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        case .titaniumLight:
            isDark = false
        case .titaniumDark:
            isDark = true
        }

        let top = isDark
            ? NSColor(calibratedRed: 0.085, green: 0.092, blue: 0.106, alpha: 1)
            : NSColor(calibratedRed: 0.84, green: 0.87, blue: 0.91, alpha: 1)
        let bottom = isDark
            ? NSColor(calibratedRed: 0.038, green: 0.043, blue: 0.052, alpha: 1)
            : NSColor(calibratedRed: 0.94, green: 0.955, blue: 0.972, alpha: 1)
        NSGradient(starting: top, ending: bottom)?.draw(in: bounds, angle: 90)

        let lineColor = isDark
            ? NSColor.white.withAlphaComponent(0.022)
            : NSColor.black.withAlphaComponent(0.024)
        lineColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        var y = bounds.minY
        while y < bounds.maxY {
            path.move(to: NSPoint(x: bounds.minX, y: y.rounded()))
            path.line(to: NSPoint(x: bounds.maxX, y: y.rounded()))
            y += 6
        }
        path.stroke()

        let glossRect = bounds.insetBy(dx: 0, dy: bounds.height * 0.45)
        if let gloss = NSGradient(
            colors: [
                NSColor.white.withAlphaComponent(isDark ? 0.02 : 0.10),
                NSColor.white.withAlphaComponent(0)
            ],
            atLocations: [0, 1],
            colorSpace: .deviceRGB
        ) {
            gloss.draw(in: glossRect, angle: 270)
        }

        let vignette = NSBezierPath(rect: bounds)
        (isDark ? NSColor.black.withAlphaComponent(0.16) : NSColor.white.withAlphaComponent(0.12)).setFill()
        vignette.fill()
    }
}

private final class BundleRoutingTypePopupButton: NSPopUpButton {
    var bundleId: String = ""
}

private final class TitleRuleRoutingTypePopupButton: NSPopUpButton {
    var ruleId: UUID?
}

private final class RoutingRuleRemoveButton: NSButton {
    var ruleId: UUID?
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
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
                // Neutral boundary for active zones; color is reserved for drop targets.
                let boundaryPath = NSBezierPath(roundedRect: zoneFrame, xRadius: 8, yRadius: 8)
                NSColor.labelColor.withAlphaComponent(0.20).setStroke()
                boundaryPath.lineWidth = 2
                boundaryPath.stroke()

                let fillPath = NSBezierPath(roundedRect: zoneFrame, xRadius: 8, yRadius: 8)
                NSColor.labelColor.withAlphaComponent(0.025).setFill()
                fillPath.fill()
            } else {
                // Faint boundary for inactive zones with rounded corners
                let boundaryPath = NSBezierPath(roundedRect: zoneFrame, xRadius: 8, yRadius: 8)
                NSColor.separatorColor.withAlphaComponent(0.34).setStroke()
                boundaryPath.lineWidth = 1.5
                boundaryPath.stroke()

                let fillPath = NSBezierPath(roundedRect: zoneFrame, xRadius: 8, yRadius: 8)
                NSColor.labelColor.withAlphaComponent(0.012).setFill()
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

private final class WindowSwitcherSearchField: NSSearchField {
    var onMoveSelection: ((Int) -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125:
            onMoveSelection?(1)
        case 126:
            onMoveSelection?(-1)
        case 36, 76:
            onCommit?()
        case 53:
            onCancel?()
        default:
            super.keyDown(with: event)
        }
    }
}

@MainActor
private final class WindowSwitcherResultRowView: NSView {
    let result: WindowSwitcherResult
    var onSelect: (() -> Void)?
    var isSelected = false {
        didSet { needsDisplay = true }
    }
    private var isHovered = false

    init(result: WindowSwitcherResult) {
        self.result = result
        super.init(frame: NSRect(x: 0, y: 0, width: 660, height: 76))
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 76).isActive = true
        wantsLayer = true
        toolTip = result.browserURL ?? result.window.title
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rowRect = bounds.insetBy(dx: 1, dy: 2)
        let path = NSBezierPath(roundedRect: rowRect, xRadius: 16, yRadius: 16)
        let fill: NSColor
        if isSelected {
            fill = NSColor.controlAccentColor.withAlphaComponent(0.20)
        } else if isHovered {
            fill = NSColor.white.withAlphaComponent(0.14)
        } else {
            fill = NSColor.white.withAlphaComponent(0.08)
        }
        fill.setFill()
        path.fill()

        let highlight = NSBezierPath(roundedRect: rowRect.insetBy(dx: 1, dy: 1), xRadius: 15, yRadius: 15)
        NSColor.white.withAlphaComponent(isSelected ? 0.22 : 0.12).setStroke()
        highlight.lineWidth = 0.6
        highlight.stroke()

        if isSelected {
            NSColor.controlAccentColor.withAlphaComponent(0.55).setStroke()
            path.lineWidth = 1.4
            path.stroke()
        }

        let iconBackRect = NSRect(x: 14, y: bounds.midY - 22, width: 44, height: 44)
        NSColor.white.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: iconBackRect, xRadius: 12, yRadius: 12).fill()

        let iconRect = iconBackRect.insetBy(dx: 5, dy: 5)
        if let icon = result.icon {
            icon.draw(in: iconRect)
        } else {
            NSColor.secondaryLabelColor.withAlphaComponent(0.20).setFill()
            NSBezierPath(roundedRect: iconRect, xRadius: 9, yRadius: 9).fill()
        }

        let appRect = NSRect(x: 72, y: 48, width: bounds.width - 190, height: 15)
        result.appTitle.draw(
            in: appRect,
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: truncatingParagraph()
            ]
        )

        let titleRect = NSRect(x: 72, y: 27, width: bounds.width - 190, height: 18)
        result.windowTitle.draw(
            in: titleRect,
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: truncatingParagraph()
            ]
        )

        let detailRect = NSRect(x: 72, y: 10, width: bounds.width - 190, height: 14)
        result.detailText.draw(
            in: detailRect,
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: truncatingParagraph()
            ]
        )

        let tag = result.browserURL == nil ? "Window" : "Active Tab"
        let tagRect = NSRect(x: bounds.width - 102, y: bounds.midY - 12, width: 86, height: 24)
        let tagPath = NSBezierPath(roundedRect: tagRect, xRadius: 12, yRadius: 12)
        (isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.14) : NSColor.white.withAlphaComponent(0.10)).setFill()
        tagPath.fill()
        tag.draw(
            in: tagRect.insetBy(dx: 8, dy: 5),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: isSelected ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor,
                .paragraphStyle: centeredParagraph()
            ]
        )
    }

    private func truncatingParagraph() -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byTruncatingTail
        return paragraph
    }

    private func centeredParagraph() -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        return paragraph
    }
}

private final class ShortcutActionButton: NSButton {
    let shortcutAction: WorkbenchShortcutAction

    init(shortcutAction: WorkbenchShortcutAction, title: String, target: AnyObject?, action: Selector?) {
        self.shortcutAction = shortcutAction
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
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
        super.init(frame: NSRect(x: 0, y: 0, width: 216, height: 38))
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 38).isActive = true
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
        let pillRect = bounds.insetBy(dx: 4, dy: 3)
        let pill = NSBezierPath(roundedRect: pillRect, xRadius: 10, yRadius: 10)

        if isSelected {
            NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
            pill.fill()
        } else if isHovered {
            NSColor.labelColor.withAlphaComponent(0.05).setFill()
            pill.fill()
        }

        let iconSize: CGFloat = 18
        let iconX: CGFloat = 18
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
            in: NSRect(x: 44, y: (bounds.height - 16) / 2, width: bounds.width - 56, height: 16),
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
