import Foundation

struct WezTermTerminalController: CLITerminalControlling {
    private static let name = "wezterm"
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

    /// Both modes use `wezterm start --cwd <dir>`. The mode only changes
    /// one flag:
    ///
    /// - `--always-new-process` (window mode): skip the existing GUI
    ///   instance handoff, always start a new window.
    /// - `--new-tab` (tab mode): if a wezterm instance is already running,
    ///   spawn a new tab in its active window; if not, fall back to
    ///   starting a new instance. The fallback is built into the flag's
    ///   own semantics, so no probe-and-recover logic is needed here.
    ///
    /// `--always-new-process` and `--new-tab` are mutually exclusive: the
    /// former skips the handoff the latter depends on.
    func arguments(mode: LaunchMode, directory: String) -> [String] {
        switch mode {
        case .window:
            return ["start", "--always-new-process", "--cwd", directory]
        case .tab:
            return ["start", "--new-tab", "--cwd", directory]
        }
    }
}