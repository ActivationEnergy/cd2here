import Foundation

public enum LaunchMode: Sendable {
    case window
    case tab
}

enum TerminalKind: String, CaseIterable, Sendable {
    case ghostty
    case iTerm2
    case terminalApp
    case wezTerm
    case alacritty
    case kitty

    var displayName: String {
        switch self {
        case .ghostty: "Ghostty"
        case .iTerm2: "iTerm2"
        case .terminalApp: "Terminal"
        case .wezTerm: "WezTerm"
        case .alacritty: "Alacritty"
        case .kitty: "Kitty"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .ghostty: "com.mitchellh.ghostty"
        case .iTerm2: "com.googlecode.iterm2"
        case .terminalApp: "com.apple.Terminal"
        // The CLI-based terminals use bundle identifiers only to detect
        // installation; opening is done via the binaries themselves.
        case .wezTerm: "com.github.wez.wezterm"
        case .alacritty: "org.alacritty"
        case .kitty: "net.kovidgoyal.kitty"
        }
    }

    /// CLI binary name used as a fallback to detect installations that lack
    /// a `.app` bundle (e.g. `brew install wezterm` without `--cask`).
    /// `nil` for AppleScript-only terminals.
    /// `internal` so the UI-layer extension (`TerminalKindUI.swift`) can
    /// reach it; not part of the public Core API surface.
    var cliBinaryName: String? {
        switch self {
        case .ghostty, .iTerm2, .terminalApp:
            return nil
        case .wezTerm: return "wezterm"
        case .alacritty: return "alacritty"
        case .kitty: return "kitty"
        }
    }
}

enum TerminalAvailability: Equatable {
    case available
    case notInstalled
    case incompatible
}

struct TerminalOption: Equatable {
    let terminal: TerminalKind
    let availability: TerminalAvailability
}

protocol TerminalControlling {
    func open(mode: LaunchMode, at directory: String) throws
    func isCompatible() -> Bool
}

/// Subprotocol for terminals driven by a compiled AppleScript. Concrete
/// controllers only need to declare `script(mode:directory:)` and the
/// `executor` seam used by the default `open` implementation.
protocol AppleScriptTerminalControlling: TerminalControlling {
    static func script(mode: LaunchMode, directory: String) -> String
    var executor: any AppleScriptExecuting { get }
}

extension AppleScriptTerminalControlling {
    func open(mode: LaunchMode, at directory: String) throws {
        _ = try executor.execute(source: Self.script(mode: mode, directory: directory))
    }

    func isCompatible() -> Bool {
        // isCompatible() intentionally reads the global AppleScriptExecutor
        // (rather than the per-instance `executor`) because compilation
        // does not need a specific executor — the script syntax check is
        // the same regardless of which executor will eventually run it.
        AppleScriptExecutor.canCompile(source: Self.script(mode: .window, directory: "/"))
            && AppleScriptExecutor.canCompile(source: Self.script(mode: .tab, directory: "/"))
    }
}

/// Subprotocol for terminals driven by a CLI binary. Concrete controllers
/// declare the binary name, an executor (for tests), and the per-mode argv.
/// `open` and `isCompatible` come from the default implementation.
protocol CLITerminalControlling: TerminalControlling {
    var binaryName: String { get }
    var executor: any CommandExecuting { get }
    var binaryLocator: () -> String? { get }
    func arguments(mode: LaunchMode, directory: String) -> [String]
}

extension CLITerminalControlling {
    func open(mode: LaunchMode, at directory: String) throws {
        guard let binary = binaryLocator() else {
            throw Cd2HereError.binaryNotFound(name: binaryName)
        }
        try executor.run(executable: binary, arguments: arguments(mode: mode, directory: directory))
    }

    func isCompatible() -> Bool {
        binaryLocator() != nil
    }
}

enum TerminalControllerFactory {
    static func make(_ terminal: TerminalKind) -> any TerminalControlling {
        switch terminal {
        case .ghostty:
            GhosttyTerminalController()
        case .iTerm2:
            ITerm2TerminalController()
        case .terminalApp:
            TerminalAppTerminalController()
        case .wezTerm:
            WezTermTerminalController()
        case .alacritty:
            AlacrittyTerminalController()
        case .kitty:
            KittyTerminalController()
        }
    }
}
