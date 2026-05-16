import Foundation

struct ProcessOutput {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum ProcessRunnerError: LocalizedError {
    case timedOut(command: String)

    var errorDescription: String? {
        switch self {
        case let .timedOut(command):
            return "Command timed out: \(command)"
        }
    }
}

enum ProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        standardInput: String? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ProcessOutput {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                let stdinPipe = standardInput == nil ? nil : Pipe()

                process.executableURL = executableURL
                process.arguments = arguments
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                if let stdinPipe {
                    process.standardInput = stdinPipe
                }

                let didTimeoutLock = NSLock()
                var didTimeout = false
                var timeoutTimer: DispatchSourceTimer?

                if let timeout {
                    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
                    timer.schedule(deadline: .now() + timeout)
                    timer.setEventHandler {
                        didTimeoutLock.lock()
                        didTimeout = true
                        didTimeoutLock.unlock()

                        if process.isRunning {
                            process.terminate()
                        }
                    }
                    timeoutTimer = timer
                    timer.resume()
                }

                do {
                    try process.run()
                } catch {
                    timeoutTimer?.cancel()
                    continuation.resume(throwing: error)
                    return
                }

                if let standardInput, let stdinPipe {
                    stdinPipe.fileHandleForWriting.write(Data(standardInput.utf8))
                    stdinPipe.fileHandleForWriting.closeFile()
                }

                process.waitUntilExit()
                timeoutTimer?.cancel()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = String(decoding: stdoutData, as: UTF8.self)
                let stderr = String(decoding: stderrData, as: UTF8.self)

                didTimeoutLock.lock()
                let commandTimedOut = didTimeout
                didTimeoutLock.unlock()

                if commandTimedOut {
                    continuation.resume(
                        throwing: ProcessRunnerError.timedOut(
                            command: commandSummary(executableURL: executableURL, arguments: arguments)
                        )
                    )
                    return
                }

                continuation.resume(
                    returning: ProcessOutput(
                        stdout: stdout,
                        stderr: stderr,
                        exitCode: process.terminationStatus
                    )
                )
            }
        }
    }

    private static func commandSummary(executableURL: URL, arguments: [String]) -> String {
        ([executableURL.path] + arguments).joined(separator: " ")
    }
}
