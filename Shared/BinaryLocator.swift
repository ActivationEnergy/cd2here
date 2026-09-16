import Foundation

enum BinaryLocator {
    /// Resolves the absolute path to a CLI binary. Tries common install
    /// prefixes first (Homebrew Apple Silicon/Intel, MacPorts, user-local
    /// bin), then falls back to `which`-style PATH lookup. Returns `nil`
    /// when the binary is not found. Result is memoised for the lifetime
    /// of the process — cd2here is an LSUIElement one-shot launcher
    /// whose entire run lasts under a second, so a binary's location
    /// cannot change between the first probe and any subsequent call.
    private nonisolated(unsafe) static var cache: [String: String?] = [:]
    private static let cacheLock = NSLock()

    static func locate(_ name: String) -> String? {
        if let cached = cacheLock.withLock({ cache[name] }) {
            return cached
        }
        let result = locateUncached(name)
        cacheLock.withLock {
            cache[name] = result
        }
        return result
    }

    /// The actual probe — no cache. Internal so tests can opt out of the
    /// memoisation and exercise the real lookup path.
    static func locateUncached(_ name: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",     // Homebrew (Apple Silicon)
            "/usr/local/bin/\(name)",         // Homebrew (Intel) / macOS
            "/opt/local/bin/\(name)",         // MacPorts
            "\(NSHomeDirectory())/.local/bin/\(name)",  // user-local bin
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return locateViaWhich(name)
    }

    static func locateViaWhich(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        // Drain stderr asynchronously. It rarely writes more than a one-line
        // error, but the previous code created this pipe and never touched it,
        // which was a latent pipe-buffer deadlock (C-1). Single
        // `availableData` call avoids blocking the handler thread.
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty {
                handle.readabilityHandler = nil
            }
        }
        do {
            try process.run()
        } catch {
            return nil
        }
        // Read stdout to EOF before waitUntilExit: if the child forks a daemon
        // that inherits the stdout fd, the original ordering (wait → read)
        // would block here forever.
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path, !path.isEmpty,
              FileManager.default.isExecutableFile(atPath: path) else {
            return nil
        }
        return path
    }
}