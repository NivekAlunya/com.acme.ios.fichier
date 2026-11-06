//
//  MediaDiskCacheActor.swift
//  fichier
//

import Foundation
import OSLog

/// Actor isolating all on-disk cache mutations, atomic writes, legacy file migrations, and eviction sweeps.
///
/// ### Architecture & Concurrency
/// - **Actor Isolation**: Guarantees mutually exclusive serial execution for filesystem mutations (writes, moves, removals),
///   preventing data corruption and race conditions between background eviction tasks and active file operations.
/// - **Structured Logging**: Replaces silent error swallowing with structured diagnostics via `AppLog.storage`.
public actor MediaDiskCacheActor {
    
    /// Global shared disk cache actor.
    public static let shared = MediaDiskCacheActor()
    
    /// Underlying file manager instance used exclusively within this actor.
    private let fileManager = FileManager()
    
    // MARK: - Atomic Writes & Reads
    
    /// Atomically writes data to the specified destination URL.
    ///
    /// - Parameters:
    ///   - data: The binary payload to persist.
    ///   - url: The target file destination URL.
    /// - Throws: An error if directory creation or file writing fails.
    public func writeData(_ data: Data, to url: URL) throws {
        let parentDir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        try data.write(to: url, options: .atomic)
    }
    
    /// Safely moves a file from a legacy location to a new destination.
    ///
    /// If the destination file already exists, the legacy file is safely removed.
    ///
    /// - Parameters:
    ///   - sourceURL: Source file URL.
    ///   - destinationURL: Destination file URL.
    public func migrateFile(from sourceURL: URL, to destinationURL: URL) {
        guard fileManager.fileExists(atPath: sourceURL.path) else { return }
        
        if fileManager.fileExists(atPath: destinationURL.path) {
            do {
                try fileManager.removeItem(at: sourceURL)
            } catch {
                AppLog.storage.debug("Failed to remove duplicate legacy file at \(sourceURL.lastPathComponent): \(error.localizedDescription)")
            }
        } else {
            do {
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
            } catch {
                AppLog.storage.debug("Failed to migrate file from \(sourceURL.lastPathComponent) to \(destinationURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
    
    /// Removes files at the designated URLs, logging any unexpected failures.
    ///
    /// - Parameter urls: The array of file URLs to delete.
    public func removeFiles(at urls: [URL]) {
        for url in urls {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            do {
                try fileManager.removeItem(at: url)
            } catch {
                AppLog.storage.debug("Failed to remove file at \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Eviction & Sweeps
    
    /// Evicts oldest accessed files (FIFO) within a directory until total size falls below `limitBytes`.
    ///
    /// - Parameters:
    ///   - directory: Target directory to sweep.
    ///   - limitBytes: Maximum allowed aggregate size in bytes.
    ///   - protectedURLs: File URLs that must be shielded from eviction.
    public func evictFilesIfNeeded(in directory: URL, limitBytes: Int64, keeping protectedURLs: Set<URL> = []) {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        var files: [(url: URL, size: Int64, date: Date)] = []
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "part" {
                do {
                    try fileManager.removeItem(at: fileURL)
                } catch {
                    AppLog.storage.debug("Failed to remove part file \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
                continue
            }
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize else { continue }
            let fileSize = Int64(size)
            let date = values.contentModificationDate ?? Date.distantPast
            totalSize += fileSize
            files.append((url: fileURL, size: fileSize, date: date))
        }
        
        guard totalSize > limitBytes else { return }
        
        // Sort oldest first (FIFO eviction)
        files.sort { $0.date < $1.date }
        
        for file in files {
            if totalSize <= limitBytes { break }
            if protectedURLs.contains(file.url) { continue }
            do {
                try fileManager.removeItem(at: file.url)
                totalSize -= file.size
            } catch {
                AppLog.storage.debug("Failed to evict file \(file.url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
    
    /// Removes orphaned partial download files (`.part`) older than the given duration.
    ///
    /// - Parameters:
    ///   - directories: The directories to inspect for stale `.part` files.
    ///   - seconds: Age threshold in seconds.
    public func cleanOrphanedPartFiles(in directories: [URL], olderThan seconds: TimeInterval = 3600) {
        let now = Date()
        for dir in directories {
            guard let enumerator = fileManager.enumerator(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "part" {
                if let modDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                   now.timeIntervalSince(modDate) > seconds {
                    do {
                        try fileManager.removeItem(at: fileURL)
                    } catch {
                        AppLog.storage.debug("Failed to remove stale part file \(fileURL.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    /// Synchronously calculates the aggregate file size across the provided directories.
    ///
    /// - Parameter directories: Target cache directories.
    /// - Returns: Total size in bytes.
    public func calculateTotalSize(in directories: [URL]) -> Int64 {
        var total: Int64 = 0
        for dir in directories {
            if let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        total += Int64(size)
                    }
                }
            }
        }
        return total
    }
    
    /// Clears all files in the designated directories, optionally sparing protected URLs.
    ///
    /// - Parameters:
    ///   - directories: The cache directories to purge and recreate.
    ///   - protectedURLs: URLs that must be preserved.
    public func clearDirectories(_ directories: [URL], protectedURLs: Set<URL> = []) {
        let attributes: [FileAttributeKey: Any] = [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ]
        for dir in directories {
            if protectedURLs.isEmpty {
                do {
                    try fileManager.removeItem(at: dir)
                } catch {
                    AppLog.storage.debug("Failed to remove cache directory \(dir.lastPathComponent): \(error.localizedDescription)")
                }
            } else {
                if let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: nil) {
                    for case let fileURL as URL in enumerator where !protectedURLs.contains(fileURL) {
                        do {
                            try fileManager.removeItem(at: fileURL)
                        } catch {
                            AppLog.storage.debug("Failed to remove file during clear \(fileURL.lastPathComponent): \(error.localizedDescription)")
                        }
                    }
                }
            }
            do {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: attributes)
            } catch {
                AppLog.storage.error("Failed to recreate cache directory \(dir.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
}
