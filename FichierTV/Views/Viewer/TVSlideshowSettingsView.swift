//
//  TVSlideshowSettingsView.swift
//  FichierTV
//

import SwiftUI
import FichierKit

/// Sheet dialog on tvOS enabling configuration of slideshow duration and transition animations.
public struct TVSlideshowSettingsView: View {
    public let currentInterval: TimeInterval
    public let currentStyle: SlideshowTransitionStyle
    public let onSelectInterval: (TimeInterval) -> Void
    public let onSelectStyle: (SlideshowTransitionStyle) -> Void

    @Environment(\.dismiss) private var dismiss

    private let availableIntervals: [TimeInterval] = [2.0, 3.0, 4.0, 5.0, 10.0]

    public init(
        currentInterval: TimeInterval,
        currentStyle: SlideshowTransitionStyle,
        onSelectInterval: @escaping (TimeInterval) -> Void,
        onSelectStyle: @escaping (SlideshowTransitionStyle) -> Void
    ) {
        self.currentInterval = currentInterval
        self.currentStyle = currentStyle
        self.onSelectInterval = onSelectInterval
        self.onSelectStyle = onSelectStyle
    }

    public var body: some View {
        NavigationStack {
            List {
                Section(.Strings.tvSlideshowSlideDuration) {
                    ForEach(availableIntervals, id: \.self) { interval in
                        Button {
                            onSelectInterval(interval)
                        } label: {
                            HStack {
                                Text(.Strings.tvSlideshowDurationSeconds(Int(interval)))
                                Spacer()
                                if currentInterval == interval {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Section(.Strings.tvSlideshowTransitionStyle) {
                    ForEach(SlideshowTransitionStyle.allCases) { style in
                        Button {
                            onSelectStyle(style)
                        } label: {
                            HStack {
                                Text(style.rawValue)
                                Spacer()
                                if currentStyle == style {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(.Strings.tvSlideshowSettingsTitle)
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
