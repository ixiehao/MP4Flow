import Darwin
import Foundation

/// Owns one child process from launch through pipe EOF. The caller can cancel
/// inspection, conversion, or merging through the same bounded shutdown path.
/// MP4Flow launches FFmpeg/ffprobe directly; this does not terminate arbitrary
/// descendant process trees or unrelated processes in a shell's process group.
final class FFmpegProcessRunner: @unchecked Sendable {
    enum ActivityPolicy: Sendable {
        case anyOutput
        case advancingFFmpegProgress
    }

    struct Configuration: Sendable {
        var inactivityTimeout: TimeInterval = 90
        var terminationGrace: TimeInterval = 3
        var pollingInterval: TimeInterval = 0.25
        var activityPolicy: ActivityPolicy = .anyOutput
        var maximumOutputBytes = 8_000_000
        var maximumErrorBytes = 4_000
    }

    struct Result: Sendable {
        let terminationStatus: Int32?
        let standardOutput: Data
        let standardError: String
        let wasCancelled: Bool
        let timedOut: Bool
        let launchError: String?

        var succeeded: Bool {
            terminationStatus == 0 && !wasCancelled && !timedOut && launchError == nil
        }
    }

    private let executable: URL
    private let arguments: [String]
    private let configuration: Configuration
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var timedOut = false
    private var finished = false
    private var lastActivity = ProcessInfo.processInfo.systemUptime
    private var output = Data()
    private var errors = Data()
    private var activityBuffer = ""
    private var progressValues: [String: Int64] = [:]
    private var watchdog: Task<Void, Never>?
    private var forcedTermination: Task<Void, Never>?

    init(executable: URL, arguments: [String], configuration: Configuration = Configuration()) {
        self.executable = executable
        self.arguments = arguments
        var normalizedConfiguration = configuration
        normalizedConfiguration.maximumOutputBytes = max(0, configuration.maximumOutputBytes)
        normalizedConfiguration.maximumErrorBytes = max(0, configuration.maximumErrorBytes)
        self.configuration = normalizedConfiguration
    }

    func cancel() {
        requestStop(isTimeout: false)
    }

    func run(onStandardOutput: @escaping @Sendable (Data) -> Void = { _ in }) async -> Result {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let child = Process()
                let stdout = Pipe()
                let stderr = Pipe()
                let drains = DispatchGroup()
                child.executableURL = executable
                child.arguments = arguments
                child.standardInput = FileHandle.nullDevice
                child.standardOutput = stdout
                child.standardError = stderr

                // Read both streams independently, including their final bytes.
                // Waiting for exit before draining can fill a pipe; removing a
                // readability handler at exit can discard a final error packet.
                drains.enter()
                DispatchQueue.global(qos: .utility).async { [self] in
                    defer { drains.leave() }
                    Self.drain(stdout.fileHandleForReading) { chunk in
                        appendOutput(chunk)
                        onStandardOutput(chunk)
                    }
                }
                drains.enter()
                DispatchQueue.global(qos: .utility).async { [self] in
                    defer { drains.leave() }
                    Self.drain(stderr.fileHandleForReading) { chunk in
                        appendError(chunk)
                    }
                }
                child.terminationHandler = { [self] child in
                    // Stop the timer immediately, even while EOF is draining.
                    stopWatchdog()
                    drains.notify(queue: .global(qos: .utility)) {
                        self.complete(status: child.terminationStatus, launchError: nil, continuation: continuation)
                    }
                }

                var launchError: String?
                lock.lock()
                if !cancelled {
                    process = child
                    lastActivity = ProcessInfo.processInfo.systemUptime
                    do { try child.run() }
                    catch { launchError = error.localizedDescription }
                }
                let didLaunch = process != nil && launchError == nil
                lock.unlock()
                // Only the child's duplicated descriptors should keep the
                // pipes open. Closing the parent ends also makes launch-failure
                // and pre-launch cancellation drains reach EOF reliably.
                try? stdout.fileHandleForWriting.close()
                try? stderr.fileHandleForWriting.close()

                if didLaunch {
                    startWatchdog()
                } else {
                    drains.notify(queue: .global(qos: .utility)) { [self] in
                        complete(status: nil, launchError: launchError, continuation: continuation)
                    }
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    private static func drain(_ handle: FileHandle, consume: (Data) -> Void) {
        defer { try? handle.close() }
        let descriptor = handle.fileDescriptor
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            // Foundation's read(upToCount:) may fill the entire requested
            // buffer before returning on macOS. FFmpeg's small progress packets
            // then arrive only at EOF, freezing the UI and misleading the
            // inactivity watchdog. A pipe read returns as soon as bytes exist;
            // the buffer is a capacity, never a minimum packet size.
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if count > 0 {
                consume(Data(buffer.prefix(count)))
            } else if count == 0 {
                return
            } else if errno != EINTR {
                return
            }
        }
    }

    private func appendOutput(_ data: Data) {
        lock.lock()
        switch configuration.activityPolicy {
        case .anyOutput:
            lastActivity = ProcessInfo.processInfo.systemUptime
        case .advancingFFmpegProgress:
            let combined = activityBuffer + String(decoding: data, as: UTF8.self)
            let lines = combined.split(separator: "\n", omittingEmptySubsequences: false)
            activityBuffer = combined.hasSuffix("\n") ? "" : String((lines.last ?? "").suffix(1_024))
            for line in (combined.hasSuffix("\n") ? lines : lines.dropLast()) {
                let fields = line.split(separator: "=", maxSplits: 1)
                guard fields.count == 2,
                      ["out_time_us", "out_time_ms", "frame", "total_size"].contains(String(fields[0])),
                      let value = Int64(fields[1]), value > (progressValues[String(fields[0])] ?? 0) else { continue }
                progressValues[String(fields[0])] = value
                lastActivity = ProcessInfo.processInfo.systemUptime
            }
        }
        if output.count < configuration.maximumOutputBytes {
            output.append(data.prefix(configuration.maximumOutputBytes - output.count))
        }
        lock.unlock()
    }

    private func appendError(_ data: Data) {
        lock.lock()
        errors.append(data)
        if errors.count > configuration.maximumErrorBytes {
            errors.removeFirst(errors.count - configuration.maximumErrorBytes)
        }
        lock.unlock()
    }

    private func startWatchdog() {
        let interval = UInt64(max(configuration.pollingInterval, 0.01) * 1_000_000_000)
        let task = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: interval) }
                catch { return }
                guard let self else { return }
                if self.hasExpired(), self.requestStop(isTimeout: true) {
                    return
                }
                if self.hasExited() { return }
            }
        }
        lock.lock()
        if finished || process?.isRunning != true { task.cancel() }
        else { watchdog = task }
        lock.unlock()
    }

    private func hasExpired() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !finished && process?.isRunning == true
            && ProcessInfo.processInfo.systemUptime - lastActivity >= configuration.inactivityTimeout
    }

    private func hasExited() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished || process?.isRunning != true
    }

    @discardableResult
    private func requestStop(isTimeout: Bool) -> Bool {
        lock.lock()
        guard !finished else { lock.unlock(); return false }
        if isTimeout {
            // The child may have exited, or a progress packet may have arrived,
            // between the watchdog's first observation and taking this lock.
            // Do not turn an already successful exit into a timeout failure.
            guard process?.isRunning == true,
                  ProcessInfo.processInfo.systemUptime - lastActivity >= configuration.inactivityTimeout else {
                lock.unlock()
                return false
            }
            timedOut = true
        } else {
            // User cancellation remains meaningful during the EOF-drain and
            // verification gap: the caller must not publish its output then.
            cancelled = true
        }
        guard forcedTermination == nil, let child = process, child.isRunning else {
            lock.unlock()
            return true
        }
        child.terminate()
        let grace = UInt64(max(configuration.terminationGrace, 0) * 1_000_000_000)
        forcedTermination = Task.detached(priority: .utility) { [weak self, child] in
            do { try await Task.sleep(nanoseconds: grace) }
            catch { return }
            guard let self, !self.hasExited(), child.isRunning else { return }
            _ = Darwin.kill(child.processIdentifier, SIGKILL)
        }
        lock.unlock()
        return true
    }

    private func stopWatchdog() {
        lock.lock()
        watchdog?.cancel()
        watchdog = nil
        forcedTermination?.cancel()
        forcedTermination = nil
        lock.unlock()
    }

    private func complete(status: Int32?, launchError: String?, continuation: CheckedContinuation<Result, Never>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        watchdog?.cancel()
        forcedTermination?.cancel()
        watchdog = nil
        forcedTermination = nil
        process = nil
        let result = Result(
            terminationStatus: status,
            standardOutput: output,
            standardError: String(decoding: errors, as: UTF8.self),
            wasCancelled: cancelled,
            timedOut: timedOut,
            launchError: launchError
        )
        lock.unlock()
        continuation.resume(returning: result)
    }
}
