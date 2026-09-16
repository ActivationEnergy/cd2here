import Foundation

struct GhosttyTerminalController: AppleScriptTerminalControlling {
    let executor: any AppleScriptExecuting

    init(executor: any AppleScriptExecuting = AppleScriptExecutor()) {
        self.executor = executor
    }

    static func script(mode: LaunchMode, directory: String) -> String {
        let path = AppleScriptLiteral.string(directory)
        let action: String
        switch mode {
        case .window:
            action = "new window with configuration surfaceConfig"
        case .tab:
            action = """
            if (count of windows) is greater than 0 then
                new tab in front window with configuration surfaceConfig
            else
                new window with configuration surfaceConfig
            end if
            """
        }

        return """
        tell application "Ghostty"
            set surfaceConfig to new surface configuration
            set initial working directory of surfaceConfig to \(path)
            \(action)
            activate
        end tell
        """
    }
}