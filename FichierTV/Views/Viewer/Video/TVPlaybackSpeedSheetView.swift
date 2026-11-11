//
//  TVPlaybackSpeedSheetView.swift
//  FichierTV
//

import SwiftUI

/// Sheet dialog presenting selectable video playback speed multipliers on tvOS.
public struct TVPlaybackSpeedSheetView: View {
    public let selectedRate: TVVideoPlaybackRate
    public let onSelectRate: (TVVideoPlaybackRate) -> Void

    @Environment(\.dismiss) private var dismiss

    public init(
        selectedRate: TVVideoPlaybackRate,
        onSelectRate: @escaping (TVVideoPlaybackRate) -> Void
    ) {
        self.selectedRate = selectedRate
        self.onSelectRate = onSelectRate
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Playback Speed") {
                    ForEach(TVVideoPlaybackRate.allCases) { rate in
                        Button {
                            onSelectRate(rate)
                            dismiss()
                        } label: {
                            HStack {
                                Text(rate.displayName)
                                Spacer()
                                if selectedRate == rate {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Playback Speed")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 420)
    }
}
