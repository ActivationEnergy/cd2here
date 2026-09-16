import Foundation

struct TerminalAppTerminalController: AppleScriptTerminalControlling {
    let executor: any AppleScriptExecuting

    init(executor: any AppleScriptExecuting = AppleScriptExecutor()) {
        self.executor = executor
    }

    static func script(mode: LaunchMode, directory: String) -> String {
        let command = "cd \(ShellLiteral.singleQuoted(directory)) && clear"
        let runCommand = AppleScriptLiteral.string(command)

        let action: String
        switch mode {
        case .window:
            // At the top level of `tell application "Terminal"`, `do script`
            // opens a new window and runs the command.
            action = "do script \(runCommand)"
        case .tab:
            // Inside `tell front window`, `do script` creates a new tab in
            // the front window. Fall back to opening a new window when
            // Terminal.app has no windows yet.
            action = """
            if (count of windows) is greater than 0 then
                tell front window
                    do script \(runCommand)
                end tell
            else
                do script \(runCommand)
            end if
            """
        }

        return """
        tell application "Terminal"
            \(action)
            activate
        end tell
        """
    }
}