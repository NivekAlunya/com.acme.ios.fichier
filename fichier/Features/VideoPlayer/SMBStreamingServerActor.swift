//
//  SMBStreamingServerActor.swift
//  fichier
//

import Foundation
import Network

/// Lightweight loopback HTTP server bridging SMB byte-range queries into standard HTTP 1.1 streaming.
///
/// Runs strictly on `127.0.0.1` on an OS-assigned ephemeral port using Apple's `Network.framework`.
/// Translates incoming HTTP `Range: bytes=X-Y` requests from `VLCKit` (or any media player) directly into
/// `SMBClientActor.fetchMediaRange(for:offset:length:)`, returning standard `206 Partial Content` payloads.
actor SMBStreamingServerActor {
    private let worker: SMBClientActor
    private let item: MediaItem
    private var listener: NWListener?
    private var activeConnections: [NWConnection] = []
    private var serverPort: UInt16?
    private var startupContinuations: [CheckedContinuation<URL, any Error>] = []
    
    // swiftlint:disable:next no_legacy_dispatch_queue
    private static let serverQueue = DispatchQueue(label: "com.acme.ios.fichier.smbstreaming.server", qos: .userInitiated)
    
    // swiftlint:disable:next no_legacy_dispatch_queue
    private static let connectionQueue = DispatchQueue(label: "com.acme.ios.fichier.smbstreaming.connection", qos: .userInitiated)
    
    /// Default maximum chunk size served in a single partial content response (2 MB).
    private static let maxChunkSize: Int = 2 * 1024 * 1024
    
    /// Designated initializer.
    ///
    /// - Parameters:
    ///   - worker: The active SMB client actor managing SMB socket connections.
    ///   - item: The target media item being streamed.
    init(worker: SMBClientActor, item: MediaItem) {
        self.worker = worker
        self.item = item
    }
    
    deinit {
        listener?.cancel()
        for connection in activeConnections {
            connection.cancel()
        }
    }
    
    /// Starts the loopback HTTP listener and returns the streaming URL.
    ///
    /// - Returns: A local loopback `http://127.0.0.1:<port>/<filename>` URL.
    func start() async throws -> URL {
        if let port = serverPort {
            return makeStreamURL(for: port)
        }
        
        // If another task already initiated listener startup, await readiness with it
        if listener != nil {
            return try await withCheckedThrowingContinuation { continuation in
                self.startupContinuations.append(continuation)
            }
        }
        
        let tcpOptions = NWProtocolTCP.Options()
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        parameters.requiredInterfaceType = .loopback
        
        let newListener = try NWListener(using: parameters, on: .any)
        self.listener = newListener
        
        return try await withCheckedThrowingContinuation { continuation in
            self.startupContinuations.append(continuation)
            
            newListener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                Task {
                    await self.handleListenerStateUpdate(state)
                }
            }
            
            newListener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                Task {
                    await self.handleNewConnection(connection)
                }
            }
            
            newListener.start(queue: Self.serverQueue)
        }
    }
    
    /// Cancels the loopback listener and closes all active client connections.
    func stop() {
        let continuations = startupContinuations
        startupContinuations.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: CancellationError())
        }
        listener?.cancel()
        listener = nil
        serverPort = nil
        for conn in activeConnections {
            conn.cancel()
        }
        activeConnections.removeAll()
    }
    
    // MARK: - Private Connection Management
    
    private func handleListenerStateUpdate(_ state: NWListener.State) {
        let continuations = startupContinuations
        switch state {
        case .ready:
            if let port = listener?.port?.rawValue {
                self.serverPort = port
                self.startupContinuations.removeAll()
                let url = makeStreamURL(for: port)
                for continuation in continuations {
                    continuation.resume(returning: url)
                }
            }
        case .failed(let error):
            self.listener = nil
            self.startupContinuations.removeAll()
            for continuation in continuations {
                continuation.resume(throwing: error)
            }
        case .cancelled:
            self.listener = nil
            self.startupContinuations.removeAll()
            for continuation in continuations {
                continuation.resume(throwing: CancellationError())
            }
        default:
            break
        }
    }
    
    private func makeStreamURL(for port: UInt16) -> URL {
        let safeName = item.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "stream.mkv"
        return URL(string: "http://127.0.0.1:\(port)/\(safeName)") ?? URL(fileURLWithPath: "/")
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        activeConnections.append(connection)
        
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .cancelled, .failed:
                Task {
                    await self.removeConnection(connection)
                }
            default:
                break
            }
        }
        
        connection.start(queue: Self.connectionQueue)
        
        receiveNextChunk(on: connection)
    }
    
    private func removeConnection(_ connection: NWConnection) {
        activeConnections.removeAll { $0 === connection }
    }
    
    private nonisolated func receiveNextChunk(on connection: NWConnection, buffer: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] content, _, isComplete, error in
            guard let self, let connection else { return }
            if let error {
                AppLog.player.error("SMB Streaming connection read error: \(error.localizedDescription)")
                connection.cancel()
                return
            }
            
            var accumulated = buffer
            if let content, !content.isEmpty {
                accumulated.append(content)
            }
            
            let headerEnd = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n
            let fallbackEnd = Data([0x0A, 0x0A]) // \n\n
            let hasCompletedHeaders = accumulated.range(of: headerEnd) != nil || accumulated.range(of: fallbackEnd) != nil
            
            if hasCompletedHeaders {
                Task {
                    await self.processHTTPRequest(accumulated, on: connection)
                }
            } else if isComplete {
                if !accumulated.isEmpty {
                    Task {
                        await self.processHTTPRequest(accumulated, on: connection)
                    }
                } else {
                    connection.cancel()
                }
            } else if accumulated.count > 65536 {
                self.sendHTTPResponse(status: "400 Bad Request", headers: [:], body: nil, on: connection)
            } else {
                self.receiveNextChunk(on: connection, buffer: accumulated)
            }
        }
    }
    
    private func processHTTPRequest(_ data: Data, on connection: NWConnection) async {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendHTTPResponse(status: "400 Bad Request", headers: [:], body: nil, on: connection)
            return
        }
        
        let lines = requestString.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            sendHTTPResponse(status: "400 Bad Request", headers: [:], body: nil, on: connection)
            return
        }
        
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendHTTPResponse(status: "400 Bad Request", headers: [:], body: nil, on: connection)
            return
        }
        
        let method = parts[0].uppercased()
        let totalSize = item.size
        
        // Extract Range header if present
        var rangeHeader: String?
        for line in lines where line.lowercased().hasPrefix("range:") {
            rangeHeader = line
            break
        }
        
        let contentType = SupportedMediaTypes.mimeType(for: (item.name as NSString).pathExtension)
        
        if method == "HEAD" {
            let headers: [String: String] = [
                "Accept-Ranges": "bytes",
                "Content-Length": "\(totalSize)",
                "Content-Type": contentType,
                "Connection": "close"
            ]
            sendHTTPResponse(status: "200 OK", headers: headers, body: nil, on: connection)
            return
        }
        
        if let rangeHeader {
            guard let (start, end) = Self.parseRangeHeader(rangeHeader, totalSize: totalSize) else {
                let headers: [String: String] = [
                    "Content-Range": "bytes */\(totalSize)",
                    "Connection": "close"
                ]
                sendHTTPResponse(status: "416 Range Not Satisfiable", headers: headers, body: nil, on: connection)
                return
            }
            
            let requestedLength = Int(end - start + 1)
            let fetchLength = min(requestedLength, Self.maxChunkSize)
            
            do {
                let payload = try await worker.fetchMediaRange(for: item, offset: start, length: fetchLength)
                let actualEnd = start + Int64(payload.count) - 1
                let headers: [String: String] = [
                    "Content-Type": contentType,
                    "Content-Range": "bytes \(start)-\(actualEnd)/\(totalSize)",
                    "Content-Length": "\(payload.count)",
                    "Accept-Ranges": "bytes",
                    "Connection": "close"
                ]
                sendHTTPResponse(status: "206 Partial Content", headers: headers, body: payload, on: connection)
            } catch {
                AppLog.player.error("Failed to read SMB chunk for range \(start)-\(end): \(error.localizedDescription)")
                sendHTTPResponse(status: "500 Internal Server Error", headers: [:], body: nil, on: connection)
            }
        } else {
            // Full stream or first chunk request without Range
            let fetchLength = min(Int(totalSize), Self.maxChunkSize)
            do {
                let payload = try await worker.fetchMediaRange(for: item, offset: 0, length: fetchLength)
                let actualEnd = Int64(payload.count) - 1
                let headers: [String: String] = [
                    "Content-Type": contentType,
                    "Content-Range": "bytes 0-\(actualEnd)/\(totalSize)",
                    "Content-Length": "\(payload.count)",
                    "Accept-Ranges": "bytes",
                    "Connection": "close"
                ]
                sendHTTPResponse(status: "206 Partial Content", headers: headers, body: payload, on: connection)
            } catch {
                AppLog.player.error("Failed to read initial SMB stream chunk: \(error.localizedDescription)")
                sendHTTPResponse(status: "500 Internal Server Error", headers: [:], body: nil, on: connection)
            }
        }
    }
    
    /// Parses and validates an HTTP byte Range header against the resource size.
    ///
    /// - Parameters:
    ///   - header: The raw Range header string (e.g. "Range: bytes=0-1024", "Range: bytes=1024-", "Range: bytes=-500").
    ///   - totalSize: The total byte size of the target file.
    /// - Returns: A valid `(start, end)` tuple if satisfiable; `nil` if malformed or unsatisfiable (should return 416).
    static func parseRangeHeader(_ header: String, totalSize: Int64) -> (start: Int64, end: Int64)? {
        guard totalSize > 0 else { return nil }
        guard let eqIndex = header.firstIndex(of: "=") else { return nil }
        
        let prefix = header[..<eqIndex].trimmingCharacters(in: .whitespaces).lowercased()
        guard prefix == "range: bytes" || prefix == "bytes" else { return nil }
        
        let spec = header[header.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)
        guard !spec.contains(",") else { return nil }
        
        let bounds = spec.components(separatedBy: "-")
        guard bounds.count == 2 else { return nil }
        
        let startStr = bounds[0].trimmingCharacters(in: .whitespaces)
        let endStr = bounds[1].trimmingCharacters(in: .whitespaces)
        
        if startStr.isEmpty {
            // Suffix range: "-suffixLength" (e.g. "-500")
            guard let suffixLength = Int64(endStr), suffixLength > 0 else { return nil }
            let start = max(0, totalSize - suffixLength)
            let end = totalSize - 1
            return (start, end)
        } else if endStr.isEmpty {
            // Open-ended range: "start-" (e.g. "1024-")
            guard let start = Int64(startStr), start >= 0, start < totalSize else { return nil }
            let end = totalSize - 1
            return (start, end)
        } else {
            // Explicit bounded range: "start-end" (e.g. "0-1024")
            guard let start = Int64(startStr), let endVal = Int64(endStr) else { return nil }
            guard start >= 0, start < totalSize, endVal >= start else { return nil }
            let end = min(endVal, totalSize - 1)
            return (start, end)
        }
    }
    
    private nonisolated func sendHTTPResponse(status: String, headers: [String: String], body: Data?, on connection: NWConnection) {
        var response = "HTTP/1.1 \(status)\r\n"
        for (key, val) in headers {
            response += "\(key): \(val)\r\n"
        }
        response += "\r\n"
        
        var fullData = Data(response.utf8)
        if let body {
            fullData.append(body)
        }
        
        connection.send(content: fullData, completion: .contentProcessed { [weak connection] _ in
            connection?.cancel()
        })
    }
}
