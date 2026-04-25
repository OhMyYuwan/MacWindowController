import Foundation

enum CLIError: LocalizedError {
    case missingCommand
    case missingRequiredArgument(String)
    case invalidArgument(String)
    case unsupportedCommand(String)

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
            printHelp()
            return
        }

        let command = arguments[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parser = ArgumentParser(tokens: Array(arguments.dropFirst(2)))

        switch command {
        case "help", "--help", "-h":
            printHelp()
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
        print("Applied desktop layout '\(name)'.")
    }

    private func runDeleteDesktop(parser: ArgumentParser) throws {
        let name = try parser.requiredValue(for: "--name")
        try layoutCoordinator.deleteDesktop(name: name)
        print("Deleted desktop layout '\(name)'.")
    }

    private func runExportDesktop(parser: ArgumentParser) throws {
        let name = try parser.requiredValue(for: "--name")
        let output = try parser.requiredValue(for: "--output")
        let outputURL = URL(fileURLWithPath: (output as NSString).expandingTildeInPath)
        try layoutCoordinator.exportDesktop(name: name, to: outputURL)
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
        let layout = try layoutCoordinator.loadDesktop(name: name)
        let frame = screenManager.mainVisibleFrame()
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                LayoutEditorLauncher.open(layout: layout, store: layoutStore, displayFrame: frame)
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    LayoutEditorLauncher.open(layout: layout, store: layoutStore, displayFrame: frame)
                }
            }
        }
    }

    private func printHelp() {
        print(
            """
            window-manager commands:
              list [--json] [--all]
              list-windows [--json] [--all]
              move --bundle-id <id> --x <N> --y <N> [--window-index N] [--json]
              move-window --bundle-id <id> --x <N> --y <N> [--window-index N] [--json]
              resize --bundle-id <id> --width <N> --height <N> [--window-index N] [--json]
              resize-window --bundle-id <id> --width <N> --height <N> [--window-index N] [--json]
              tile --bundle-id <id> --position <left|right|top|bottom|fullscreen|top-left|top-right|bottom-left|bottom-right> [--display-index N] [--window-index N]
              tile-window --bundle-id <id> --position <left|right|top|bottom|fullscreen|top-left|top-right|bottom-left|bottom-right> [--display-index N] [--window-index N]
              create-stack --name <name> --position <position> --windows <bundle1,bundle2,...> [--display-index N] [--json]
              switch-stack --name <name> --index <N>
              list-stacks [--json]
              delete-stack --name <name>

              save-desktop --name <name> [--description <text>] [--json]
              save-layout --name <name> [--description <text>] [--json]
              list-desktops [--json]
              list-layouts [--json]
              apply-desktop --name <name>
              restore-layout --name <name>
              delete-desktop --name <name>
              delete-layout --name <name>
              export-desktop --name <name> --output <path>
              import-desktop --file <path> [--json]
              edit-desktop --name <name>
            """
        )
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
