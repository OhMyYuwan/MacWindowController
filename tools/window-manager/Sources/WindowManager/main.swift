import Foundation

let cli = WindowManagerCLI()

do {
    try cli.run(arguments: CommandLine.arguments)
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}

