import Foundation

protocol AppleScriptExecuting {
    func execute(source: String) throws -> NSAppleEventDescriptor
}

struct AppleScriptExecutor: AppleScriptExecuting {
    private static let lock = NSLock()

    static func canCompile(source: String) -> Bool {
        lock.withLock {
            guard let script = NSAppleScript(source: source) else { return false }
            var errorInfo: NSDictionary?
            // Discarded intentionally: callers only need a yes/no answer here.
            // For detailed diagnostics use `compile(source:)` below.
            return script.compileAndReturnError(&errorInfo)
        }
    }

    /// Compiles `source` and returns the rich error dictionary on failure
    /// (keys: `NSAppleScript.errorMessage`, `NSAppleScript.errorNumber`,
    /// `NSAppleScript.errorRange`, `NSAppleScript.errorApp`). Returns `nil`
    /// when compilation succeeds.
    static func compile(source: String) -> NSDictionary? {
        lock.withLock {
            guard let script = NSAppleScript(source: source) else {
                return ["NSAppleScript.errorMessage": "Failed to construct AppleScript object."]
            }
            var errorInfo: NSDictionary?
            script.compileAndReturnError(&errorInfo)
            return errorInfo
        }
    }

    func execute(source: String) throws -> NSAppleEventDescriptor {
        try Self.lock.withLock {
            guard let script = NSAppleScript(source: source) else {
                throw Cd2HereError.appleScriptFailed(
                    message: "Failed to construct AppleScript object.",
                    number: nil
                )
            }

            var errorInfo: NSDictionary?
            let result = script.executeAndReturnError(&errorInfo)
            try Self.mapAppleScriptError(errorInfo)
            return result
        }
    }

    /// Maps an NSAppleScript `errorInfo` dictionary into a `Cd2HereError`.
    /// Exposed (internal) for unit testing the `-1743` Automation-permission
    /// special case without needing a real `NSAppleScript` to fail on demand.
    ///
    /// -1743 is the canonical "couldn't be launched" error: the target app
    /// is missing, sandboxed, or hasn't been granted Automation permission.
    /// Surface it explicitly so the alert is actionable instead of cryptic.
    static func mapAppleScriptError(_ errorInfo: NSDictionary?) throws {
        guard let errorInfo else { return }
        let message = errorInfo[NSAppleScript.errorMessage] as? String
            ?? "Unknown AppleScript error"
        let number = errorInfo[NSAppleScript.errorNumber] as? Int
        let range = errorInfo[NSAppleScript.errorRange] as? NSValue
        if number == -1743 {
            throw Cd2HereError.automationPermissionDenied(message: message)
        }
        throw Cd2HereError.appleScriptFailed(
            message: range.map { "\(message) (at \($0.rangeValue))" } ?? message,
            number: number
        )
    }
}