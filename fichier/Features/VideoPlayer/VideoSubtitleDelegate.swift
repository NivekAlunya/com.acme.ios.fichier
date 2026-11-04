//
//  VideoSubtitleDelegate.swift
//  fichier
//

import AVFoundation

/// Delegate implementing `AVPlayerItemLegibleOutputPushDelegate` to extract real-time subtitle strings.
///
/// Attaches to an `AVPlayerItemLegibleOutput` instance, extracting attributed string contents and
/// notifying parent views on the `@MainActor` as subtitles change during playback.
public final class VideoSubtitleDelegate: NSObject, AVPlayerItemLegibleOutputPushDelegate, Sendable {
    /// Callback delivering the latest subtitle text string.
    public let onSubtitleChanged: (@MainActor @Sendable (String) -> Void)?
    
    /// Designated public initializer.
    ///
    /// - Parameter onSubtitleChanged: Subtitle update callback.
    public init(onSubtitleChanged: (@MainActor @Sendable (String) -> Void)? = nil) {
        self.onSubtitleChanged = onSubtitleChanged
        super.init()
    }
    
    /// Delegate callback receiving new attributed subtitle text segments from the media demuxer.
    public func legibleOutput(
        _ output: AVPlayerItemLegibleOutput,
        didOutputAttributedStrings strings: [NSAttributedString],
        nativeSampleBuffers nativeSamples: [Any],
        forItemTime itemTime: CMTime
    ) {
        let text = strings.map(\.string).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            self.onSubtitleChanged?(text)
        }
    }
}
