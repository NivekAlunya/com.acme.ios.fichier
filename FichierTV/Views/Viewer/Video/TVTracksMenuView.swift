//
//  TVTracksMenuView.swift
//  FichierTV
//

import SwiftUI
import FichierKit

/// Sheet dialog presenting available audio streams and subtitle tracks on tvOS.
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
                Section("Audio") {
                    if audioTracks.isEmpty {
                        Text("Default Audio")
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

                Section("Subtitles") {
                    Button {
                        onSelectSubtitle(nil)
                        dismiss()
                    } label: {
                        HStack {
                            Text("Off")
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
            .navigationTitle("Audio & Subtitles")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
