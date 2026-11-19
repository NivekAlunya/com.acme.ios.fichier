//
//  TVVideoRemoteSeekCoordinator.swift
//  FichierTV
//

import Foundation
import Observation
import FichierKit

/// Coordinator managing remote seek gestures, progressive hold mechanics, discrete tap skips, and scrubber tracking.
@Observable
@MainActor
public final class TVVideoRemoteSeekCoordinator {
    // MARK: - Observable State

    /// Indicates whether timeline scrubbing is currently active.
    public var isScrubbing: Bool = false

    /// Target timestamp in seconds during scrubbing.
    public var scrubbingTime: Double?

    /// Active remote seek preview banner model.
    public var remoteSeekPreview: TVRemoteSeekPreview?

    /// Active long-press hold state on remote forward/rewind buttons.
    private(set) var activeRemoteSeekHold: TVRemoteSeekHoldState?

    /// Indicates whether a remote seek hold is actively progressing and not cancelled by Menu.
    public var isRemoteSeekHolding: Bool {
        activeRemoteSeekHold?.wasCancelledByMenu == false
    }

    // MARK: - Internal Mechanics State

    private var scrubHoldCounter: Int = 0
    private var lastRemoteSeekTap: TVRemoteSeekTapState?
    private var recentCommittedSeekTarget: Double?
    private var recentCommittedSeekUptime: TimeInterval?
    private var remoteSeekHoldTask: Task<Void, Never>?
    private var remoteSeekPreviewDismissTask: Task<Void, Never>?

    // MARK: - Injected Providers & Callbacks

    public var uptimeProvider: () -> TimeInterval
    public var currentDurationProvider: () -> Double = { 0 }
    public var currentTimeProvider: () -> Double = { 0 }
    public var onCommitSeek: ((Double, TimeInterval) -> Void)?
    public var onRequestThumbnail: ((Double) -> Void)?
    public var onCancelThumbnails: ((Bool) -> Void)?
    public var onResetInactivityTimer: (() -> Void)?

    // MARK: - Initialization

    public init(uptimeProvider: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.uptimeProvider = uptimeProvider
    }

    // MARK: - Scrubbing & Acceleration

    public func adjustScrub(forward: Bool) {
        isScrubbing = true
        scrubHoldCounter += 1

        let duration = currentDurationProvider()
        let currentTime = currentTimeProvider()
        let step = TVRemoteSeekCalculator.scrubStepMagnitude(
            consecutiveSteps: scrubHoldCounter,
            totalDuration: duration
        )
        let baseTime = scrubbingTime ?? currentTime
        let target = forward ? baseTime + step : baseTime - step
        let upperBound = duration > 0 ? duration : max(baseTime + step, target)
        let clamped = max(0, min(upperBound, target))
        scrubbingTime = clamped
        onRequestThumbnail?(clamped)
    }

    public func commitScrub() {
        if let target = scrubbingTime {
            let timestamp = uptimeProvider()
            recordCommittedSeek(target: target, at: timestamp)
            onCommitSeek?(target, timestamp)
        }
        isScrubbing = false
        scrubbingTime = nil
        scrubHoldCounter = 0
        onCancelThumbnails?(true)
    }

    public func cancelScrub() {
        isScrubbing = false
        scrubbingTime = nil
        scrubHoldCounter = 0
        onCancelThumbnails?(true)
    }

    // MARK: - Remote Seek Gestures

    public func beginRemoteSeek(
        isForward: Bool,
        source: TVRemoteSeekSource,
        timestamp: TimeInterval? = nil
    ) {
        let eventTime = timestamp ?? uptimeProvider()
        if let existing = activeRemoteSeekHold,
           !existing.wasCancelledByMenu,
           existing.source == source,
           existing.isForward == isForward {
            return
        }

        if isScrubbing {
            cancelScrub()
        }

        remoteSeekHoldTask?.cancel()
        remoteSeekHoldTask = nil
        remoteSeekPreviewDismissTask?.cancel()
        remoteSeekPreviewDismissTask = nil

        let anchorTime = effectiveSeekBaseTime(at: eventTime)
        activeRemoteSeekHold = TVRemoteSeekHoldState(
            isForward: isForward,
            source: source,
            anchorTime: anchorTime,
            startTimestamp: eventTime,
            wasCancelledByMenu: false
        )
        startRemoteSeekHoldPreviewLoop()
    }

    public func endRemoteSeek(
        isForward: Bool,
        source: TVRemoteSeekSource,
        timestamp: TimeInterval? = nil
    ) {
        let releaseTime = timestamp ?? uptimeProvider()

        guard let hold = activeRemoteSeekHold,
              hold.source == source,
              hold.isForward == isForward else {
            if source == .hardwareMediaCommand {
                triggerRemoteTapSkip(isForward: isForward, timestamp: releaseTime)
            }
            return
        }

        activeRemoteSeekHold = nil
        remoteSeekHoldTask?.cancel()
        remoteSeekHoldTask = nil

        guard !hold.wasCancelledByMenu else {
            remoteSeekPreview = nil
            onResetInactivityTimer?()
            return
        }

        let heldDuration = max(0, releaseTime - hold.startTimestamp)
        if heldDuration < TVRemoteSeekCalculator.shortTapMaxDuration {
            performRemoteTapSkip(
                isForward: isForward,
                baseAnchorTime: hold.anchorTime,
                timestamp: releaseTime
            )
            return
        }

        lastRemoteSeekTap = nil
        let duration = currentDurationProvider()
        let magnitude = TVRemoteSeekCalculator.progressiveHoldMagnitude(
            for: heldDuration,
            totalDuration: duration
        )
        let signedDelta = isForward ? magnitude : -magnitude
        let targetTime = TVRemoteSeekCalculator.clampedTarget(
            from: hold.anchorTime,
            signedDelta: signedDelta,
            duration: duration
        )
        let appliedDelta = targetTime - hold.anchorTime

        onCancelThumbnails?(false)
        commitRemoteSeek(to: targetTime, at: releaseTime)
        presentRemoteSeekPreview(
            TVRemoteSeekPreview(targetTime: targetTime, deltaSeconds: appliedDelta, isHolding: false)
        )
    }

    public func cancelRemoteSeek(isForward: Bool, source: TVRemoteSeekSource) {
        guard let hold = activeRemoteSeekHold,
              hold.source == source,
              hold.isForward == isForward else {
            return
        }
        activeRemoteSeekHold = nil
        remoteSeekHoldTask?.cancel()
        remoteSeekHoldTask = nil
        remoteSeekPreviewDismissTask?.cancel()
        remoteSeekPreviewDismissTask = nil
        remoteSeekPreview = nil
        onCancelThumbnails?(true)
        onResetInactivityTimer?()
    }

    public func cancelActiveRemoteSeekHoldByMenu() {
        if let hold = activeRemoteSeekHold, !hold.wasCancelledByMenu {
            activeRemoteSeekHold = hold.cancellingByMenu()
            remoteSeekHoldTask?.cancel()
            remoteSeekHoldTask = nil
            remoteSeekPreviewDismissTask?.cancel()
            remoteSeekPreviewDismissTask = nil
            remoteSeekPreview = nil
        }
    }

    public func triggerRemoteTapSkip(isForward: Bool, timestamp: TimeInterval? = nil) {
        let eventTime = timestamp ?? uptimeProvider()
        if isScrubbing {
            cancelScrub()
        }
        activeRemoteSeekHold = nil
        remoteSeekHoldTask?.cancel()
        remoteSeekHoldTask = nil

        let baseAnchorTime = effectiveSeekBaseTime(at: eventTime)
        performRemoteTapSkip(
            isForward: isForward,
            baseAnchorTime: baseAnchorTime,
            timestamp: eventTime
        )
    }

    public func refreshActiveRemoteSeekPreview(at timestamp: TimeInterval? = nil) {
        guard let hold = activeRemoteSeekHold, !hold.wasCancelledByMenu else { return }
        let now = timestamp ?? uptimeProvider()
        let elapsed = max(0, now - hold.startTimestamp)
        guard elapsed >= TVRemoteSeekCalculator.shortTapMaxDuration else { return }

        let duration = currentDurationProvider()
        let magnitude = TVRemoteSeekCalculator.progressiveHoldMagnitude(
            for: elapsed,
            totalDuration: duration
        )
        let signedDelta = hold.isForward ? magnitude : -magnitude
        let targetTime = TVRemoteSeekCalculator.clampedTarget(
            from: hold.anchorTime,
            signedDelta: signedDelta,
            duration: duration
        )
        let appliedDelta = targetTime - hold.anchorTime
        remoteSeekPreview = TVRemoteSeekPreview(
            targetTime: targetTime,
            deltaSeconds: appliedDelta,
            isHolding: true
        )
        onRequestThumbnail?(targetTime)
    }

    public func resolveActiveThumbnailTarget() -> Double? {
        if isScrubbing, let scrubbingTime {
            return scrubbingTime
        }
        if let preview = remoteSeekPreview {
            return preview.targetTime
        }
        return nil
    }

    public func reset() {
        remoteSeekHoldTask?.cancel()
        remoteSeekHoldTask = nil
        remoteSeekPreviewDismissTask?.cancel()
        remoteSeekPreviewDismissTask = nil
        activeRemoteSeekHold = nil
        lastRemoteSeekTap = nil
        recentCommittedSeekTarget = nil
        recentCommittedSeekUptime = nil
        remoteSeekPreview = nil
        isScrubbing = false
        scrubbingTime = nil
        scrubHoldCounter = 0
        onCancelThumbnails?(true)
    }

    // MARK: - Private Helpers

    private func performRemoteTapSkip(
        isForward: Bool,
        baseAnchorTime: Double,
        timestamp: TimeInterval
    ) {
        let sign: Double = isForward ? 1.0 : -1.0
        let duration = currentDurationProvider()

        if let previousTap = lastRemoteSeekTap,
            previousTap.isForward == isForward,
            previousTap.tapCountInPair == 1,
            (timestamp - previousTap.releaseTimestamp) <= TVRemoteSeekCalculator.doubleTapWindow {
            let totalTarget = TVRemoteSeekCalculator.clampedTarget(
                from: previousTap.originTime,
                signedDelta: sign * TVRemoteSeekCalculator.doubleTapTotalSkipSeconds,
                duration: duration
            )
            let appliedDelta = totalTarget - previousTap.originTime
            lastRemoteSeekTap = TVRemoteSeekTapState(
                isForward: isForward,
                releaseTimestamp: timestamp,
                originTime: previousTap.originTime,
                committedTargetTime: totalTarget,
                tapCountInPair: 2
            )
            commitRemoteSeek(to: totalTarget, at: timestamp)
            presentRemoteSeekPreview(
                TVRemoteSeekPreview(targetTime: totalTarget, deltaSeconds: appliedDelta, isHolding: false)
            )
            onRequestThumbnail?(totalTarget)
            return
        }

        let targetTime = TVRemoteSeekCalculator.clampedTarget(
            from: baseAnchorTime,
            signedDelta: sign * TVRemoteSeekCalculator.singleTapSkipSeconds,
            duration: duration
        )
        let appliedDelta = targetTime - baseAnchorTime
        lastRemoteSeekTap = TVRemoteSeekTapState(
            isForward: isForward,
            releaseTimestamp: timestamp,
            originTime: baseAnchorTime,
            committedTargetTime: targetTime,
            tapCountInPair: 1
        )
        commitRemoteSeek(to: targetTime, at: timestamp)
        presentRemoteSeekPreview(
            TVRemoteSeekPreview(targetTime: targetTime, deltaSeconds: appliedDelta, isHolding: false)
        )
        onRequestThumbnail?(targetTime)
    }

    private func commitRemoteSeek(to targetTime: Double, at timestamp: TimeInterval) {
        recordCommittedSeek(target: targetTime, at: timestamp)
        onCommitSeek?(targetTime, timestamp)
        onResetInactivityTimer?()
    }

    public func effectiveSeekBaseTime(at timestamp: TimeInterval) -> Double {
        let currentTime = currentTimeProvider()
        if let recentTarget = recentCommittedSeekTarget,
           let recentUptime = recentCommittedSeekUptime,
           (timestamp - recentUptime) <= 1.25,
           abs(currentTime - recentTarget) > 1.5 {
            return recentTarget
        }
        return currentTime
    }

    public func recordCommittedSeek(target: Double, at timestamp: TimeInterval) {
        recentCommittedSeekTarget = target
        recentCommittedSeekUptime = timestamp
    }

    private func startRemoteSeekHoldPreviewLoop() {
        remoteSeekHoldTask?.cancel()
        remoteSeekHoldTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            while !Task.isCancelled {
                guard let self, let hold = self.activeRemoteSeekHold, !hold.wasCancelledByMenu else {
                    return
                }
                let elapsed = self.uptimeProvider() - hold.startTimestamp
                let effectiveElapsed = max(TVRemoteSeekCalculator.shortTapMaxDuration, elapsed)
                let duration = self.currentDurationProvider()
                let magnitude = TVRemoteSeekCalculator.progressiveHoldMagnitude(
                    for: effectiveElapsed,
                    totalDuration: duration
                )
                let signedDelta = hold.isForward ? magnitude : -magnitude
                let targetTime = TVRemoteSeekCalculator.clampedTarget(
                    from: hold.anchorTime,
                    signedDelta: signedDelta,
                    duration: duration
                )
                let appliedDelta = targetTime - hold.anchorTime
                self.remoteSeekPreview = TVRemoteSeekPreview(
                    targetTime: targetTime,
                    deltaSeconds: appliedDelta,
                    isHolding: true
                )
                self.onRequestThumbnail?(targetTime)
                try? await Task.sleep(for: .nanoseconds(Int(TVRemoteSeekCalculator.holdTickIntervalNanoseconds)))
            }
        }
    }

    public func presentRemoteSeekPreview(_ preview: TVRemoteSeekPreview) {
        remoteSeekPreviewDismissTask?.cancel()
        remoteSeekPreview = preview
        remoteSeekPreviewDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .nanoseconds(Int(TVRemoteSeekCalculator.previewVisibleDurationNanoseconds)))
            guard !Task.isCancelled, let self else { return }
            if self.activeRemoteSeekHold == nil {
                self.remoteSeekPreview = nil
                if !self.isScrubbing {
                    self.onCancelThumbnails?(true)
                }
            }
        }
    }
}
