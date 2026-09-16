import Foundation
import Testing
@testable import Cd2HereCore

@Suite("CommandExecutor and BinaryLocator")
struct CommandExecutorTests {

    @Test("Spawning a long-lived child returns immediately (N-1)")
    func spawnReturnsImmediately() throws {
        let executor = CommandExecutor()
        let start = Date()
        // `sleep 5` runs for 5 seconds. Fire-and-forget must return well
        // before the child exits.
        try executor.run(executable: "/bin/sh", arguments: ["-c", "sleep 5"])
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 0.5, "executor blocked \(elapsed)s waiting for child")
    }

    @Test("runAndWait returns exit code on quick success")
    func runAndWaitQuickSuccess() throws {
        let executor = CommandExecutor()
        let code = try executor.runAndWait(
            executable: "/bin/sh",
            arguments: ["-c", "exit 0"],
            timeout: 5
        )
        #expect(code == 0)
    }

    @Test("runAndWait throws commandFailed on non-zero exit")
    func runAndWaitNonZero() {
        let executor = CommandExecutor()
        #expect(throws: Cd2HereError.self) {
            _ = try executor.runAndWait(
                executable: "/bin/sh",
                arguments: ["-c", "exit 7"],
                timeout: 5
            )
        }
        do {
            _ = try executor.runAndWait(executable: "/bin/sh", arguments: ["-c", "exit 7"], timeout: 5)
            Issue.record("Expected throw")
        } catch let error as Cd2HereError {
            if case .commandFailed(_, let exitCode, _) = error {
                #expect(exitCode == 7)
            } else {
                Issue.record("Expected .commandFailed, got \(error)")
            }
        } catch {
            Issue.record("Expected Cd2HereError, got \(error)")
        }
    }

    @Test("runAndWait does not misreport success as timeout when exit happens before deadline")
    func runAndWaitNoTimeoutRace() throws {
        let executor = CommandExecutor()
        // Sleep 0.05s — well under the 5s timeout. The dispatch timer
        // may still flip `timedOut` after waitUntilExit returns; the
        // exit-status check must win.
        let code = try executor.runAndWait(
            executable: "/bin/sh",
            arguments: ["-c", "sleep 0.05; exit 0"],
            timeout: 5
        )
        #expect(code == 0)
    }

    @Test("Spawning a process that writes >64KB to stdout does not deadlock (C-1)")
    func largeStdoutDoesNotDeadlock() throws {
        let executor = CommandExecutor()
        let start = Date()
        // `yes x | head -c 100000` writes 100KB to stdout and exits cleanly.
        // The plain `yes x` runs forever; relying on launchd to reap it
        // would burn CPU until the test runner exits.
        try executor.run(executable: "/bin/sh", arguments: ["-c", "yes x | head -c 100000"])
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 0.5, "executor blocked \(elapsed)s on full stdout pipe")
    }

    @Test("Spawning a child that exits non-zero does NOT throw (fire-and-forget)")
    func noThrowOnImmediateNonZeroExit() throws {
        let executor = CommandExecutor()
        // /bin/sh -c 'exit 7' exits 7 within milliseconds.
        // Must NOT throw — termination is observed asynchronously via NSLog.
        try executor.run(executable: "/bin/sh", arguments: ["-c", "exit 7"])
    }

    @Test("Spawning a missing executable throws binaryNotFound")
    func throwOnMissingExecutable() {
        let executor = CommandExecutor()
        #expect(throws: Cd2HereError.self) {
            try executor.run(
                executable: "/nonexistent/cd2here-test-binary",
                arguments: []
            )
        }
        // Be specific: it must be binaryNotFound, not the generic
        // commandSpawnFailed. (This assertion would have caught the
        // F-4 regression where POSIX ENOENT was matched instead of
        // Cocoa NSFileNoSuchFileError.)
        do {
            try executor.run(executable: "/nonexistent/cd2here-test-binary", arguments: [])
            Issue.record("Expected throw")
        } catch let error as Cd2HereError {
            switch error {
            case .binaryNotFound:
                break  // pass
            default:
                Issue.record("Expected .binaryNotFound, got \(error)")
            }
        } catch {
            Issue.record("Expected Cd2HereError, got \(error)")
        }
    }

    @Test("mapSpawnError classifies NSCocoaErrorDomain NSFileNoSuchFileError as binaryNotFound")
    func mapSpawnErrorNoSuchFile() {
        let nsError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileNoSuchFileError,
            userInfo: [NSFilePathErrorKey: "/missing/thing"]
        )
        #expect(CommandExecutor.mapSpawnError(nsError, executable: "thing")
            == .binaryNotFound(name: "/missing/thing"))
    }

    @Test("mapSpawnError classifies NSCocoaErrorDomain NSFileReadNoPermissionError as binaryPermissionDenied")
    func mapSpawnErrorPermission() {
        let nsError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoPermissionError,
            userInfo: [NSFilePathErrorKey: "/etc/shadow"]
        )
        #expect(CommandExecutor.mapSpawnError(nsError, executable: "shadow")
            == .binaryPermissionDenied(path: "/etc/shadow"))
    }

    @Test("mapSpawnError falls back to commandSpawnFailed for unknown domains")
    func mapSpawnErrorOtherDomain() {
        let nsError = NSError(domain: "CustomDomain", code: 42, userInfo: nil)
        if case .commandSpawnFailed(let command, _) = CommandExecutor.mapSpawnError(nsError, executable: "foo") {
            #expect(command.contains("foo"))
        } else {
            Issue.record("Expected .commandSpawnFailed")
        }
    }

    @Test("locateViaWhich returns nil for missing binaries")
    func whichMissing() {
        #expect(BinaryLocator.locateViaWhich("cd2here-nonexistent-binary-xyz") == nil)
    }

    @Test("locateViaWhich returns a usable path for /bin/sh")
    func whichFound() {
        let path = BinaryLocator.locateViaWhich("sh")
        #expect(path != nil)
        #expect(FileManager.default.isExecutableFile(atPath: path!))
    }

    @Test("locate returns the same result as locateUncached (cache does not corrupt)")
    func locateCacheConsistency() {
        let cached = BinaryLocator.locate("sh")
        let uncached = BinaryLocator.locateUncached("sh")
        #expect(cached == uncached)
    }

    @Test("locate returns the same value on repeated calls (cache is stable)")
    func locateCacheStable() {
        let first = BinaryLocator.locate("sh")
        let second = BinaryLocator.locate("sh")
        let third = BinaryLocator.locate("sh")
        #expect(first == second)
        #expect(second == third)
    }

    @Test("locate returns nil for missing binaries without throwing")
    func locateMissingBinary() {
        // Unknown binary; the cache may have been populated with nil from a
        // prior test, but that itself proves the cache returned the cached
        // result (which is correct: not found).
        let result = BinaryLocator.locate("cd2here-nonexistent-binary-xyz-test")
        #expect(result == nil)
    }
}