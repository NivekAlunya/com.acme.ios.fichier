//
//  SMBStreamingServerActor.swift
//  fichier
//

import Foundation
import Network

/// Lightweight loopback HTTP server bridging SMB byte-range queries into standard HTTP 1.1 streaming.
///
/// Runs strictly on `127.0.0.1` on an OS-assigned ephemeral port using Apple's `Network.framework`.
/// Translates incoming HTTP `Range: bytes=X-Y` requests from `MobileVLCKit` (or any media player) directly into
/// `SMBClientActor.fetchMediaRange(for:offset:length:)`, returning standard `206 Partial Content` payloads.
actor SMBStreamingServerActor {
    private let worker: SMBClientActor
    private let item: MediaItem
    private var listener: NWListener?
    private var activeConnections: [NWConnection] = []
    private var serverPort: UInt16?
    
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
        
        let tcpOptions = NWProtocolTCP.Options()
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        parameters.requiredInterfaceType = .loopback
        
        let newListener = try NWListener(using: parameters, on: .any)
        self.listener = newListener
        
        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            
            newListener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                Task {
                    switch state {
                    case .ready:
                        if let port = newListener.port?.rawValue {
                            await self.setPort(port)
                            if !didResume {
                                didResume = true
                                continuation.resume(returning: await self.makeStreamURL(for: port))
                            }
                        }
                    case .failed(let error):
                        if !didResume {
                            didResume = true
                            continuation.resume(throwing: error)
                        }
                    case .cancelled:
                        break
                    default:
                        break
                    }
                }
            }
            
            newListener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                Task {
                    await self.handleNewConnection(connection)
                }
            }
            
            // swiftlint:disable:next no_legacy_dispatch_queue
            let queue = DispatchQueue(label: "com.acme.ios.fichier.smbstreaming.\(UUID().uuidString)")
            newListener.start(queue: queue)
        }
    }
    
    /// Cancels the loopback listener and closes all active client connections.
    func stop() {
        listener?.cancel()
        listener = nil
        serverPort = nil
        for conn in activeConnections {
            conn.cancel()
        }
        activeConnections.removeAll()
    }
    
    // MARK: - Private Connection Management
    
    private func setPort(_ port: UInt16) {
        self.serverPort = port
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
        
        // swiftlint:disable:next no_legacy_dispatch_queue
        let queue = DispatchQueue(label: "com.acme.ios.fichier.smbstreamconn.\(UUID().uuidString)")
        connection.start(queue: queue)
        
        receiveNextChunk(on: connection)
    }
    
    private func removeConnection(_ connection: NWConnection) {
        activeConnections.removeAll { $0 === connection }
    }
    
    private func receiveNextChunk(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] content, _, isComplete, error in
            guard let self, let connection else { return }
            if let error {
                AppLog.player.error("SMB Streaming connection read error: \(error.localizedDescription)")
                connection.cancel()
                return
            }
            
            if let content, !content.isEmpty {
                Task {
                    await self.processHTTPRequest(content, on: connection)
                }
            } else if isComplete {
                connection.cancel()
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
        
        if method == "HEAD" {
            let headers: [String: String] = [
                "Accept-Ranges": "bytes",
                "Content-Length": "\(totalSize)",
                "Content-Type": "video/x-matroska",
                "Connection": "close"
            ]
            sendHTTPResponse(status: "200 OK", headers: headers, body: nil, on: connection)
            return
        }
        
        if let rangeHeader, let (start, end) = parseRangeHeader(rangeHeader, totalSize: totalSize) {
            let requestedLength = Int(end - start + 1)
            let fetchLength = min(requestedLength, Self.maxChunkSize)
            
            do {
                let payload = try await worker.fetchMediaRange(for: item, offset: start, length: fetchLength)
                let actualEnd = start + Int64(payload.count) - 1
                let headers: [String: String] = [
                    "Content-Type": "video/x-matroska",
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
                    "Content-Type": "video/x-matroska",
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
    
    private func parseRangeHeader(_ header: String, totalSize: Int64) -> (start: Int64, end: Int64)? {
        // e.g. "Range: bytes=0-1024" or "Range: bytes=1024-"
        guard let eqIndex = header.firstIndex(of: "=") else { return nil }
        let spec = header[header.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)
        let bounds = spec.components(separatedBy: "-")
        guard let first = bounds.first, let start = Int64(first) else { return nil }
        
        let end: Int64
        if bounds.count > 1, let specifiedEnd = Int64(bounds[1]), specifiedEnd >= start {
            end = min(specifiedEnd, totalSize - 1)
        } else {
            end = min(start + Int64(Self.maxChunkSize) - 1, totalSize - 1)
        }
        
        return (start, end)
    }
    
    private func sendHTTPResponse(status: String, headers: [String: String], body: Data?, on connection: NWConnection) {
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
