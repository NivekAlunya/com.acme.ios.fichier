//
//  PictureViewerBottomBarView.swift
//  fichier
//

import SwiftUI

/// Floating translucent action toolbar docked at the bottom of the full-screen photo viewer.
///
/// Features interactive controls:
/// - Previous and Next photo chevrons for fast paging.
/// - Slideshow play/pause button and duration/transition settings menu.
/// - EXIF photo information sheet toggle button.
/// - Favorite state toggle button.
/// - Save to camera roll button (disabled when viewing local Photos library assets).
/// - Native SwiftUI `ShareLink` export.
public struct PictureViewerBottomBarView: View {
    /// Indicates whether the collection contains more than one photo, enabling navigation arrows.
    public let hasMultiplePictures: Bool
    
    /// Two-way binding controlling automated slideshow playback.
    @Binding public var isPlayingSlideshow: Bool
    
    /// Two-way binding for slideshow advance interval in seconds.
    @Binding public var slideshowInterval: Double
    
    /// Two-way binding for transition visual effect style.
    @Binding public var transitionStyle: SlideshowTransitionStyle
    
    /// Indicates whether the current photo is marked as a user favorite.
    public let isFavorite: Bool
    
    /// Indicates whether export to Camera Roll is allowed (false for existing PhotoKit assets).
    public let canSaveToCameraRoll: Bool
    
    /// Indicates whether photo export to Camera Roll is actively processing.
    public let isSaving: Bool
    
    /// The currently decoded full-resolution `UIImage` reference.
    public let currentImage: UIImage?
    
    /// Display name of the active photo.
    public let currentName: String
    
    /// Action handler to page backward to the previous photo.
    public let onPrevious: () -> Void
    
    /// Action handler to page forward to the next photo.
    public let onNext: () -> Void
    
    /// Action handler to present the EXIF metadata inspector.
    public let onShowInfo: () -> Void
    
    /// Action handler to toggle favorite status.
    public let onToggleFavorite: () -> Void
    
    /// Action handler to save the current photo to the device photo library.
    public let onSaveToCameraRoll: () -> Void
    
    /// Memberwise designated initializer.
    public init(
        hasMultiplePictures: Bool,
        isPlayingSlideshow: Binding<Bool>,
        slideshowInterval: Binding<Double>,
        transitionStyle: Binding<SlideshowTransitionStyle>,
        isFavorite: Bool,
        canSaveToCameraRoll: Bool,
        isSaving: Bool,
        currentImage: UIImage?,
        currentName: String,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onShowInfo: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void,
        onSaveToCameraRoll: @escaping () -> Void
    ) {
        self.hasMultiplePictures = hasMultiplePictures
        self._isPlayingSlideshow = isPlayingSlideshow
        self._slideshowInterval = slideshowInterval
        self._transitionStyle = transitionStyle
        self.isFavorite = isFavorite
        self.canSaveToCameraRoll = canSaveToCameraRoll
        self.isSaving = isSaving
        self.currentImage = currentImage
        self.currentName = currentName
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onShowInfo = onShowInfo
        self.onToggleFavorite = onToggleFavorite
        self.onSaveToCameraRoll = onSaveToCameraRoll
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            // Leading: Previous Photo Button
            if hasMultiplePictures {
                Button {
                    onPrevious()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Previous Photo", comment: "Accessibility label for previous photo"))
                
                Divider()
                    .frame(height: 20)
                    .background(Color.white.opacity(0.3))
            }
            
            // Middle: Action Tools
            HStack(spacing: 10) {
                // 1. Slideshow Play/Pause
                Button {
                    withAnimation { isPlayingSlideshow.toggle() }
                } label: {
                    Image(systemName: isPlayingSlideshow ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isPlayingSlideshow ? Color.orange : Color.white)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlayingSlideshow ? String(localized: "Pause Slideshow", comment: "Accessibility label to pause slideshow") : String(localized: "Start Slideshow", comment: "Accessibility label to start slideshow"))
                
                // 2. Slideshow Duration & Transition Style Menu
                Menu {
                    Section(.Strings.slideshowSectionTransitionStyle) {
                        Picker(.Strings.slideshowPickerStyle, selection: $transitionStyle) {
                            ForEach(SlideshowTransitionStyle.allCases) { style in
                                Label(style.localizedTitle, systemImage: style.iconName).tag(style)
                            }
                        }
                    }
                    
                    Section(.Strings.slideshowPickerDuration) {
                        Picker(.Strings.slideshowPickerSlideshowDuration, selection: $slideshowInterval) {
                            Text(.Strings.slideshowDurationTwoSeconds).tag(2.0)
                            Text(.Strings.slideshowDurationThreeSeconds).tag(3.0)
                            Text(.Strings.slideshowDurationFiveSeconds).tag(5.0)
                            Text(.Strings.slideshowDurationTenSeconds).tag(10.0)
                            Text(.Strings.slideshowDurationFifteenSeconds).tag(15.0)
                            Text(.Strings.slideshowDurationThirtySeconds).tag(30.0)
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "timer")
                            .font(.system(size: 10))
                        Text("\(Int(slideshowInterval))")
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .fixedSize()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Capsule())
                }
                .accessibilityLabel(String(localized: "Slideshow Settings", comment: "Accessibility label for slideshow duration and transition menu"))
                
                // 3. EXIF Info Sheet
                Button {
                    onShowInfo()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Photo Information", comment: "Accessibility label for photo EXIF info"))
                
                // 4. Favorite Button
                Button {
                    onToggleFavorite()
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isFavorite ? Color.red : Color.white)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFavorite ? String(localized: "Remove from Favorites", comment: "Accessibility label to unfavorite photo") : String(localized: "Add to Favorites", comment: "Accessibility label to favorite photo"))
                
                if canSaveToCameraRoll {
                    // 5. Save to Camera Roll
                    Button {
                        onSaveToCameraRoll()
                    } label: {
                        if isSaving {
                            ProgressView().scaleEffect(0.65)
                                .frame(width: 28, height: 28)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(currentImage == nil || isSaving)
                    .accessibilityLabel(String(localized: "Save to Photos", comment: "Accessibility label to save photo to Photos"))
                }
                
                // 6. ShareLink (Directly disabled when image is not yet loaded)
                ShareLink(
                    item: Image(uiImage: currentImage ?? UIImage()),
                    preview: SharePreview(currentName, image: Image(uiImage: currentImage ?? UIImage()))
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(currentImage == nil ? .white.opacity(0.35) : .white)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(currentImage == nil)
                .accessibilityLabel(String(localized: "Share Photo", comment: "Accessibility label to share photo"))
            }
            .padding(.horizontal, 4)
            
            // Trailing: Next Photo Button
            if hasMultiplePictures {
                Divider()
                    .frame(height: 20)
                    .background(Color.white.opacity(0.3))
                
                Button {
                    onNext()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Next Photo", comment: "Accessibility label for next photo"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
        )
    }
}
