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

    public init() {}

    /// Cancels any in-flight download or Photos export task and clears status banners.
    public func cancel() {
        saveTask?.cancel()
        saveTask = nil
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
        isSaving = true
        saveTask?.cancel()
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
