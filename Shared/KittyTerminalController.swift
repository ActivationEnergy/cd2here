import Foundation

struct KittyTerminalController: CLITerminalControlling {
    private static let name = "kitty"
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

    func arguments(mode: LaunchMode, directory: String) -> [String] {
        switch mode {
        case .window:
            return ["--directory", directory]
        case .tab:
            // `kitty @ launch` requires `allow_remote_control` in kitty.conf.
            // We try this first via the override `open` below; here we just
            // provide the fallback arguments.
            return ["--directory", directory]
        }
    }

    // Override the default `open` so tab mode can try `kitty @ launch` first
    // and fall back to a new window when remote control is not enabled.
    // Uses `runAndWait` (synchronous) so non-zero exit is observable and
    // triggers the fallback — fire-and-forget would silently drop the
    // exit code and the fallback would never run.
    func open(mode: LaunchMode, at directory: String) throws {
        guard let binary = binaryLocator() else {
            throw Cd2HereError.binaryNotFound(name: binaryName)
        }
        switch mode {
        case .window:
            try executor.run(executable: binary, arguments: arguments(mode: mode, directory: directory))
        case .tab:
            let probeArguments = ["@", "launch", "--type", "tab", "--cwd", directory]
            do {
                _ = try executor.runAndWait(
                    executable: binary,
                    arguments: probeArguments,
                    timeout: 5
                )
                // Success — new tab opened in the existing kitty window.
            } catch {
                // Remote control unreachable or `kitty @ launch` failed.
                // This is the common case: most kitty installs ship with
                // `allow_remote_control no` in their default config, so
                // tab-mode silently falls back to opening a new window.
                // NSLog so users searching Console.app can correlate the
                // "I clicked the tab button and got a new window" report
                // with their kitty config.
                NSLog(
                    "cd2here: kitty @ launch failed (\(error)); tab mode falling back to new window. To enable true tabs, set `allow_remote_control yes` in kitty.conf and ensure `KITTY_LISTEN_ON` is reachable from cd2here's launch context."
                )
                try executor.run(
                    executable: binary,
                    arguments: arguments(mode: .window, directory: directory)
                )
            }
        }
    }
}