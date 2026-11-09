//
//  StubHostSMBClient.swift
//  FichierTVTests
//

import Foundation
import FichierKit

final class StubHostSMBClient: SMBClientProtocol, Sendable {
    let mockShares: [String]
    let mockItems: [MediaSourceItem]
    let mockFileData: [String: Data]

    init(
        mockShares: [String] = ["Movies"],
        mockItems: [MediaSourceItem] = [],
        mockFileData: [String: Data] = [:]
    ) {
        self.mockShares = mockShares
        self.mockItems = mockItems
        self.mockFileData = mockFileData
    }

    func listShares() async throws -> [String] {
        mockShares
    }

    func listDirectory(share: String, path: String) async throws -> [MediaSourceItem] {
        mockItems
    }

    func readFileData(share: String, path: String, maxBytes: Int64?) async throws -> Data {
        let key = "\(share)/\(path)"
        guard let data = mockFileData[key] else {
            return Data()
        }
        if let maxBytes, maxBytes > 0, data.count > Int(maxBytes) {
            return data.prefix(Int(maxBytes))
        }
        return data
    }

    func readMediaRange(share: String, path: String, offset: Int64, length: Int) async throws -> Data {
        let key = "\(share)/\(path)"
        guard let data = mockFileData[key], offset >= 0, offset < Int64(data.count), length > 0 else {
            return Data()
        }
        let start = Int(offset)
        let end = min(data.count, start + length)
        return data.subdata(in: start..<end)
    }

    func fileSize(share: String, path: String) async throws -> Int64 {
        let key = "\(share)/\(path)"
        return Int64(mockFileData[key]?.count ?? 0)
    }
}
