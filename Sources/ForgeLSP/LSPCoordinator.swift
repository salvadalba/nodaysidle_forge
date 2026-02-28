import Foundation
import ForgeShared
import os.log

private let logger = Logger(subsystem: "com.forge.editor", category: "lsp")

/// Maximum retries for crash recovery.
private let maxRetries = 3

/// Response timeout in seconds.
private let responseTimeout: UInt64 = 10_000_000_000 // 10s in nanoseconds

// MARK: - LSPCoordinator

/// Actor-isolated coordinator for a language server process.
///
/// Manages the child process lifecycle, correlates JSON-RPC requests/responses by ID,
/// and implements crash recovery with exponential backoff (1s/2s/4s).
public actor LSPCoordinator {
    // MARK: - Properties

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?

    private var nextRequestID: Int = 1
    private var pendingRequests: [Int: CheckedContinuation<JSONRPCResponse, Error>] = [:]
    private var notificationHandlers: [String: @Sendable (JSONValue) -> Void] = [:]
    private var readTask: Task<Void, Never>?

    private let serverPath: String
    private let serverArguments: [String]
    private var retryCount: Int = 0
    private var isRunning: Bool = false

    /// The current status of the LSP connection.
    public private(set) var status: LSPStatus = .stopped

    // MARK: - Init

    public init(serverPath: String, arguments: [String] = []) {
        self.serverPath = serverPath
        self.serverArguments = arguments
    }

    // MARK: - Lifecycle

    /// Start the language server process.
    public func start() async throws {
        guard !isRunning else { return }

        // Validate server binary path
        try validateServerPath(serverPath)

        status = .starting
        logger.info("Starting LSP server: \(self.serverPath)")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: serverPath)
        proc.arguments = serverArguments

        let stdin = Pipe()
        let stdout = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = FileHandle.nullDevice

        // Set up crash recovery
        proc.terminationHandler = { [weak self] terminatedProcess in
            Task { [weak self] in
                await self?.handleTermination(exitCode: terminatedProcess.terminationStatus)
            }
        }

        try proc.run()

        self.process = proc
        self.inputPipe = stdin
        self.outputPipe = stdout
        self.isRunning = true
        self.retryCount = 0
        self.status = .running

        // Start reading responses
        startReading()

        // Send initialize request
        let initParams = JSONValue.object([
            "processId": .int(Int(ProcessInfo.processInfo.processIdentifier)),
            "capabilities": .object([:]),
            "rootUri": .null,
        ])
        let _ = try await sendRequest(method: "initialize", params: initParams)

        // Send initialized notification
        try sendNotification(method: "initialized", params: nil)

        logger.info("LSP server started and initialized")
    }

    /// Stop the language server process.
    public func stop() {
        isRunning = false
        readTask?.cancel()
        readTask = nil

        // Send shutdown request if possible
        if let pipe = inputPipe {
            let shutdownReq = JSONRPCRequest(id: nextRequestID, method: "shutdown")
            nextRequestID += 1
            if let data = try? LSPFraming.encode(shutdownReq) {
                pipe.fileHandleForWriting.write(data)
            }
        }

        process?.terminate()
        process = nil
        inputPipe = nil
        outputPipe = nil

        // Cancel all pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: LSPError.serverCrashed)
        }
        pendingRequests.removeAll()

        status = .stopped
        logger.info("LSP server stopped")
    }

    // MARK: - Request/Response

    /// Send a JSON-RPC request and await the response (10s timeout).
    public func sendRequest(method: String, params: JSONValue?) async throws -> JSONRPCResponse {
        guard isRunning, let pipe = inputPipe else {
            throw LSPError.serverNotRunning
        }

        let id = nextRequestID
        nextRequestID += 1

        let request = JSONRPCRequest(id: id, method: method, params: params)
        let data = try LSPFraming.encode(request)
        pipe.fileHandleForWriting.write(data)

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation

            // Timeout after 10 seconds
            Task {
                try? await Task.sleep(nanoseconds: responseTimeout)
                if let pending = pendingRequests.removeValue(forKey: id) {
                    pending.resume(throwing: LSPError.timeout(method))
                }
            }
        }
    }

    /// Send a JSON-RPC notification (no response expected).
    public func sendNotification(method: String, params: JSONValue?) throws {
        guard isRunning, let pipe = inputPipe else {
            throw LSPError.serverNotRunning
        }

        let notification = JSONRPCNotification(method: method, params: params)
        let data = try LSPFraming.encode(notification)
        pipe.fileHandleForWriting.write(data)
    }

    /// Register a handler for server-initiated notifications.
    public func onNotification(_ method: String, handler: @Sendable @escaping (JSONValue) -> Void) {
        notificationHandlers[method] = handler
    }

    // MARK: - Reading

    private func startReading() {
        guard let stdout = outputPipe else { return }

        readTask = Task { [weak self] in
            let handle = stdout.fileHandleForReading
            var buffer = Data()

            while !Task.isCancelled {
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    // EOF — process likely terminated
                    break
                }
                buffer.append(chunk)

                // Parse frames from buffer
                while let message = Self.extractMessage(from: &buffer) {
                    await self?.handleMessage(message)
                }
            }
        }
    }

    /// Extract a complete LSP message from the buffer if one is available.
    private static func extractMessage(from buffer: inout Data) -> Data? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }

        let headerData = buffer[buffer.startIndex..<headerEnd.lowerBound]
        guard let headerStr = String(data: headerData, encoding: .utf8),
              let contentLength = LSPFraming.parseContentLength(from: headerStr) else {
            return nil
        }

        let bodyStart = headerEnd.upperBound
        let messageEnd = bodyStart + contentLength

        guard buffer.count >= messageEnd else {
            return nil // Not enough data yet
        }

        let body = buffer[bodyStart..<messageEnd]
        buffer.removeSubrange(buffer.startIndex..<messageEnd)
        return Data(body)
    }

    private func handleMessage(_ data: Data) {
        // Try as response (has id)
        if let response = try? JSONDecoder().decode(JSONRPCResponse.self, from: data),
           let id = response.id,
           let continuation = pendingRequests.removeValue(forKey: id) {
            continuation.resume(returning: response)
            return
        }

        // Try as notification
        if let notification = try? JSONDecoder().decode(JSONRPCNotification.self, from: data) {
            if let handler = notificationHandlers[notification.method] {
                handler(notification.params ?? .null)
            }
            return
        }

        logger.warning("Unhandled LSP message")
    }

    // MARK: - Crash Recovery

    private func handleTermination(exitCode: Int32) async {
        guard isRunning else { return }

        isRunning = false
        logger.error("LSP server terminated with exit code: \(exitCode)")

        // Cancel pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: LSPError.serverCrashed)
        }
        pendingRequests.removeAll()

        // Exponential backoff retry: 1s, 2s, 4s
        guard retryCount < maxRetries else {
            status = .unavailable
            logger.error("LSP server failed after \(maxRetries) retries — giving up")
            return
        }

        retryCount += 1
        let delay = UInt64(pow(2.0, Double(retryCount - 1))) * 1_000_000_000
        status = .restarting(attempt: retryCount)
        logger.info("Restarting LSP server (attempt \(self.retryCount)/\(maxRetries)) in \(self.retryCount)s")

        do {
            try await Task.sleep(nanoseconds: delay)
            try await start()
        } catch {
            logger.error("LSP restart failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Validation

    private func validateServerPath(_ path: String) throws {
        let fm = FileManager.default

        guard fm.fileExists(atPath: path) else {
            throw LSPError.serverBinaryNotFound(path)
        }

        guard fm.isExecutableFile(atPath: path) else {
            throw LSPError.serverBinaryNotExecutable(path)
        }

        // Validate path is within allowed directories
        let allowedPrefixes = ["/usr/local", "/usr/bin", "/opt/homebrew"]
        let homeDir = fm.homeDirectoryForCurrentUser.path
        let localBinDir = homeDir + "/.local"

        let isAllowed = allowedPrefixes.contains(where: { path.hasPrefix($0) })
            || path.hasPrefix(localBinDir)

        guard isAllowed else {
            throw LSPError.serverBinaryUntrusted(path)
        }
    }
}
