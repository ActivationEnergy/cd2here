import Foundation

struct ITerm2TerminalController: AppleScriptTerminalControlling {
    let executor: any AppleScriptExecuting

    init(executor: any AppleScriptExecuting = AppleScriptExecutor()) {
        self.executor = executor
    }

    static func script(mode: LaunchMode, directory: String) -> String {
        let changeDirectory = AppleScriptLiteral.string(
            "cd \(ShellLiteral.singleQuoted(directory)) && clear"
        )
        let createSession: String
        switch mode {
        case .window:
            createSession = """
            set w to (create window with default profile)
            set s to (current session of w)
            """
        case .tab:
            createSession = """
            if (count of windows) is greater than 0 then
                tell current window
                    set t to (create tab with default profile)
                end tell
                set s to (current session of t)
            else
                set w to (create window with default profile)
                set s to (current session of w)
            end if
            """
        }

        return """
        tell application "iTerm"
            \(createSession)
            tell s
                write text \(changeDirectory)
            end tell
            activate
        end tell
        """
    }
}