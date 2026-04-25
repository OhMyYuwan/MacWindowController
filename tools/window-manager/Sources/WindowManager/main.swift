import Foundation

let cli = WindowManagerCLI()

do {
    let args = CommandLine.arguments
    if args.count <= 1 && isRunningFromXcode() {
        // Xcode Run convenience mode: open desktop workbench directly.
        try cli.run(arguments: [args.first ?? "window-manager", "edit-current", "--name", "xcode_workspace"])
    } else {
        try cli.run(arguments: args)
    }
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}

private func isRunningFromXcode() -> Bool {
    let env = ProcessInfo.processInfo.environment
    if env["XCODE_VERSION_ACTUAL"] != nil { return true }
    if env["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] != nil { return true }
    if env["IDEPackageSupportUseBuiltinSCM"] != nil { return true }
    return false
}
