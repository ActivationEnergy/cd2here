import Foundation
#if canImport(Darwin)
import Darwin
#endif

protocol CommandExecuting {
    /// Spawns an executable as a detached child process. Throws only when
    /// the executable cannot be launched (ENOENT, EACCES, launchd refusal).
    /// Runtime failures (non-zero exit) are logged via NSLog from a
    /// termination handler — the caller has already returned to the user.
    func run(executable: String, arguments: [String]) throws

    /// Spawns an executable and waits up to `timeout` seconds for it to
    /// exit. Drains stderr so it can be surfaced on failure. Throws
    /// `.commandFailed` on non-zero exit or `.commandSpawnFailed` on launch
    /// failure; returns the exit code on success. Use this for fast
    /// synchronous probes (e.g. `kitty @ launch`); for GUI subprocesses
    /// that you want to outlive cd2here, use `run` instead.
    func runAndWait(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> Int32
}

struct CommandExecutor: CommandExecuting {
    /// Active child processes tracked so termination handlers fire reliably.
    /// Each entry owns its `Process` strongly — without this, the local
    /// `process` reference in `run` is gone after return and the Process
    /// can be deallocated before the child terminates, dropping the
    /// termination handler entirely.
    private nonisolated(unsafe) static var activeTrackers: [ProcessTracker] = []
    private static let trackersLock = NSLock()

    func run(executable: String, arguments: [String]) throws {
        let tracker = try Self.spawn(
            executable: executable,
            arguments: arguments
        )
        // Register the tracker and termination handler immediately after
        // spawn returns. The race window between `process.run()` and this
        // append is microseconds — a child that exits within it would
        // escape NSLog diagnostics, but this is exceptionally rare in
        // practice (the child has to fork, exec, and exit). Acceptable.
        Self.trackersLock.withLock { Self.activeTrackers.append(tracker) }
        tracker.process.terminationHandler = { [weak tracker] _ in
            tracker?.flushAndLog()
            Self.trackersLock.withLock {
                Self.activeTrackers.removeAll { $0 === tracker }
            }
        }
    }

    func runAndWait(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> Int32 {
        let tracker = try Self.spawn(
            executable: executable,
            arguments: arguments
        )
        // `tracker` is local — when `runAndWait` returns or throws, it
        // goes out of scope and its strong reference to `tracker.process`
        // is released. `tracker.process.terminationHandler` was never set,
        // and the tracker was never appended to `activeTrackers` (that's
        // `run`'s job). No cleanup needed.

        // Schedule a two-stage timeout: SIGTERM at `timeout`, then SIGKILL
        // one second later if the child is still alive. The two-stage
        // escalation is what makes `waitUntilExit()` actually bounded — a
        // child that ignores SIGTERM (the F-2 case) gets killed for sure.
        let timedOut = ManagedAtomic<Bool>(false)
        let sigkilled = ManagedAtomic<Bool>(false)
        let grace: TimeInterval = 1.0

        let sigtermItem = DispatchWorkItem {
            guard !timedOut.exchange(true) else { return }
            if tracker.process.isRunning {
                tracker.process.terminate()  // SIGTERM
            }
        }
        DispatchQueue.global().asyncAfter(
            deadline: .now() + timeout,
            execute: sigtermItem
        )

        let sigkillItem = DispatchWorkItem {
            if tracker.process.isRunning {
                sigkilled.exchange(true)
                Darwin.kill(tracker.process.processIdentifier, SIGKILL)
            }
        }
        DispatchQueue.global().asyncAfter(
            deadline: .now() + timeout + grace,
            execute: sigkillItem
        )

        tracker.process.waitUntilExit()  // Now actually bounded by timeout + grace.
        sigtermItem.cancel()
        sigkillItem.cancel()

        // Drain stderr with a 500ms deadline. Normal-case pipes are already
        // closed (process exited, EOF returns immediately). Stale-fd cases
        // (F-2: inherited grandchild) block at most 500ms here; the leak
        // budget for the background thread is one per stuck subprocess.
        tracker.drainRemaining(deadline: .now() + 0.5)

        // Determine the actual outcome. Three possibilities, in order of
        // authority:
        //   1. Process exited normally with status 0 → success.
        //   2. Process exited non-zero (with or without a late
        //      `timedOut` signal) → non-zero exit error.
        //   3. Process was killed by our timeout (terminated by signal,
        //      timedOut.load() == true) → timeout error.
        //
        // Why this ordering: a late `timedOut.exchange(true)` from the
        // dispatch queue can race with the natural exit path — if the
        // process exits successfully milliseconds before the timeout
        // deadline, the timer block still runs and flips `timedOut` to
        // true after `waitUntilExit` already returned. Trusting
        // `timedOut.load()` alone in that case would misreport a
        // successful run as a timeout. The exit status is the
        // authoritative ground truth.
        if tracker.process.terminationReason == .exit
            && tracker.process.terminationStatus == 0 {
            return 0
        }
        if timedOut.load() {
            throw Cd2HereError.commandTimedOut(
                command: "\(executable) \(arguments.joined(separator: " "))",
                timeout: timeout
            )
        }
        let status = Int32(tracker.process.terminationStatus)
        throw Cd2HereError.commandFailed(
            command: "\(executable) \(arguments.joined(separator: " "))",
            exitCode: Int(status),
            stderr: tracker.takeStderrString()
        )
    }

    /// Common spawn path used by both `run` and `runAndWait`. Returns a
    /// tracker that owns the Process strongly. Caller is responsible for
    /// either registering it in `activeTrackers` (fire-and-forget) or
    /// driving it to completion synchronously.
    private static func spawn(
        executable: String,
        arguments: [String]
    ) throws -> ProcessTracker {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.qualityOfService = .userInitiated

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Discard stdout asynchronously so a verbose child never blocks on a
        // full pipe buffer (C-1).
        drainPipe(stdoutPipe.fileHandleForReading)
        let command = "\(executable) \(arguments.joined(separator: " "))"
        let tracker = ProcessTracker(
            process: process,
            stderrHandle: stderrPipe.fileHandleForReading,
            command: command
        )

        do {
            try process.run()
        } catch {
            throw Self.mapSpawnError(error, executable: executable)
        }
        return tracker
    }

    /// Classify a `Process.run()` failure into a typed `Cd2HereError`.
    /// `Process.run` on macOS throws `NSError`s from `NSCocoaErrorDomain`
    /// (codes `NSFileNoSuchFileError=4`, `NSFileReadNoPermissionError=257`)
    /// with the offending path in `NSFilePath`. POSIX `ENOENT` does not
    /// appear — matching `NSPOSIXErrorDomain` here was a latent bug that
    /// routed every spawn failure to the generic `commandSpawnFailed`.
    static func mapSpawnError(_ error: Error, executable: String) -> Cd2HereError {
        let nsError = error as NSError
        let path = (nsError.userInfo[NSFilePathErrorKey] as? String) ?? executable

        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileNoSuchFileError,
                 NSFileReadNoSuchFileError:
                return .binaryNotFound(name: path)
            case NSFileReadNoPermissionError:
                return .binaryPermissionDenied(path: path)
            default:
                break
            }
        }
        return .commandSpawnFailed(
            command: executable,
            underlying: nsError.localizedDescription
        )
    }

    private static func drainPipe(_ handle: FileHandle) {
        handle.readabilityHandler = { handle in
            // Read once and check for EOF inline. Calling `availableData`
            // twice would block the handler thread waiting for more data.
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            }
        }
    }
}

/// Holds the `Process` strongly so its termination handler fires reliably,
/// buffers stderr, and lets callers drain the tail synchronously.
private final class ProcessTracker: @unchecked Sendable {
    let process: Process
    private let stderrHandle: FileHandle
    private let command: String
    private var stderrBuffer = Data()
    private let lock = NSLock()

    init(process: Process, stderrHandle: FileHandle, command: String) {
        self.process = process
        self.stderrHandle = stderrHandle
        self.command = command
        stderrHandle.readabilityHandler = { [weak self] handle in
            guard let self else {
                handle.readabilityHandler = nil
                return
            }
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self.lock.withLock { self.stderrBuffer.append(data) }
        }
    }

    /// Cancel the readability callback and synchronously drain any bytes
    /// still in the kernel pipe buffer.
    ///
    /// Without `deadline`, blocks until EOF — safe on a background thread
    /// (e.g. the fire-and-forget termination handler) but **not safe on the
    /// main actor** if a subprocess has inherited the stderr fd and never
    /// closes it (the F-2 deadlock case).
    ///
    /// With `deadline`, races the read against a deadline: returns at most
    /// at the deadline even if the pipe is still open. The read continues
    /// in a background thread until it eventually returns and appends the
    /// result; one leaked thread per stuck subprocess, no main-thread
    /// block. The lock guarantees the late append is observed safely.
    func drainRemaining(deadline: DispatchTime? = nil) {
        stderrHandle.readabilityHandler = nil

        if deadline == nil {
            let remaining = stderrHandle.readDataToEndOfFile()
            lock.withLock { stderrBuffer.append(remaining) }
            return
        }

        // Bounded drain. Capture locals so the closure doesn't need self.
        let bgLock = self.lock
        let handle = self.stderrHandle
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let remaining = handle.readDataToEndOfFile()
            bgLock.withLock { [weak self] in
                // `self` is guaranteed alive because the group keeps the
                // tracker referenced indirectly via the closure capture;
                // if a degenerate timing makes `self` nil mid-drain, we
                // drop the late bytes — acceptable.
                self?.stderrBuffer.append(remaining)
            }
            group.leave()
        }
        _ = group.wait(timeout: deadline!)
    }

    func takeStderrString() -> String {
        let data = lock.withLock { stderrBuffer }
        // Single-byte UTF-8 decoding failures should not erase the whole
        // diagnostic stream — fall back to ISO-Latin1 which always
        // succeeds, then hex-escape anything still malformed. An empty
        // stderr is also valid (no fallback noise).
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let latin1 = String(data: data, encoding: .isoLatin1) {
            return latin1
        }
        return data.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    /// Used by the fire-and-forget termination handler. Logs non-zero
    /// exits with the buffered stderr so failures show up in Console.app.
    /// Drains the stderr pipe synchronously first so the last bytes that
    /// haven't been delivered to the readabilityHandler yet are not lost.
    func flushAndLog() {
        drainRemaining()
        let stderr = takeStderrString()
        guard process.terminationReason == .exit,
              process.terminationStatus != 0 else { return }
        NSLog(
            "cd2here: command exited %d: %@ stderr=%@",
            process.terminationStatus, command, stderr
        )
    }
}

/// Minimal atomic boolean for the timeout race. `NSLock` would be
/// overkill for a single Bool toggled between two threads.
private final class ManagedAtomic<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()
    init(_ initial: T) { self.value = initial }
    func load() -> T { lock.withLock { value } }
    @discardableResult
    func exchange(_ new: T) -> T { lock.withLock {
        let old = value; value = new; return old
    } }
}