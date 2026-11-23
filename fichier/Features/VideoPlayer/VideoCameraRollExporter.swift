//
//  VideoCameraRollExporter.swift
//  fichier
//

import SwiftUI
import Observation
import FichierKit

/// Coordinator managing downloading and saving video files to the system Photos library.
@Observable
@MainActor
public final class VideoCameraRollExporter {
    /// Indicates whether a video export or download operation is currently in flight.
    public var isSaving: Bool = false

    /// Status banner message reporting download progress or export state.
    public var saveStatusMessage: String?

    /// Active background task downloading the video file and writing it to the Photos library.
    private var saveTask: Task<Void, Never>?

    /// Cancellable timer task that clears transient save status banners.
    private var statusResetTask: Task<Void, Never>?

    public init() {}

    /// Cancels any in-flight download or Photos export task and clears status banners.
    public func cancel() {
        saveTask?.cancel()
        saveTask = nil
        statusResetTask?.cancel()
        statusResetTask = nil
        isSaving = false
        saveStatusMessage = nil
    }

    /// Downloads or copies the specified video file into the system Photos library.
    ///
    /// - Parameters:
    ///   - item: Target video media item.
    ///   - manager: Shared storage location manager handling network workers and credentials.
    ///   - onShareableURL: Optional callback receiving the resolved local file URL on successful fetch.
    public func saveToCameraRoll(
        item: MediaItem,
        manager: StorageLocationManager,
        onShareableURL: (@MainActor (URL) -> Void)? = nil
    ) {
        runVideoDownload(item: item, manager: manager, onShareableURL: onShareableURL) { localURL in
            withAnimation {
                self.saveStatusMessage = String(localized: .Strings.videoPlayerSavingToPhotos)
            }
            #if !os(tvOS)
            try await PhotoLibrarySaver.saveVideoToPhotos(at: localURL)
            #endif
            guard !Task.isCancelled else { return }
            withAnimation {
                self.saveStatusMessage = String(localized: .Strings.gallerySavedToPhotosSingle)
            }
        }
    }

    #if !os(tvOS)
    /// Downloads the specified video file to local cache and presents the system Files export picker.
    ///
    /// - Parameters:
    ///   - item: Target video media item.
    ///   - manager: Shared storage location manager handling network workers and credentials.
    ///   - onShareableURL: Optional callback receiving the resolved local file URL on successful fetch.
    public func downloadToFiles(
        item: MediaItem,
        manager: StorageLocationManager,
        onShareableURL: (@MainActor (URL) -> Void)? = nil
    ) {
        runVideoDownload(item: item, manager: manager, onShareableURL: onShareableURL) { [weak self] localURL in
            guard let self else { return }
            withAnimation {
                self.saveStatusMessage = nil
            }
            DocumentPickerExportView.present(urls: [localURL]) { [weak self] success in
                guard let self, success else { return }
                withAnimation {
                    self.saveStatusMessage = String(localized: .Strings.galleryBatchSavedToFiles(1))
                }
                self.statusResetTask?.cancel()
                self.statusResetTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2.5))
                    guard let self, !Task.isCancelled else { return }
                    withAnimation {
                        self.saveStatusMessage = nil
                    }
                }
            }
        }
    }
    #endif

    private func runVideoDownload(
        item: MediaItem,
        manager: StorageLocationManager,
        onShareableURL: (@MainActor (URL) -> Void)?,
        onDownloaded: @escaping @MainActor (URL) async throws -> Void
    ) {
        isSaving = true
        saveTask?.cancel()
        statusResetTask?.cancel()
        statusResetTask = nil
        withAnimation {
            saveStatusMessage = String(localized: .Strings.videoPlayerDownloadingVideo)
        }
        saveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isSaving = false }
            do {
                let throttler = DownloadProgressThrottler()
                let localURL = try await manager.fetchVideoURL(for: item) { [weak self] bytes, total in
                    Task {
                        guard await throttler.shouldReport(bytes: bytes, total: total) else { return }
                        await MainActor.run {
                            guard let self, total > 0 else { return }
                            let readStr = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                            let totalStr = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
                            let percent = (Double(bytes) / Double(total)).formatted(.percent.precision(.fractionLength(0)))
                            self.saveStatusMessage = String(
                                localized: .Strings.galleryDownloadProgressBytes(readStr, totalStr, percent)
                            )
                        }
                    }
                }
                guard !Task.isCancelled else { return }
                onShareableURL?(localURL)
                try await onDownloaded(localURL)
            } catch {
                guard !Task.isCancelled else { return }
                withAnimation {
                    self.saveStatusMessage = String(localized: .Strings.commonErrorFailedToSave(error.localizedDescription))
                }
            }
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation {
                self.saveStatusMessage = nil
            }
        }
    }
}
