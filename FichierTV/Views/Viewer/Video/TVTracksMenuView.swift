//
//  TVTracksMenuView.swift
//  FichierTV
//

import SwiftUI
import FichierKit

/// Sheet dialog presenting available audio streams, subtitle tracks, and playback speed on tvOS.
public struct TVTracksMenuView: View {
    public let audioTracks: [PlayerAudioTrack]
    public let selectedAudio: PlayerAudioTrack?
    public let subtitleTracks: [PlayerSubtitleTrack]
    public let selectedSubtitle: PlayerSubtitleTrack?
    public let onSelectAudio: (PlayerAudioTrack) -> Void
    public let onSelectSubtitle: (PlayerSubtitleTrack?) -> Void
    @Environment(\.dismiss) private var dismiss

    public init(
        audioTracks: [PlayerAudioTrack],
        selectedAudio: PlayerAudioTrack?,
        subtitleTracks: [PlayerSubtitleTrack],
        selectedSubtitle: PlayerSubtitleTrack?,
        onSelectAudio: @escaping (PlayerAudioTrack) -> Void,
        onSelectSubtitle: @escaping (PlayerSubtitleTrack?) -> Void
    ) {
        self.audioTracks = audioTracks
        self.selectedAudio = selectedAudio
        self.subtitleTracks = subtitleTracks
        self.selectedSubtitle = selectedSubtitle
        self.onSelectAudio = onSelectAudio
        self.onSelectSubtitle = onSelectSubtitle
    }

    public var body: some View {
        NavigationStack {
            List {
                Section(.Strings.tvTracksAudioTitle) {
                    if audioTracks.isEmpty {
                        Text(.Strings.tvTracksDefaultAudio)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(audioTracks) { track in
                            Button {
                                onSelectAudio(track)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(track.title)
                                    Spacer()
                                    if selectedAudio?.id == track.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }

                Section(.Strings.tvTracksSubtitlesTitle) {
                    Button {
                        onSelectSubtitle(nil)
                        dismiss()
                    } label: {
                        HStack {
                            Text(.Strings.videoPlayerSubtitlesOff)
                            Spacer()
                            if selectedSubtitle == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    ForEach(subtitleTracks) { track in
                        Button {
                            onSelectSubtitle(track)
                            dismiss()
                        } label: {
                            HStack {
                                Text(track.title)
                                Spacer()
                                if selectedSubtitle?.id == track.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(.Strings.tvTracksMenuTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.Strings.commonDone) {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
