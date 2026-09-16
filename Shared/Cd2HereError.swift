import Foundation

public enum Cd2HereError: LocalizedError, Equatable {
    case appleScriptFailed(message: String, number: Int?)
    case automationPermissionDenied(message: String)
    case binaryNotFound(name: String)
    case binaryPermissionDenied(path: String)
    case commandFailed(command: String, exitCode: Int, stderr: String)
    case commandSpawnFailed(command: String, underlying: String)
    case commandTimedOut(command: String, timeout: TimeInterval)
    case invalidFinderResponse
    case invalidDirectory(String)
    case noCompatibleTerminalAvailable

    public var errorDescription: String? {
        switch self {
        case let .appleScriptFailed(message, number):
            if let number {
                return "AppleScript failed (\(number)): \(message)"
            }
            return "AppleScript failed: \(message)"
        case let .automationPermissionDenied(message):
            return "macOS denied Automation permission for the target application (error -1743). Grant access under System Settings → Privacy & Security → Automation, then try again. (\(message))"
        case let .binaryNotFound(name):
            return "Could not find the executable for \(name). It may not be installed or not on PATH."
        case let .binaryPermissionDenied(path):
            return "The executable at \(path) exists but could not be launched (permission denied). Run `chmod +x \(path)` or check the file's owner."
        case let .commandFailed(command, exitCode, stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Command failed (exit \(exitCode)): \(command)"
            }
            return "Command failed (exit \(exitCode)): \(command)\n\(trimmed)"
        case let .commandSpawnFailed(command, underlying):
            return "Could not launch \(command): \(underlying)"
        case let .commandTimedOut(command, timeout):
            return "Command did not exit within \(Int(timeout))s: \(command)"
        case .invalidFinderResponse:
            return "Finder returned an unexpected response."
        case let .invalidDirectory(path):
            return "Finder returned an invalid directory path: \(path)"
        case .noCompatibleTerminalAvailable:
            return "No compatible supported terminal application is available."
        }
    }
}
