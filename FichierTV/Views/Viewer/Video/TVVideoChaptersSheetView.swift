//
//  TVVideoChaptersSheetView.swift
//  FichierTV
//
//

import FichierKit
import SwiftUI

/// Sheet dialog presenting instant timeline quick-jump presets (`0% / 25% / 50% / 75% / ±10m`) and embedded video chapters.
public struct TVVideoChaptersSheetView: View {
    public let chapters: [PlayerChapter]
    public let currentTime: Double
    public let duration: Double
    public let onSelectTime: (Double) -> Void
    @Environment(\.dismiss) private var dismiss

    public init(
        chapters: [PlayerChapter],
        currentTime: Double,
        duration: Double,
        onSelectTime: @escaping (Double) -> Void
    ) {
        self.chapters = chapters
        self.currentTime = currentTime
        self.duration = duration
        self.onSelectTime = onSelectTime
    }

    private var quickJumpOptions: [TVVideoQuickJumpOption] {
        TVVideoQuickJumpOption.buildOptions(duration: duration, currentTime: currentTime)
    }

    public var body: some View {
        NavigationStack {
            List {
                if !quickJumpOptions.isEmpty {
                    Section("Quick Jump") {
                        ForEach(quickJumpOptions) { option in
                            Button {
                                onSelectTime(option.targetTime)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(option.label)
                                    Spacer()
                                    Text(TVRemoteSeekCalculator.formattedTimestamp(option.targetTime))
                                        .font(.callout.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !chapters.isEmpty {
                    Section("Chapters") {
                        ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                            let nextStart = index + 1 < chapters.count ? chapters[index + 1].startTime : duration
                            let isCurrent = currentTime >= chapter.startTime && (nextStart <= chapter.startTime || currentTime < nextStart)

                            Button {
                                onSelectTime(chapter.startTime)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(chapter.title)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(TVRemoteSeekCalculator.formattedTimestamp(chapter.startTime))
                                        .font(.callout.monospacedDigit())
                                        .foregroundStyle(.secondary)

                                    if isCurrent {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(chapters.isEmpty ? "Quick Jump" : "Chapters & Jump")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 540, minHeight: 420)
    }
}
