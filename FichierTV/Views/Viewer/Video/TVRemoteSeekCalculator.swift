//
//  TVRemoteSeekCalculator.swift
//  FichierTV
//
//

import Foundation

/// Pure seek calculation and formatting rules for tvOS remote tap, double-tap, and hold seeking.
public enum TVRemoteSeekCalculator {
    public static let shortTapMaxDuration: TimeInterval = 0.30
    public static let doubleTapWindow: TimeInterval = 0.50
    public static let singleTapSkipSeconds: Double = 15.0
    public static let doubleTapTotalSkipSeconds: Double = 60.0
    public static let previewVisibleDurationNanoseconds: UInt64 = 1_600_000_000
    public static let holdTickIntervalNanoseconds: UInt64 = 50_000_000

    /// Returns unsigned seek offset in seconds for a hold duration using the baseline curve.
    public static func progressiveHoldMagnitude(for heldDuration: TimeInterval) -> Double {
        progressiveHoldMagnitude(for: heldDuration, totalDuration: 0)
    }

    /// Returns unsigned seek offset in seconds scaled cleanly to total video duration.
    ///
    /// Short videos (`<= 10m` or unknown duration) preserve fine `15s -> 55s -> 190s -> +90s/s` pacing,
    /// while longer movies smoothly scale upper hold tiers so traversing 1–2 hours takes ~7–9s.
    public static func progressiveHoldMagnitude(for heldDuration: TimeInterval, totalDuration: Double) -> Double {
        guard heldDuration.isFinite && heldDuration > 0 else {
            return singleTapSkipSeconds
        }
        if heldDuration < shortTapMaxDuration {
            return singleTapSkipSeconds
        }

        if totalDuration.isFinite && !totalDuration.isNaN && totalDuration > 600.0 {
            let longScale = min(16.0, max(1.0, totalDuration / 600.0))
            let entryRate = 20.0 * longScale.squareRoot()
            let tier1End = 15.0 + 1.50 * entryRate
            if heldDuration <= 1.80 {
                return 15.0 + (heldDuration - shortTapMaxDuration) * entryRate
            }

            let cruiseRate = 45.0 * longScale
            let tier2End = tier1End + 2.50 * cruiseRate
            if heldDuration <= 4.30 {
                return tier1End + (heldDuration - 1.80) * cruiseRate
            }

            let expressRate = 90.0 * longScale
            return tier2End + (heldDuration - 4.30) * expressRate
        }

        if heldDuration <= 2.30 {
            return 15.0 + (heldDuration - shortTapMaxDuration) * 20.0
        }
        if heldDuration <= 5.30 {
            return 55.0 + (heldDuration - 2.30) * 45.0
        }
        return 190.0 + (heldDuration - 5.30) * 90.0
    }

    /// Computes accelerated HUD scrubber step size scaled to video duration.
    public static func scrubStepMagnitude(consecutiveSteps: Int, totalDuration: Double) -> Double {
        guard totalDuration.isFinite && !totalDuration.isNaN && totalDuration > 600.0 else {
            if consecutiveSteps > 8 { return 60.0 }
            if consecutiveSteps > 4 { return 30.0 }
            return 10.0
        }

        if consecutiveSteps <= 2 {
            return max(15.0, min(60.0, (totalDuration / 180.0).rounded()))
        }
        if consecutiveSteps <= 5 {
            return max(60.0, (totalDuration / 60.0).rounded())
        }
        return max(120.0, (totalDuration / 24.0).rounded())
    }

    /// Computes smooth Siri Remote touchpad swipe delta in seconds scaled by duration and flick velocity.
    public static func swipeScrubDelta(
        translationDeltaX: Double,
        velocityX: Double,
        trackWidth: Double,
        totalDuration: Double
    ) -> Double {
        guard translationDeltaX.isFinite, !translationDeltaX.isNaN,
              totalDuration.isFinite, !totalDuration.isNaN, totalDuration > 0 else {
            return 0
        }

        let safeTrackWidth = max(480.0, (trackWidth.isFinite && trackWidth > 0) ? trackWidth : 1600.0)
        let normalizedFraction = translationDeltaX / (safeTrackWidth * 0.55)
        let speed = velocityX.isFinite ? abs(velocityX) : 0

        let velocityMultiplier: Double
        if speed < 220.0 {
            velocityMultiplier = 0.35
        } else if speed <= 1200.0 {
            velocityMultiplier = 1.0
        } else {
            velocityMultiplier = min(2.4, 1.0 + (speed - 1200.0) / 1400.0)
        }

        let effectiveSpan = min(totalDuration, max(totalDuration * 0.45, 240.0))
        return normalizedFraction * velocityMultiplier * effectiveSpan
    }

    /// Computes clamped destination timestamp for an origin and signed delta.
    public static func clampedTarget(from originTime: Double, signedDelta: Double, duration: Double) -> Double {
        let safeOrigin = (originTime.isFinite && !originTime.isNaN) ? max(0, originTime) : 0
        let rawTarget = max(0, safeOrigin + signedDelta)
        if duration.isFinite && !duration.isNaN && duration > 0 {
            return min(duration, rawTarget)
        }
        return rawTarget
    }

    /// Formats a signed delta label (e.g., `+15s`, `+60s`, `-1m 35s`).
    public static func formattedDelta(_ deltaSeconds: Double) -> String {
        guard deltaSeconds.isFinite && !deltaSeconds.isNaN else {
            return "0s"
        }
        let rounded = Int(deltaSeconds.rounded())
        guard rounded != 0 else {
            return "0s"
        }
        let sign = rounded > 0 ? "+" : "-"
        let magnitude = abs(rounded)
        if magnitude <= 60 {
            return "\(sign)\(magnitude)s"
        }

        let hours = magnitude / 3600
        let minutes = (magnitude % 3600) / 60
        let seconds = magnitude % 60
        if hours > 0 {
            if seconds > 0 {
                return String(format: "%@%dh %02dm %02ds", sign, hours, minutes, seconds)
            }
            if minutes > 0 {
                return String(format: "%@%dh %02dm", sign, hours, minutes)
            }
            return "\(sign)\(hours)h"
        }

        if seconds > 0 {
            return "\(sign)\(minutes)m \(seconds)s"
        }
        return "\(sign)\(minutes)m"
    }

    /// Formats a playback timestamp as `MM:SS` or `HH:MM:SS`.
    public static func formattedTimestamp(_ totalSeconds: Double) -> String {
        guard totalSeconds.isFinite && !totalSeconds.isNaN && totalSeconds > 0 else {
            return "00:00"
        }
        let seconds = Int(totalSeconds)
        let hrs = seconds / 3600
        let mins = (seconds % 3600) / 60
        let secs = seconds % 60

        if hrs > 0 {
            return String(format: "%02d:%02d:%02d", hrs, mins, secs)
        }
        return String(format: "%02d:%02d", mins, secs)
    }
}
