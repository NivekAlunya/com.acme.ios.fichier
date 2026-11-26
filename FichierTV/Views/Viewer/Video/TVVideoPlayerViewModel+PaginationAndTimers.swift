//
//  TVVideoPlayerViewModel+PaginationAndTimers.swift
//  FichierTV
//

import SwiftUI
import os
import FichierKit

@MainActor
extension TVVideoPlayerViewModel {
    // MARK: - Inactivity Timer & Resume Playback

    public func resetInactivityTimer() {
        autoHideTask?.cancel()
        guard isPlaying, !isScrubbing, !isShowingTracksSheet, !isShowingChaptersSheet, !isShowingSpeedSheet, !isRemoteSeekHolding else { return }

        autoHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            if self.isPlaying && !self.isScrubbing && !self.isShowingTracksSheet && !self.isShowingChaptersSheet && !self.isShowingSpeedSheet && !self.isRemoteSeekHolding {
                withAnimation(.snappy) {
                    self.showOverlay = false
                }
            }
        }
    }

    func restorePlaybackPosition(for itemID: String, on engine: any PlayerEngine) {
        playbackPositionRestoreTask?.cancel()
        playbackPositionRestoreTask = Task { [weak self] in
            guard let self else { return }
            if let savedTime = await self.playbackStore.playbackPosition(for: itemID),
               !Task.isCancelled,
               self.currentItem.id == itemID {
                engine.seek(to: savedTime)
                self.currentTime = engine.currentTime
            }
        }
    }

    func startProgressPersistenceLoop() {
        progressPersistenceTask?.cancel()
        progressPersistenceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { return }
                if self.isPlaying {
                    let itemID = self.currentItem.id
                    let time = self.currentTime
                    let dur = self.duration
                    await self.playbackStore.savePlaybackPosition(itemID: itemID, time: time, duration: dur)
                }
            }
        }
    }

    func saveCurrentProgressSnapshot() {
        let itemID = currentItem.id
        let time = currentTime
        let dur = duration
        Task { [playbackStore] in
            await playbackStore.savePlaybackPosition(itemID: itemID, time: time, duration: dur)
        }
    }

    // MARK: - Multi-Page Source Lookahead & Video Pagination

    func scheduleLookaheadIfNeeded() {
        let bufferedAhead = (videos.count - 1) - currentIndex
        guard hasMoreSourcePages, bufferedAhead <= 5, paginationTask == nil else { return }
        paginationTask = Task { [weak self] in
            guard let self else { return }
            await self.performFetchLookaheadVideos(targetBufferCount: 6)
        }
    }

    func loadMoreAndAdvance() {
        guard paginationTask == nil else { return }
        paginationTask = Task { [weak self] in
            guard let self else { return }
            await self.performFetchLookaheadVideos(targetBufferCount: 1, advanceWhenReady: true)
        }
    }

    private func performFetchLookaheadVideos(targetBufferCount: Int, advanceWhenReady: Bool = false) async {
        defer { paginationTask = nil }
        guard hasMoreSourcePages, let context = paginationContext else { return }

        if paginationSource == nil {
            paginationSource = await resolver.resolve(sourceID: context.sourceID)
        }
        guard !Task.isCancelled, let source = paginationSource else {
            hasMoreSourcePages = false
            return
        }

        while !Task.isCancelled && hasMoreSourcePages {
            let bufferedAhead = (videos.count - 1) - currentIndex
            if !advanceWhenReady && bufferedAhead >= targetBufferCount {
                break
            }

            let page = nextPageToFetch
            do {
                let fetched = try await source.fetchItems(
                    in: context.folder,
                    sortBy: context.sortKey,
                    order: context.sortOrder,
                    page: page,
                    pageSize: context.pageSize
                )
                guard !Task.isCancelled else { break }

                nextPageToFetch = page + 1
                if fetched.count < context.pageSize {
                    hasMoreSourcePages = false
                }

                let newVideos = fetched.filter { $0.type == .video && seenItemIDs.insert($0.id).inserted }

                if !newVideos.isEmpty {
                    videos.append(contentsOf: newVideos)
                    if advanceWhenReady && currentIndex < videos.count - 1 {
                        saveCurrentProgressSnapshot()
                        currentIndex += 1
                        loadCurrentVideo()
                        break
                    }
                }
            } catch {
                Self.logger.error("Failed to paginate video source: \(error.localizedDescription)")
                hasMoreSourcePages = false
                break
            }
        }
    }
}
