import Foundation

struct AlacrittyTerminalController: CLITerminalControlling {
    private static let name = "alacritty"
    var binaryName: String { Self.name }
    let executor: any CommandExecuting
    let binaryLocator: () -> String?

    init() {
        self.init(executor: CommandExecutor(), binaryLocator: { BinaryLocator.locate(Self.name) })
    }

    init(executor: any CommandExecuting, binaryLocator: @escaping () -> String?) {
        self.executor = executor
        self.binaryLocator = binaryLocator
    }

    // Alacritty has no reliable tab-creation CLI/IPC, so tab mode opens a new
    // window as the most useful fallback. Users who care about tab behaviour
    // should pick a terminal with proper tab support.
    func arguments(mode: LaunchMode, directory: String) -> [String] {
        ["--working-directory", directory]
    }
}