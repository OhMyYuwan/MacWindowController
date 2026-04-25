import Foundation

enum CLIError: LocalizedError {
    case missingCommand
    case missingRequiredArgument(String)
    case invalidArgument(String)
    case unsupportedCommand(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingCommand:
            return "No command provided."
        case .missingRequiredArgument(let flag):
            return "Missing required argument: \(flag)"
        case .invalidArgument(let message):
            return "Invalid argument: \(message)"
        case .unsupportedCommand(let command):
            return "Unsupported command: \(command)"
        case .commandFailed(let message):
            return message
        }
    }
}

@MainActor
final class WindowManagerCLI {
    private let windowController = WindowController()
    private let screenManager = ScreenManager()
    private lazy var stackManager = StackManager(windowController: windowController, screenManager: screenManager)
    private let layoutStore = DesktopLayoutStore()
    private lazy var layoutCoordinator = DesktopLayoutCoordinator(
        windowController: windowController,
        stackManager: stackManager,
        store: layoutStore
    )

    func run(arguments: [String]) throws {
        guard arguments.count > 1 else {
            runOpenWorkbench(focusedLayoutName: nil)
            return
        }

        let command = arguments[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parser = ArgumentParser(tokens: Array(arguments.dropFirst(2)))

        switch command {
        case "help", "--help", "-h":
            printHelp()
        case "launch-app", "open-app":
            try runLaunchApp(parser: parser)
        case "launch-chrome-windows", "open-chrome-windows":
            try runLaunchChromeWindows(parser: parser)
        case "list":
            try runList(parser: parser, wrapJSONResponse: false)
        case "list-windows":
            try runList(parser: parser, wrapJSONResponse: true)
        case "move", "move-window":
            try runMove(parser: parser)
        case "resize", "resize-window":
            try runResize(parser: parser)
        case "tile", "tile-window":
            try runTile(parser: parser)
        case "place-window":
            try runPlaceWindow(parser: parser)
        case "tile-frontmost":
            try runTileFrontmost(parser: parser)
        case "bucket-left-frontmost":
            try runBucketLeftFrontmost(parser: parser)
        case "create-stack":
            try runCreateStack(parser: parser)
        case "switch-stack":
            try runSwitchStack(parser: parser)
        case "list-stacks":
            try runListStacks(parser: parser)
        case "delete-stack":
            try runDeleteStack(parser: parser)
        case "save-desktop", "save-layout":
            try runSaveDesktop(parser: parser)
        case "edit-current":
            try runEditCurrent(parser: parser)
        case "list-desktops", "list-layouts":
            try runListDesktops(parser: parser)
        case "apply-desktop", "restore-layout":
            try runApplyDesktop(parser: parser)
        case "delete-desktop", "delete-layout":
            try runDeleteDesktop(parser: parser)
        case "export-desktop":
            try runExportDesktop(parser: parser)
        case "import-desktop":
            try runImportDesktop(parser: parser)
        case "edit-desktop":
            try runEditDesktop(parser: parser)
        case "open-workbench":
            runOpenWorkbench(focusedLayoutName: parser.value(for: "--layout"))
        default:
            throw CLIError.unsupportedCommand(command)
        }
    }

    private func runList(parser: ArgumentParser, wrapJSONResponse: Bool) throws {
        let windows = windowController.listWindows(onScreenOnly: !parser.hasFlag("--all"))
        if parser.hasFlag("--json") {
            if wrapJSONResponse {
                try printJSON(WindowListResponse(windows: windows))
            } else {
                try printJSON(windows)
            }
            return
        }

        if windows.isEmpty {
            print("No windows found.")
            return
        }

        for window in windows {
            let title = window.title.isEmpty ? "<untitled>" : window.title
            print("[\(window.bundleId)] #\(window.windowNumber) \(title) \(window.frame.width)x\(window.frame.height) @ (\(window.frame.x), \(window.frame.y))")
        }
    }

    private func runLaunchApp(parser: ArgumentParser) throws {
        let bundleId = try parser.requiredValue(for: "--bundle-id")
        let activate = !parser.hasFlag("--background")
        try windowController.launchApp(bundleId: bundleId, activate: activate)
        if parser.hasFlag("--json") {
            try printJSON(OperationResult(operation: "launch-app", bundleId: bundleId, status: "ok"))
            return
        }
        print("Launched \(bundleId).")
    }

    private func runLaunchChromeWindows(parser: ArgumentParser) throws {
        let count = parser.intValue(for: "--count") ?? 1
        guard count > 0 else {
            throw CLIError.invalidArgument("--count must be > 0")
        }

        try windowController.launchApp(bundleId: "com.google.Chrome", activate: true)
        try openChromeWindows(count: count)

        if parser.hasFlag("--json") {
            try printJSON(
                LaunchWindowsResult(
                    operation: "launch-chrome-windows",
                    bundleId: "com.google.Chrome",
                    count: count,
                    status: "ok"
                )
            )
            return
        }
        print("Opened \(count) Chrome window(s).")
    }

    private func runMove(parser: ArgumentParser) throws {
        let bundleId = try parser.requiredValue(for: "--bundle-id")
        let x = try parser.requiredDouble(for: "--x")
        let y = try parser.requiredDouble(for: "--y")
        let windowIndex = parser.intValue(for: "--window-index") ?? 0
        try windowController.moveWindow(
            bundleId: bundleId,
            windowIndex: windowIndex,
            to: CGPoint(x: x, y: y)
        )
        if parser.hasFlag("--json") {
            try printJSON(OperationResult(operation: "move-window", bundleId: bundleId, status: "ok"))
            return
        }
        print("Moved \(bundleId) to (\(x), \(y)).")
    }

    private func runResize(parser: ArgumentParser) throws {
        let bundleId = try parser.requiredValue(for: "--bundle-id")
        let width = try parser.requiredDouble(for: "--width")
        let height = try parser.requiredDouble(for: "--height")
        let windowIndex = parser.intValue(for: "--window-index") ?? 0
        try windowController.resizeWindow(
            bundleId: bundleId,
            windowIndex: windowIndex,
            to: CGSize(width: width, height: height)
        )
        if parser.hasFlag("--json") {
            try printJSON(OperationResult(operation: "resize-window", bundleId: bundleId, status: "ok"))
            return
        }
        print("Resized \(bundleId) to \(width)x\(height).")
    }

    private func runTile(parser: ArgumentParser) throws {
        let bundleId = try parser.requiredValue(for: "--bundle-id")
        let positionRaw = try parser.requiredValue(for: "--position")
        guard let position = TilePosition.parse(positionRaw) else {
            throw CLIError.invalidArgument("--position must be one of \(TilePosition.allCases.map(\.rawValue).joined(separator: ", "))")
        }

        let displayIndex = parser.intValue(for: "--display-index")
        let windowIndex = parser.intValue(for: "--window-index") ?? 0
        let frame = screenManager.visibleFrame(displayIndex: displayIndex)
        try windowController.tileWindow(bundleId: bundleId, position: position, in: frame, windowIndex: windowIndex)
        if parser.hasFlag("--json") {
            try printJSON(OperationResult(operation: "tile-window", bundleId: bundleId, status: "ok"))
            return
        }
        print("Tiled \(bundleId) to \(position.rawValue).")
    }

    private func runPlaceWindow(parser: ArgumentParser) throws {
        let bundleId = try parser.requiredValue(for: "--bundle-id")
        let zoneRaw = try parser.requiredValue(for: "--zone")
        guard let position = TilePosition.parse(zoneRaw) else {
            throw CLIError.invalidArgument("--zone must be one of left/right/left-up/left-down/right-up/right-down or TilePosition values")
        }

        let windowIndex: Int
        if let explicit = parser.intValue(for: "--window-index") {
            windowIndex = explicit
        } else if let windowNumber = parser.intValue(for: "--window-number") {
            guard let matched = try windowController.findWindowIndex(bundleId: bundleId, windowNumber: windowNumber) else {
                throw CLIError.invalidArgument("No window matched window-number: \(windowNumber)")
            }
            windowIndex = matched
        } else if let titleQuery = parser.value(for: "--window-title-contains") {
            guard let matched = try windowController.findWindowIndex(bundleId: bundleId, titleContains: titleQuery) else {
                throw CLIError.invalidArgument("No window matched title query: \(titleQuery)")
            }
            windowIndex = matched
        } else {
            windowIndex = 0
        }

        let displayIndex = parser.intValue(for: "--display-index")
        let frame = screenManager.visibleFrame(displayIndex: displayIndex)
        try windowController.tileWindow(
            bundleId: bundleId,
            position: position,
            in: frame,
            windowIndex: windowIndex
        )

        if parser.hasFlag("--json") {
            try printJSON(
                WindowPlacementResult(
                    operation: "place-window",
                    bundleId: bundleId,
                    position: position.rawValue,
                    windowIndex: windowIndex,
                    status: "ok"
                )
            )
            return
        }
        print("Placed \(bundleId) window[\(windowIndex)] in \(position.rawValue).")
    }

    private func runTileFrontmost(parser: ArgumentParser) throws {
        let positionRaw = try parser.requiredValue(for: "--position")
        guard let position = TilePosition.parse(positionRaw) else {
            throw CLIError.invalidArgument("--position must be one of \(TilePosition.allCases.map(\.rawValue).joined(separator: ", "))")
        }

        guard let identity = windowController.frontmostWindowIdentity() else {
            throw CLIError.invalidArgument("No frontmost window found")
        }
        let frame = screenManager.mainVisibleFrame()
        let targetFrame = LayoutEngine().frame(for: position, in: frame)
        if let windowNumber = identity.windowNumber {
            try windowController.setWindowFrame(bundleId: identity.bundleId, windowNumber: windowNumber, frame: targetFrame)
        } else {
            try windowController.tileWindow(bundleId: identity.bundleId, position: position, in: frame, windowIndex: 0)
        }
        if parser.hasFlag("--json") {
            try printJSON(OperationResult(operation: "tile-frontmost", bundleId: identity.bundleId, status: "ok"))
            return
        }
        print("Tiled frontmost \(identity.bundleId) to \(position.rawValue).")
    }

    private func runBucketLeftFrontmost(parser: ArgumentParser) throws {
        guard let identity = windowController.frontmostWindowIdentity() else {
            throw CLIError.invalidArgument("No frontmost window found")
        }
        let frame = LayoutEngine().frame(for: .left, in: screenManager.mainVisibleFrame())
        _ = try stackManager.putWindowInStack(name: "left-bucket", frame: frame, window: identity)
        if parser.hasFlag("--json") {
            try printJSON(OperationResult(operation: "bucket-left-frontmost", bundleId: identity.bundleId, status: "ok"))
            return
        }
        print("Added frontmost \(identity.bundleId) into left-bucket.")
    }

    private func runCreateStack(parser: ArgumentParser) throws {
        let name = try parser.requiredValue(for: "--name")
        let positionRaw = try parser.requiredValue(for: "--position")
        let windowsRaw = try parser.requiredValue(for: "--windows")

        guard let position = TilePosition.parse(positionRaw) else {
            throw CLIError.invalidArgument("--position must be one of \(TilePosition.allCases.map(\.rawValue).joined(separator: ", "))")
        }

        let bundleIds = windowsRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let displayIndex = parser.intValue(for: "--display-index")

        let stack = try stackManager.createStack(
            name: name,
            position: position,
            windows: bundleIds,
            displayIndex: displayIndex
        )
        if parser.hasFlag("--json") {
            try printJSON(stack)
            return
        }
        print("Created stack '\(stack.name)' with \(stack.windows.count) windows.")
    }

    private func runSwitchStack(parser: ArgumentParser) throws {
        let name = try parser.requiredValue(for: "--name")
        let index = try parser.requiredInt(for: "--index")
        try stackManager.switchStack(name: name, index: index)
        print("Switched stack '\(name)' to window index \(index).")
    }

    private func runListStacks(parser: ArgumentParser) throws {
        let stacks = stackManager.listStacks()
        if parser.hasFlag("--json") {
            try printJSON(stacks)
            return
        }
        if stacks.isEmpty {
            print("No stacks found.")
            return
        }
        for stack in stacks {
            print("\(stack.name): \(stack.windows.count) windows, active index \(stack.activeIndex)")
        }
    }

    private func runDeleteStack(parser: ArgumentParser) throws {
        let name = try parser.requiredValue(for: "--name")
        try stackManager.deleteStack(name: name)
        print("Deleted stack '\(name)'.")
    }

    private func runSaveDesktop(parser: ArgumentParser) throws {
        let name = try parser.requiredValue(for: "--name")
        let description = parser.value(for: "--description") ?? ""
        let layout = try layoutCoordinator.saveCurrentDesktop(name: name, description: description)
        if parser.hasFlag("--json") {
            try printJSON(layout)
            return
        }
        print("Saved desktop layout '\(layout.name)'.")
    }

    private func runListDesktops(parser: ArgumentParser) throws {
        let layouts = layoutCoordinator.listDesktops()
        if parser.hasFlag("--json") {
            try printJSON(DesktopLayoutListResponse(desktops: layouts))
            return
        }
        if layouts.isEmpty {
            print("No desktop layouts found.")
            return
        }
        for layout in layouts {
            print("\(layout.name) (\(layout.windows.count) windows, \(layout.stacks.count) stacks)")
        }
    }

    private func runApplyDesktop(parser: ArgumentParser) throws {
        let name = try parser.requiredValue(for: "--name")
        try layoutCoordinator.applyDesktop(name: name)
        if parser.hasFlag("--json") {
            try printJSON(OperationResult(operation: "apply-desktop", bundleId: name, status: "ok"))
            return
        }
        print("Applied desktop layout '\(name)'.")
    }

    private func runDeleteDesktop(parser: ArgumentParser) throws {
        let name = try parser.requiredValue(for: "--name")
        try layoutCoordinator.deleteDesktop(name: name)
        if parser.hasFlag("--json") {
            try printJSON(OperationResult(operation: "delete-desktop", bundleId: name, status: "ok"))
            return
        }
        print("Deleted desktop layout '\(name)'.")
    }

    private func runExportDesktop(parser: ArgumentParser) throws {
        let name = try parser.requiredValue(for: "--name")
        let output = try parser.requiredValue(for: "--output")
        let outputURL = URL(fileURLWithPath: (output as NSString).expandingTildeInPath)
        try layoutCoordinator.exportDesktop(name: name, to: outputURL)
        if parser.hasFlag("--json") {
            try printJSON(OperationResult(operation: "export-desktop", bundleId: name, status: "ok"))
            return
        }
        print("Exported desktop '\(name)' to \(outputURL.path).")
    }

    private func runImportDesktop(parser: ArgumentParser) throws {
        let file = try parser.requiredValue(for: "--file")
        let fileURL = URL(fileURLWithPath: (file as NSString).expandingTildeInPath)
        let layout = try layoutCoordinator.importDesktop(from: fileURL)
        if parser.hasFlag("--json") {
            try printJSON(layout)
            return
        }
        print("Imported desktop layout '\(layout.name)'.")
    }

    private func runEditDesktop(parser: ArgumentParser) throws {
        let name = try parser.requiredValue(for: "--name")
        let description = parser.value(for: "--description") ?? ""
        let createIfMissing = parser.hasFlag("--create-if-missing")

        let layout: DesktopLayout
        do {
            layout = try layoutCoordinator.loadDesktop(name: name)
        } catch {
            guard createIfMissing else { throw error }
            layout = try layoutCoordinator.saveCurrentDesktop(name: name, description: description)
        }
        runOpenWorkbench(focusedLayoutName: layout.name)
    }

    private func runEditCurrent(parser: ArgumentParser) throws {
        let name = try parser.requiredValue(for: "--name")
        let description = parser.value(for: "--description") ?? ""
        _ = try layoutCoordinator.saveCurrentDesktop(name: name, description: description)
        runOpenWorkbench(focusedLayoutName: name)
    }

    private func runOpenWorkbench(focusedLayoutName: String?) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                DesktopWorkbenchLauncher.open(
                    windowController: windowController,
                    stackManager: stackManager,
                    layoutCoordinator: layoutCoordinator,
                    layoutStore: layoutStore,
                    screenManager: screenManager,
                    focusedLayoutName: focusedLayoutName
                )
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    DesktopWorkbenchLauncher.open(
                        windowController: windowController,
                        stackManager: stackManager,
                        layoutCoordinator: layoutCoordinator,
                        layoutStore: layoutStore,
                        screenManager: screenManager,
                        focusedLayoutName: focusedLayoutName
                    )
                }
            }
        }
    }

    private func printHelp() {
        print(
            """
            window-manager commands:
              launch-app --bundle-id <id> [--background] [--json]
              launch-chrome-windows [--count N] [--json]
              list [--json] [--all]
              list-windows [--json] [--all]
              move --bundle-id <id> --x <N> --y <N> [--window-index N] [--json]
              move-window --bundle-id <id> --x <N> --y <N> [--window-index N] [--json]
              resize --bundle-id <id> --width <N> --height <N> [--window-index N] [--json]
              resize-window --bundle-id <id> --width <N> --height <N> [--window-index N] [--json]
              tile --bundle-id <id> --position <left|right|top|bottom|fullscreen|top-left|top-right|bottom-left|bottom-right> [--display-index N] [--window-index N]
              tile-window --bundle-id <id> --position <left|right|top|bottom|fullscreen|top-left|top-right|bottom-left|bottom-right> [--display-index N] [--window-index N]
              place-window --bundle-id <id> --zone <left|left-up|left-down|right|right-up|right-down> [--window-index N | --window-number N | --window-title-contains <text>] [--display-index N] [--json]
              tile-frontmost --position <position> [--json]
              bucket-left-frontmost [--json]
              create-stack --name <name> --position <position> --windows <bundle1,bundle2,...> [--display-index N] [--json]
              switch-stack --name <name> --index <N>
              list-stacks [--json]
              delete-stack --name <name>

              save-desktop --name <name> [--description <text>] [--json]
              save-layout --name <name> [--description <text>] [--json]
              edit-current --name <name> [--description <text>]
              list-desktops [--json]
              list-layouts [--json]
              apply-desktop --name <name> [--json]
              restore-layout --name <name>
              delete-desktop --name <name> [--json]
              delete-layout --name <name>
              export-desktop --name <name> --output <path> [--json]
              import-desktop --file <path> [--json]
              edit-desktop --name <name> [--create-if-missing] [--description <text>]
              open-workbench [--layout <name>]
            """
        )
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
            throw CLIError.commandFailed("Failed to open Chrome windows: \(message)")
        }
    }

    private func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        if let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }
}

private struct WindowListResponse: Encodable {
    var windows: [WindowInfo]
}

private struct OperationResult: Encodable {
    var operation: String
    var bundleId: String
    var status: String
}

private struct WindowPlacementResult: Encodable {
    var operation: String
    var bundleId: String
    var position: String
    var windowIndex: Int
    var status: String
}

private struct LaunchWindowsResult: Encodable {
    var operation: String
    var bundleId: String
    var count: Int
    var status: String
}

private struct ArgumentParser {
    private let tokens: [String]

    init(tokens: [String]) {
        self.tokens = tokens
    }

    func value(for flag: String) -> String? {
        guard let index = tokens.firstIndex(of: flag) else {
            return nil
        }
        let valueIndex = index + 1
        guard tokens.indices.contains(valueIndex) else {
            return nil
        }
        let value = tokens[valueIndex]
        if value.hasPrefix("--") {
            return nil
        }
        return value
    }

    func intValue(for flag: String) -> Int? {
        guard let raw = value(for: flag) else { return nil }
        return Int(raw)
    }

    func hasFlag(_ flag: String) -> Bool {
        tokens.contains(flag)
    }

    func requiredValue(for flag: String) throws -> String {
        guard let value = value(for: flag) else {
            throw CLIError.missingRequiredArgument(flag)
        }
        return value
    }

    func requiredInt(for flag: String) throws -> Int {
        guard let raw = value(for: flag), let value = Int(raw) else {
            throw CLIError.invalidArgument("\(flag) requires an integer")
        }
        return value
    }

    func requiredDouble(for flag: String) throws -> Double {
        guard let raw = value(for: flag), let value = Double(raw) else {
            throw CLIError.invalidArgument("\(flag) requires a number")
        }
        return value
    }
}
