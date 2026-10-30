//
//  VideoSubtitleDelegate.swift
//  fichier
//

import AVFoundation

public final class VideoSubtitleDelegate: NSObject, AVPlayerItemLegibleOutputPushDelegate, @unchecked Sendable {
    public var onSubtitleChanged: (@MainActor (String) -> Void)?
    
    public init(onSubtitleChanged: (@MainActor (String) -> Void)? = nil) {
        self.onSubtitleChanged = onSubtitleChanged
        super.init()
    }
    
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
