import AppKit
import Testing
@testable import Cd2HereCore

@Suite("Terminal automation scripts")
struct TerminalControllerTests {
    @Test("Ghostty window mode always creates a window")
    func ghosttyWindowScript() {
        let script = GhosttyTerminalController.script(mode: .window, directory: "/tmp/project")
        #expect(script.contains("new window with configuration surfaceConfig"))
        #expect(!script.contains("new tab with configuration surfaceConfig"))
    }

    @Test("Ghostty tab mode uses the front window and falls back to a window")
    func ghosttyTabScript() {
        let script = GhosttyTerminalController.script(mode: .tab, directory: "/tmp/project")
        #expect(script.contains("new tab in front window with configuration surfaceConfig"))
        #expect(!script.contains("tell front window"))
        #expect(script.contains("new window with configuration surfaceConfig"))
    }

    @Test("iTerm2 window mode uses the default profile without overriding its command")
    func iTerm2WindowScript() {
        let script = ITerm2TerminalController.script(mode: .window, directory: "/tmp/project")
        #expect(script.contains("create window with default profile"))
        #expect(!script.contains("default profile command"))
        #expect(script.contains("write text"))
        #expect(script.contains("&& clear"))
    }

    @Test("iTerm2 tab mode uses the current window and falls back to a window")
    func iTerm2TabScript() {
        let script = ITerm2TerminalController.script(mode: .tab, directory: "/tmp/project")
        #expect(script.contains("tell current window"))
        #expect(script.contains("create tab with default profile"))
        #expect(script.contains("create window with default profile"))
    }

    @Test("Terminal.app window mode opens a new window via do script")
    func terminalAppWindowScript() {
        let script = TerminalAppTerminalController.script(mode: .window, directory: "/tmp/project")
        #expect(script.contains("tell application \"Terminal\""))
        #expect(script.contains("do script \"cd '/tmp/project' && clear\""))
        #expect(!script.contains("tell front window"))
        #expect(!script.contains("if (count of windows) is greater than 0 then"))
    }

    @Test("Terminal.app tab mode reuses the front window and falls back to a window")
    func terminalAppTabScript() {
        let script = TerminalAppTerminalController.script(mode: .tab, directory: "/tmp/project")
        #expect(script.contains("tell front window"))
        #expect(script.contains("if (count of windows) is greater than 0 then"))
        #expect(script.contains("do script \"cd '/tmp/project' && clear\""))
    }

    @Test("AppleScript and shell literals escape paths")
    func escapedPath() {
        let appleScript = AppleScriptLiteral.string("/tmp/a \\\"quote\\\"\nnext")
        #expect(appleScript == "\"/tmp/a \\\\\\\"quote\\\\\\\"\\nnext\"")
        #expect(ITerm2TerminalController.script(mode: .window, directory: "/tmp/it's here").contains("write text"))
        #expect(TerminalAppTerminalController.script(mode: .window, directory: "/tmp/it's here").contains("do script"))
        #expect(ShellLiteral.singleQuoted("/tmp/it's here") == "'/tmp/it'\\''s here'")
    }

    @Test("POSIX shell single-quote escape covers backslash, double-quote, newline, and consecutive apostrophes")
    func shellEscapeCoverage() {
        // Single-quote wrapping makes backslashes, double quotes, newlines,
        // tabs and dollar signs all literal — no escape needed inside `'…'`.
        // The only character that needs handling is the apostrophe itself.
        #expect(ShellLiteral.singleQuoted("/tmp/back\\slash") == "'/tmp/back\\slash'")
        #expect(ShellLiteral.singleQuoted("/tmp/with\"quote") == "'/tmp/with\"quote'")
        #expect(ShellLiteral.singleQuoted("/tmp/new\nline") == "'/tmp/new\nline'")
        #expect(ShellLiteral.singleQuoted("/tmp/it's a test") == "'/tmp/it'\\''s a test'")
        // Consecutive apostrophes.
        #expect(ShellLiteral.singleQuoted("/a''b") == "'/a'\\'''\\''b'")
        // Empty string round-trips to an empty single-quoted pair.
        #expect(ShellLiteral.singleQuoted("") == "''")
    }

    @Test("Finder AppleScript compiles")
    func finderScriptCompiles() {
        #expect(AppleScriptExecutor.canCompile(
            source: FinderContext.snapshotScript(desktopDirectory: "/Users/test/Desktop")
        ))
    }

    @Test("Installed terminal AppleScripts compile")
    @MainActor
    func installedTerminalScriptsCompile() {
        for terminal in TerminalKind.allCases {
            guard NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: terminal.bundleIdentifier
            ) != nil else { continue }

            let scripts: [String]? = {
                switch terminal {
                case .ghostty:
                    return [
                        GhosttyTerminalController.script(mode: .window, directory: "/tmp/a test"),
                        GhosttyTerminalController.script(mode: .tab, directory: "/tmp/a test"),
                    ]
                case .iTerm2:
                    return [
                        ITerm2TerminalController.script(mode: .window, directory: "/tmp/a test"),
                        ITerm2TerminalController.script(mode: .tab, directory: "/tmp/a test"),
                    ]
                case .terminalApp:
                    return [
                        TerminalAppTerminalController.script(mode: .window, directory: "/tmp/a test"),
                        TerminalAppTerminalController.script(mode: .tab, directory: "/tmp/a test"),
                    ]
                case .wezTerm, .alacritty, .kitty:
                    // CLI-based controllers build argv at call time; nothing to compile.
                    return nil
                }
            }()

            guard let scripts else { continue }

            for script in scripts {
                #expect(AppleScriptExecutor.canCompile(source: script))
            }
        }
    }

    @Test("WezTerm window mode uses `wezterm start --always-new-process --cwd`")
    func wezTermWindowArguments() {
        let controller = WezTermTerminalController()
        let args = controller.arguments(mode: .window, directory: "/tmp/project")
        #expect(args == ["start", "--always-new-process", "--cwd", "/tmp/project"])
    }

    @Test("WezTerm tab mode uses `wezterm start --new-tab --cwd` (no probe needed)")
    func wezTermTabArguments() {
        // `--new-tab` opens a tab in the existing wezterm instance, or
        // falls back to a new window if no instance is running. The
        // fallback semantics are built into the flag itself, so no
        // probe-and-recover logic is needed in `open()`.
        let controller = WezTermTerminalController()
        #expect(controller.arguments(mode: .tab, directory: "/tmp/project")
            == ["start", "--new-tab", "--cwd", "/tmp/project"])
    }

    @Test("Alacritty uses --working-directory for both modes (no tab IPC)")
    func alacrittyArguments() {
        let controller = AlacrittyTerminalController()
        #expect(controller.arguments(mode: .window, directory: "/tmp/project")
            == ["--working-directory", "/tmp/project"])
        #expect(controller.arguments(mode: .tab, directory: "/tmp/project")
            == ["--working-directory", "/tmp/project"])
    }

    @Test("Kitty window mode uses --directory; tab mode falls back to window open")
    func kittyArguments() {
        let controller = KittyTerminalController()
        #expect(controller.arguments(mode: .window, directory: "/tmp/project")
            == ["--directory", "/tmp/project"])
        // Tab mode's default arguments are the same as window mode; the real
        // `kitty @ launch` attempt + fallback happens inside the overridden
        // `open(mode:at:)`. This test documents the argument list passed
        // when the fallback path runs.
        #expect(controller.arguments(mode: .tab, directory: "/tmp/project")
            == ["--directory", "/tmp/project"])
    }

    @Test("Selection is required for first use, Option-click, or a missing app")
    func selectionPolicy() {
        #expect(TerminalSelectionPolicy.requiresSelection(
            savedTerminal: nil,
            isSavedTerminalAvailable: false,
            optionPressed: false
        ))
        #expect(TerminalSelectionPolicy.requiresSelection(
            savedTerminal: .ghostty,
            isSavedTerminalAvailable: true,
            optionPressed: true
        ))
        #expect(TerminalSelectionPolicy.requiresSelection(
            savedTerminal: .ghostty,
            isSavedTerminalAvailable: false,
            optionPressed: false
        ))
        #expect(!TerminalSelectionPolicy.requiresSelection(
            savedTerminal: .ghostty,
            isSavedTerminalAvailable: true,
            optionPressed: false
        ))
    }
}
