//
//  MockSMBClient.swift
//  fichierTests
//
//  Created for unit testing SMB integrations in fichierTests.
//

#if DEBUG
import Foundation
import FichierKit

/// Deterministic actor-backed `SMBClientProtocol` double supporting configurable shares, directories,
/// injected errors, call tracking, and cancellable gates for concurrency testing.
actor MockSMBClient: SMBClientProtocol {
    private var shares: [String]
    private var sharesError: (any Error)?
    private var directoryContents: [String: [MediaSourceItem]]
    private var directoryErrors: [String: any Error]
    private var pageErrors: [String: any Error] = [:]
    private var fileData: [String: Data]
    private var fileErrors: [String: any Error]

    private(set) var listSharesCalls: Int = 0
    private(set) var listDirectoryCalls: [String] = []
    private(set) var listDirectoryPageCalls: [MockSMBDirectoryPageCall] = []
    private(set) var readFileCalls: [String] = []
    private(set) var disconnectCalls: Int = 0
    private(set) var disconnectObservedCancelled: [Bool] = []
    private(set) var createdDirectories: [(share: String, path: String)] = []
    private(set) var removedItems: [(share: String, path: String)] = []
    private(set) var movedItems: [(share: String, from: String, to: String)] = []

    private var isSharesGateArmed = false
    private var hasSharesGateStarted = false
    private var sharesStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var sharesReleaseWaiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private var cancelledSharesWaitIDs: Set<UUID> = []

    private var armedDirectoryGates: Set<String> = []
    private var startedDirectoryGates: Set<String> = []
    private var directoryStartWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var directoryReleaseWaiters: [String: [UUID: CheckedContinuation<Void, any Error>]] = [:]
    private var cancelledDirectoryWaitIDs: Set<UUID> = []

    private var armedReadGates: Set<String> = []
    private var startedReadGates: Set<String> = []
    private var readStartWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var readReleaseWaiters: [String: [UUID: CheckedContinuation<Void, any Error>]] = [:]
    private var cancelledReadWaitIDs: Set<UUID> = []

    private static func normalizeDictKeys<T>(_ dict: [String: T]) -> [String: T] {
        var result: [String: T] = [:]
        for (k, v) in dict {
            let normalized = k.split(separator: "/").joined(separator: "/")
            result[normalized] = v
        }
        return result
    }

    init(
        shares: [String] = [],
        sharesError: (any Error)? = nil,
        directoryContents: [String: [MediaSourceItem]] = [:],
        directoryErrors: [String: any Error] = [:],
        fileData: [String: Data] = [:],
        fileErrors: [String: any Error] = [:]
    ) {
        self.shares = shares
        self.sharesError = sharesError
        self.directoryContents = Self.normalizeDictKeys(directoryContents)
        self.directoryErrors = Self.normalizeDictKeys(directoryErrors)
        self.fileData = Self.normalizeDictKeys(fileData)
        self.fileErrors = Self.normalizeDictKeys(fileErrors)
    }

    func updateDirectoryContents(_ contents: [MediaSourceItem], forKey key: String) {
        let normalized = key.split(separator: "/").joined(separator: "/")
        directoryContents[normalized] = contents
    }

    func setPageError(_ error: (any Error)?, forKey key: String, cursor: String?) {
        let pageKey = "\(key)|\(cursor ?? "__initial__")"
        if let error {
            pageErrors[pageKey] = error
        } else {
            pageErrors.removeValue(forKey: pageKey)
        }
    }

    func updateShares(_ shares: [String], error: (any Error)? = nil) {
        self.shares = shares
        self.sharesError = error
    }

    func armSharesGate() {
        isSharesGateArmed = true
        hasSharesGateStarted = false
    }

    func waitUntilListSharesStarts() async {
        if hasSharesGateStarted {
            return
        }
        await withCheckedContinuation { continuation in
            sharesStartWaiters.append(continuation)
        }
    }

    func releaseSharesGate() {
        isSharesGateArmed = false
        let waiters = sharesReleaseWaiters
        sharesReleaseWaiters.removeAll()
        for continuation in waiters.values {
            continuation.resume()
        }
    }

    func armDirectoryGate(forKey key: String) {
        armedDirectoryGates.insert(key)
        startedDirectoryGates.remove(key)
    }

    func waitUntilDirectoryFetchStarts(forKey key: String) async {
        if startedDirectoryGates.contains(key) {
            return
        }
        await withCheckedContinuation { continuation in
            directoryStartWaiters[key, default: []].append(continuation)
        }
    }

    func releaseDirectoryGate(forKey key: String) {
        armedDirectoryGates.remove(key)
        let waiters = directoryReleaseWaiters.removeValue(forKey: key) ?? [:]
        for continuation in waiters.values {
            continuation.resume()
        }
    }

    func armReadGate(forKey key: String) {
        armedReadGates.insert(key)
        startedReadGates.remove(key)
    }

    func waitUntilReadStarts(forKey key: String) async {
        if startedReadGates.contains(key) {
            return
        }
        await withCheckedContinuation { continuation in
            readStartWaiters[key, default: []].append(continuation)
        }
    }

    func releaseReadGate(forKey key: String) {
        armedReadGates.remove(key)
        let waiters = readReleaseWaiters.removeValue(forKey: key) ?? [:]
        for continuation in waiters.values {
            continuation.resume()
        }
    }

    private func suspendForDirectoryGate(key: String, waitID: UUID) async throws {
        try Task.checkCancellation()
        if cancelledDirectoryWaitIDs.remove(waitID) != nil {
            throw CancellationError()
        }
        if !armedDirectoryGates.contains(key) {
            return
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            directoryReleaseWaiters[key, default: [:]][waitID] = continuation
        }
    }

    private func suspendForReadGate(key: String, waitID: UUID) async throws {
        try Task.checkCancellation()
        if cancelledReadWaitIDs.remove(waitID) != nil {
            throw CancellationError()
        }
        if !armedReadGates.contains(key) {
            return
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            readReleaseWaiters[key, default: [:]][waitID] = continuation
        }
    }

    private func suspendForSharesGate(waitID: UUID) async throws {
        try Task.checkCancellation()
        if cancelledSharesWaitIDs.remove(waitID) != nil {
            throw CancellationError()
        }
        if !isSharesGateArmed {
            return
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            sharesReleaseWaiters[waitID] = continuation
        }
    }

    private func cancelSharesWaiter(id: UUID) {
        if let continuation = sharesReleaseWaiters.removeValue(forKey: id) {
            continuation.resume(throwing: CancellationError())
        } else {
            cancelledSharesWaitIDs.insert(id)
        }
    }

    private func cancelDirectoryWaiter(forKey key: String, id: UUID) {
        if let continuation = directoryReleaseWaiters[key]?.removeValue(forKey: id) {
            continuation.resume(throwing: CancellationError())
        } else {
            cancelledDirectoryWaitIDs.insert(id)
        }
    }

    private func cancelReadWaiter(forKey key: String, id: UUID) {
        if let continuation = readReleaseWaiters[key]?.removeValue(forKey: id) {
            continuation.resume(throwing: CancellationError())
        } else {
            cancelledReadWaitIDs.insert(id)
        }
    }

    private static func normalizedKey(share: String, path: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? share : "\(share)/\(trimmed)"
    }

    func listShares() async throws -> [String] {
        try Task.checkCancellation()
        listSharesCalls += 1

        if isSharesGateArmed {
            hasSharesGateStarted = true
            let startWaiters = sharesStartWaiters
            sharesStartWaiters.removeAll()
            for waiter in startWaiters {
                waiter.resume()
            }

            let waitID = UUID()
            try await withTaskCancellationHandler {
                try await self.suspendForSharesGate(waitID: waitID)
            } onCancel: {
                Task { await self.cancelSharesWaiter(id: waitID) }
            }
        }

        try Task.checkCancellation()
        if let sharesError {
            throw sharesError
        }
        return shares
    }

    func listDirectory(share: String, path: String) async throws -> [MediaSourceItem] {
        let key = Self.normalizedKey(share: share, path: path)
        listDirectoryCalls.append(key)

        if armedDirectoryGates.contains(key) {
            startedDirectoryGates.insert(key)
            let startWaiters = directoryStartWaiters.removeValue(forKey: key) ?? []
            for waiter in startWaiters {
                waiter.resume()
            }

            let waitID = UUID()
            try await withTaskCancellationHandler {
                try await self.suspendForDirectoryGate(key: key, waitID: waitID)
            } onCancel: {
                Task { await self.cancelDirectoryWaiter(forKey: key, id: waitID) }
            }
        }

        try Task.checkCancellation()
        if let error = directoryErrors[key] {
            throw error
        }
        return directoryContents[key] ?? []
    }

    // swiftlint:disable:next function_parameter_count
    func listDirectoryPage(
        share: String,
        path: String,
        cursor: String?,
        pageSize: Int,
        sortBy sortKey: MediaSortKey,
        order sortOrder: MediaSortOrder
    ) async throws -> SMBDirectoryPage {
        let key = Self.normalizedKey(share: share, path: path)
        let pageKey = "\(key)|\(cursor ?? "__initial__")"
        listDirectoryPageCalls.append(
            MockSMBDirectoryPageCall(
                key: key,
                cursor: cursor,
                pageSize: pageSize,
                sortKey: sortKey,
                sortOrder: sortOrder
            )
        )

        let activeGateKey: String?
        if armedDirectoryGates.contains(key) {
            activeGateKey = key
        } else if armedDirectoryGates.contains(pageKey) {
            activeGateKey = pageKey
        } else {
            activeGateKey = nil
        }

        if let activeGateKey {
            startedDirectoryGates.insert(activeGateKey)
            let startWaiters = directoryStartWaiters.removeValue(forKey: activeGateKey) ?? []
            for waiter in startWaiters {
                waiter.resume()
            }

            let waitID = UUID()
            try await withTaskCancellationHandler {
                try await self.suspendForDirectoryGate(key: activeGateKey, waitID: waitID)
            } onCancel: {
                Task { await self.cancelDirectoryWaiter(forKey: activeGateKey, id: waitID) }
            }
        }

        try Task.checkCancellation()
        if let error = pageErrors[pageKey] ?? directoryErrors[key] {
            throw error
        }

        guard pageSize > 0 else {
            return SMBDirectoryPage(items: [], nextCursor: nil, totalCount: nil)
        }

        let offset: Int
        if let cursor {
            guard let parsedOffset = Int(cursor), parsedOffset >= 0 else {
                return SMBDirectoryPage(items: [], nextCursor: nil, totalCount: nil)
            }
            offset = parsedOffset
        } else {
            offset = 0
        }

        let sorted = MediaSourceItemSortComparator.sortFoldersFirst(
            directoryContents[key] ?? [],
            sortBy: sortKey,
            order: sortOrder
        )
        guard offset < sorted.count else {
            return SMBDirectoryPage(items: [], nextCursor: nil, totalCount: sorted.count)
        }

        let endIndex = min(offset + pageSize, sorted.count)
        let slice = Array(sorted[offset..<endIndex])
        let nextCursor = endIndex < sorted.count ? String(endIndex) : nil
        return SMBDirectoryPage(items: slice, nextCursor: nextCursor, totalCount: sorted.count)
    }

    func disconnect() async {
        disconnectCalls += 1
        let cancelledAtEntry = Task.isCancelled
        await Task.yield()
        let cancelledAfterYield = Task.isCancelled
        disconnectObservedCancelled.append(cancelledAtEntry || cancelledAfterYield)
    }

    func readFileData(share: String, path: String, maxBytes: Int64?) async throws -> Data {
        let key = Self.normalizedKey(share: share, path: path)
        readFileCalls.append(key)

        if armedReadGates.contains(key) {
            startedReadGates.insert(key)
            let startWaiters = readStartWaiters.removeValue(forKey: key) ?? []
            for waiter in startWaiters {
                waiter.resume()
            }

            let waitID = UUID()
            try await withTaskCancellationHandler {
                try await self.suspendForReadGate(key: key, waitID: waitID)
            } onCancel: {
                Task { await self.cancelReadWaiter(forKey: key, id: waitID) }
            }
        }

        try Task.checkCancellation()
        if let error = fileErrors[key] {
            throw error
        }
        guard let data = fileData[key] else {
            throw SMBError.shareNotFound(key)
        }
        if let maxBytes, maxBytes > 0, data.count > Int(maxBytes) {
            return Data(data.prefix(Int(maxBytes)))
        }
        return data
    }

    func readMediaRange(share: String, path: String, offset: Int64, length: Int) async throws -> Data {
        try Task.checkCancellation()
        let key = Self.normalizedKey(share: share, path: path)
        if let error = fileErrors[key] {
            throw error
        }
        guard let data = fileData[key], offset >= 0, offset < Int64(data.count), length > 0 else {
            return Data()
        }
        let start = Int(offset)
        let end = min(data.count, start + length)
        return data.subdata(in: start..<end)
    }

    func fileSize(share: String, path: String) async throws -> Int64 {
        try Task.checkCancellation()
        let key = Self.normalizedKey(share: share, path: path)
        if let error = fileErrors[key] {
            throw error
        }
        return Int64(fileData[key]?.count ?? 0)
    }

    func downloadFile(
        share: String,
        path: String,
        to localURL: URL,
        progress: (@Sendable (Int64, Int64) -> Bool)?
    ) async throws {
        try Task.checkCancellation()
        let key = Self.normalizedKey(share: share, path: path)
        if let error = fileErrors[key] {
            throw error
        }
        guard let data = fileData[key] else {
            throw SMBError.shareNotFound(key)
        }
        let total = Int64(data.count)
        if let progress, !progress(total, total) {
            throw CancellationError()
        }
        try data.write(to: localURL, options: .atomic)
    }

    func createDirectory(share: String, path: String) async throws {
        createdDirectories.append((share: share, path: path))
        let folderItem = MediaSourceItem(
            id: "\(share)::/\(path)",
            name: (path as NSString).lastPathComponent,
            path: "\(share)/\(path)",
            type: .folder,
            size: 0,
            modifiedDate: Date(),
            smbShare: share,
            smbPath: path
        )
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parentPath = (cleanPath as NSString).deletingLastPathComponent
        let parentKey = Self.normalizedKey(share: share, path: parentPath == "." ? "" : parentPath)
        directoryContents[parentKey, default: []].append(folderItem)
        let ownKey = Self.normalizedKey(share: share, path: path)
        directoryContents[ownKey] = []
    }

    func removeItem(share: String, path: String) async throws {
        removedItems.append((share: share, path: path))
        let ownKey = Self.normalizedKey(share: share, path: path)
        directoryContents.removeValue(forKey: ownKey)
        fileData.removeValue(forKey: ownKey)
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parentPath = (cleanPath as NSString).deletingLastPathComponent
        let parentKey = Self.normalizedKey(share: share, path: parentPath == "." ? "" : parentPath)
        let filename = (cleanPath as NSString).lastPathComponent
        directoryContents[parentKey]?.removeAll(where: { $0.name == filename })
    }

    func moveItem(share: String, fromPath: String, toPath: String) async throws {
        movedItems.append((share: share, from: fromPath, to: toPath))
        let fromKey = Self.normalizedKey(share: share, path: fromPath)
        let toKey = Self.normalizedKey(share: share, path: toPath)
        if let data = fileData.removeValue(forKey: fromKey) {
            fileData[toKey] = data
        }
        if let contents = directoryContents.removeValue(forKey: fromKey) {
            directoryContents[toKey] = contents
        }
        let cleanFrom = fromPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fromParent = (cleanFrom as NSString).deletingLastPathComponent
        let fromParentKey = Self.normalizedKey(share: share, path: fromParent == "." ? "" : fromParent)
        let filename = (cleanFrom as NSString).lastPathComponent
        if let itemIndex = directoryContents[fromParentKey]?.firstIndex(where: { $0.name == filename }) {
            let movedItem = directoryContents[fromParentKey]?.remove(at: itemIndex)
            let cleanTo = toPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let toParent = (cleanTo as NSString).deletingLastPathComponent
            let toParentKey = Self.normalizedKey(share: share, path: toParent == "." ? "" : toParent)
            if let movedItem {
                let updated = MediaSourceItem(
                    id: "\(share)::/\(toPath)",
                    name: (cleanTo as NSString).lastPathComponent,
                    path: "\(share)/\(toPath)",
                    type: movedItem.type,
                    size: movedItem.size,
                    modifiedDate: Date(),
                    smbShare: share,
                    smbPath: toPath
                )
                directoryContents[toParentKey, default: []].append(updated)
            }
        }
    }
}
#endif
