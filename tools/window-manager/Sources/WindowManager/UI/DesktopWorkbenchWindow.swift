import AppKit
import Foundation

@MainActor
enum DesktopMergeMode: Int, CaseIterable {
    case grid = 0
    case leftColumn
    case rightColumn
    case topRow
    case bottomRow

    var title: String {
        switch self {
        case .grid: return "四分"
        case .leftColumn: return "左合并"
        case .rightColumn: return "右合并"
        case .topRow: return "上合并"
        case .bottomRow: return "下合并"
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
    private var mergeMode: DesktopMergeMode = .leftColumn
    private var leftBucketEnabled = true
    private var autoScanEnabled = false
    private var selectedLayoutName: String?
    private var lastExternalWindowIdentity: WindowIdentity?

    private var window: NSWindow?
    private var desktopView: DesktopContainerView?
    private var layoutNameField: NSTextField?
    private var appBundleIdField: NSTextField?
    private var chromeWindowCountField: NSTextField?
    private var mergeControl: NSSegmentedControl?
    private var statusLabel: NSTextField?
    private var noteScrollView: NSScrollView?
    private var noteStackView: NSStackView?
    private var stackPanels: [String: NSPanel] = [:]
    private var stackPanelTabStacks: [String: NSStackView] = [:]
    private var refreshTimer: Timer?
    private var keyboardMonitor: Any?

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
            contentRect: NSRect(x: 100, y: 80, width: 1280, height: 860),
            styleMask: [.titled, .resizable, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Window Manager Workbench"
        window.center()
        window.delegate = self
        self.window = window

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root

        let title = NSTextField(labelWithString: "桌面容器工作台")
        title.font = NSFont.systemFont(ofSize: 21, weight: .bold)

        let shortcutsRow = NSStackView()
        shortcutsRow.orientation = .horizontal
        shortcutsRow.spacing = 8
        shortcutsRow.distribution = .fillProportionally

        shortcutsRow.addArrangedSubview(makeButton("左半屏 ⌥⌘←", action: #selector(tileFrontmostLeft)))
        shortcutsRow.addArrangedSubview(makeButton("右半屏 ⌥⌘→", action: #selector(tileFrontmostRight)))
        shortcutsRow.addArrangedSubview(makeButton("上半屏 ⌥⌘↑", action: #selector(tileFrontmostTop)))
        shortcutsRow.addArrangedSubview(makeButton("下半屏 ⌥⌘↓", action: #selector(tileFrontmostBottom)))
        shortcutsRow.addArrangedSubview(makeButton("加入左桶", action: #selector(addFrontmostToLeftBucket)))

        let bucketToggle = NSButton(checkboxWithTitle: "左半屏使用桶堆叠", target: self, action: #selector(toggleLeftBucket))
        bucketToggle.state = .on
        shortcutsRow.addArrangedSubview(bucketToggle)
        shortcutsRow.addArrangedSubview(makeButton("立即扫描", action: #selector(runAutoScan)))

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
        mergeControl.selectedSegment = mergeMode.rawValue
        self.mergeControl = mergeControl

        let desktopView = DesktopContainerView(displayFrame: screenManager.mainVisibleFrame())
        desktopView.translatesAutoresizingMaskIntoConstraints = false
        desktopView.heightAnchor.constraint(equalToConstant: 460).isActive = true
        desktopView.onBucketTabSelected = { [weak self] index in
            self?.switchLeftBucket(to: index)
        }
        self.desktopView = desktopView

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

        root.addArrangedSubview(title)
        root.addArrangedSubview(shortcutsRow)
        root.addArrangedSubview(launcherRow)
        root.addArrangedSubview(mergeControl)
        root.addArrangedSubview(desktopView)
        root.addArrangedSubview(statusLabel)
        root.addArrangedSubview(saveRow)
        root.addArrangedSubview(noteScroll)

        window.makeKeyAndOrderFront(nil)

        installKeyboardShortcuts()
        startRefreshTimer()
        refreshWorkbench()
        if let focusedLayoutName {
            selectedLayoutName = focusedLayoutName
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
        }
        refreshTimer?.invalidate()
        for panel in stackPanels.values { panel.close() }
        stackPanels.removeAll()
        NSApplication.shared.terminate(nil)
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refreshWorkbench()
            }
        }
    }

    private func installKeyboardShortcuts() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
            guard flags.contains(.command), flags.contains(.option) else { return event }

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
    }

    private func refreshWorkbench() {
        if let identity = windowController.frontmostWindowIdentity(ignoringCurrentProcess: true) {
            lastExternalWindowIdentity = identity
        }
        let windows = windowController.listWindows(onScreenOnly: true)
        let leftBucket = stackManager.stack(named: leftBucketName)
        desktopView?.update(
            windows: windows,
            leftBucket: leftBucket,
            mergeMode: mergeMode,
            leftBucketEnabled: leftBucketEnabled
        )
        refreshAllStackPanels()
        reloadLayoutCards()
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
            setStatus("左桶模式已开启：左半屏将使用标签桶堆叠", error: false)
        } else {
            setStatus("左桶模式已关闭：左半屏恢复普通平铺", error: false)
        }
        refreshWorkbench()
    }

    @objc
    private func changeMergeMode(_ sender: NSSegmentedControl) {
        mergeMode = DesktopMergeMode(rawValue: sender.selectedSegment) ?? .grid
        setStatus("切分模式：\(mergeMode.title)", error: false)
        refreshWorkbench()
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
        return button
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
        panel.orderFrontRegardless()
    }

    private func makeStackPanel() -> (NSPanel, NSStackView) {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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

    private let displayFrame: CGRect
    private var sections: [Section] = []
    private var tabHitAreas: [TabHitArea] = []
    var onBucketTabSelected: ((Int) -> Void)?

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
        let map = Dictionary(grouping: windows) { classify(window: $0) }
        sections = buildSections(for: mergeMode).map { descriptor in
            let sectionWindows = descriptor.quadrants.flatMap { map[$0] ?? [] }
            if descriptor.isLeftArea, leftBucketEnabled {
                let tabs = leftBucket?.windows.map { $0.title.isEmpty ? $0.bundleId : $0.title } ?? []
                let activeTabIndex = leftBucket?.activeIndex ?? 0
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
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        tabHitAreas.removeAll()
        for section in sections {
            tabHitAreas.append(contentsOf: drawSection(section))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if let hitArea = tabHitAreas.first(where: { $0.rect.contains(location) }) {
            onBucketTabSelected?(hitArea.index)
            return
        }
        super.mouseDown(with: event)
    }

    private func drawSection(_ section: Section) -> [TabHitArea] {
        let path = NSBezierPath(roundedRect: section.frame, xRadius: 10, yRadius: 10)
        (section.isBucket ? NSColor.systemBlue.withAlphaComponent(0.2) : NSColor.systemGray.withAlphaComponent(0.14)).setFill()
        path.fill()
        (section.isBucket ? NSColor.systemBlue.withAlphaComponent(0.7) : NSColor.systemGray.withAlphaComponent(0.45)).setStroke()
        path.lineWidth = 1.5
        path.stroke()

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        section.title.draw(
            in: NSRect(x: section.frame.minX + 10, y: section.frame.maxY - 24, width: section.frame.width - 20, height: 16),
            withAttributes: titleAttrs
        )

        if section.isBucket {
            return drawTabs(
                section.tabs,
                activeIndex: section.activeTabIndex,
                in: section.frame.insetBy(dx: 8, dy: 28)
            )
        } else {
            drawStackList(section.windows, in: section.frame.insetBy(dx: 10, dy: 28))
            return []
        }
    }

    private func drawTabs(_ tabs: [String], activeIndex: Int, in rect: CGRect) -> [TabHitArea] {
        var hitAreas: [TabHitArea] = []
        let tabBarRect = CGRect(x: rect.minX, y: rect.maxY - 30, width: rect.width, height: 24)
        let bar = NSBezierPath(roundedRect: tabBarRect, xRadius: 6, yRadius: 6)
        NSColor.systemBlue.withAlphaComponent(0.16).setFill()
        bar.fill()

        if tabs.isEmpty {
            drawPlaceholder("空桶（点击“加入左桶”或将窗口平铺到左侧）", in: rect.insetBy(dx: 4, dy: 6))
            return hitAreas
        }

        let safeActiveIndex = min(max(activeIndex, 0), tabs.count - 1)
        var x = rect.minX
        let topY = rect.maxY - 30
        for (index, tab) in tabs.prefix(6).enumerated() {
            let label = "\(index + 1). \(tab)"
            let width = min(140, max(80, CGFloat(label.count) * 7.2))
            let tabRect = CGRect(x: x, y: topY, width: width, height: 22)
            let p = NSBezierPath(roundedRect: tabRect, xRadius: 6, yRadius: 6)
            let isActive = index == safeActiveIndex
            (isActive ? NSColor.systemBlue.withAlphaComponent(0.56) : NSColor.systemBlue.withAlphaComponent(0.28)).setFill()
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
            x += width + 6
            if x > rect.maxX - 70 { break }
        }

        let infoAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let activeTitle = tabs[safeActiveIndex]
        "当前标签：\(activeTitle)（点击上方标签切换）".draw(
            in: NSRect(x: rect.minX + 2, y: rect.maxY - 52, width: rect.width - 6, height: 16),
            withAttributes: infoAttrs
        )
        return hitAreas
    }

    private func drawStackList(_ windows: [WindowInfo], in rect: CGRect) {
        if windows.isEmpty {
            drawPlaceholder("空区域", in: rect)
            return
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        var y = rect.maxY - 20
        for window in windows.prefix(8) {
            let title = window.title.isEmpty ? window.appName : "\(window.appName) - \(window.title)"
            title.draw(in: NSRect(x: rect.minX, y: y, width: rect.width - 4, height: 14), withAttributes: attrs)
            y -= 15
            if y < rect.minY { break }
        }
    }

    private func drawPlaceholder(_ text: String, in rect: CGRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        text.draw(
            in: NSRect(x: rect.minX, y: rect.midY - 7, width: rect.width, height: 14),
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
        let inset = bounds.insetBy(dx: 10, dy: 10)
        let spacing: CGFloat = 10
        let halfW = (inset.width - spacing) / 2
        let halfH = (inset.height - spacing) / 2

        let tl = CGRect(x: inset.minX, y: inset.midY + spacing / 2, width: halfW, height: halfH)
        let tr = CGRect(x: inset.midX + spacing / 2, y: inset.midY + spacing / 2, width: halfW, height: halfH)
        let bl = CGRect(x: inset.minX, y: inset.minY, width: halfW, height: halfH)
        let br = CGRect(x: inset.midX + spacing / 2, y: inset.minY, width: halfW, height: halfH)

        switch mode {
        case .grid:
            return [
                ("左上", tl, [.tl], true),
                ("右上", tr, [.tr], false),
                ("左下", bl, [.bl], true),
                ("右下", br, [.br], false)
            ]
        case .leftColumn:
            let left = CGRect(x: inset.minX, y: inset.minY, width: halfW, height: inset.height)
            return [
                ("左侧大块", left, [.tl, .bl], true),
                ("右上", tr, [.tr], false),
                ("右下", br, [.br], false)
            ]
        case .rightColumn:
            let right = CGRect(x: inset.midX + spacing / 2, y: inset.minY, width: halfW, height: inset.height)
            return [
                ("左上", tl, [.tl], true),
                ("左下", bl, [.bl], true),
                ("右侧大块", right, [.tr, .br], false)
            ]
        case .topRow:
            let top = CGRect(x: inset.minX, y: inset.midY + spacing / 2, width: inset.width, height: halfH)
            return [
                ("上方大块", top, [.tl, .tr], true),
                ("左下", bl, [.bl], true),
                ("右下", br, [.br], false)
            ]
        case .bottomRow:
            let bottom = CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: halfH)
            return [
                ("左上", tl, [.tl], true),
                ("右上", tr, [.tr], false),
                ("下方大块", bottom, [.bl, .br], true)
            ]
        }
    }
}

private final class StackTabButton: NSButton {
    var stackName: String = ""
    var tabIndex: Int = 0
}
