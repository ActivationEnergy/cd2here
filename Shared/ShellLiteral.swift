import Foundation

enum ShellLiteral {
    /// Wraps a POSIX shell argument in single quotes, escaping any embedded
    /// single quotes with the standard `'\''` sequence. Safe for embedding
    /// inside AppleScript strings that will be passed to `do script` or
    /// `write text` style commands.
    static func singleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}