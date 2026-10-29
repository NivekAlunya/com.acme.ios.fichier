//
//  AppSettingsView.swift
//  fichier
//

import SwiftUI
import UIKit

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
    // Gallery & Slideshow Settings
    @AppStorage("slideshow_timer_interval") private var slideshowInterval: Double = 3.0
    @AppStorage("slideshow_transition_style") private var transitionStyle: SlideshowTransitionStyle = .slide
    @AppStorage("gallery_view_mode") private var viewMode: ViewMode = .grid
    @AppStorage("gallery_sort_option") private var sortOption: SortOption = .nameAsc
    @AppStorage("gallery_grid_size") private var gridSize: GridSize = .medium
    
    // Cache State
    @State private var cacheSizeString: String = MediaCacheManager.shared.formattedCacheSize()
    @State private var isShowingClearConfirmation = false
    @State private var isClearingCache = false
    
    var body: some View {
        NavigationStack {
            Form {
                // 1. iOS System Settings (Local Network, Permissions, Language)
                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        HStack {
                            Label(.Strings.settingsButtonOpenSystemSettings, systemImage: "gear")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text(.Strings.settingsSectionSystem)
                } footer: {
                    Text(.Strings.settingsSystemFooter)
                }
                
                // 2. Storage & Cache Management
                Section {
                    LabeledContent(.Strings.settingsCacheSize, value: cacheSizeString)
                    
                    Button(role: .destructive) {
                        isShowingClearConfirmation = true
                    } label: {
                        HStack {
                            Label(.Strings.settingsButtonClearCache, systemImage: "trash")
                            Spacer()
                            if isClearingCache {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isClearingCache)
                } header: {
                    Text(.Strings.settingsSectionStorage)
                } footer: {
                    Text(.Strings.settingsStorageFooter)
                }
                .confirmationDialog(
                    .Strings.settingsClearCacheDialogTitle,
                    isPresented: $isShowingClearConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(.Strings.settingsClearCacheConfirm, role: .destructive) {
                        clearCache()
                    }
                    Button(.Strings.commonCancel, role: .cancel) {}
                } message: {
                    Text(.Strings.settingsClearCacheDialogMessage)
                }
                
                // 3. Slideshow Preferences
                Section(.Strings.settingsSectionSlideshow) {
                    Picker(.Strings.slideshowSectionTransitionStyle, selection: $transitionStyle) {
                        ForEach(SlideshowTransitionStyle.allCases) { style in
                            Label(style.localizedTitle, systemImage: style.iconName).tag(style)
                        }
                    }
                    
                    Picker(.Strings.slideshowSectionSlideDuration, selection: $slideshowInterval) {
                        Text(.Strings.slideshowDurationTwoSeconds).tag(2.0)
                        Text(.Strings.slideshowDurationThreeSeconds).tag(3.0)
                        Text(.Strings.slideshowDurationFiveSeconds).tag(5.0)
                        Text(.Strings.slideshowDurationTenSeconds).tag(10.0)
                        Text(.Strings.slideshowDurationFifteenSeconds).tag(15.0)
                        Text(.Strings.slideshowDurationThirtySeconds).tag(30.0)
                    }
                }
                
                // 4. Gallery Display Defaults
                Section(.Strings.settingsSectionGalleryDefaults) {
                    Picker(.Strings.settingsDefaultView, selection: $viewMode) {
                        Label(.Strings.galleryViewModeGrid, systemImage: "square.grid.2x2").tag(ViewMode.grid)
                        Label(.Strings.galleryViewModeList, systemImage: "list.bullet").tag(ViewMode.list)
                    }
                    
                    Picker(.Strings.galleryPickerGridSize, selection: $gridSize) {
                        ForEach(GridSize.allCases) { size in
                            Label(size.localizedTitle, systemImage: size.iconName).tag(size)
                        }
                    }
                    
                    Picker(.Strings.galleryMenuSortBy, selection: $sortOption) {
                        ForEach(SortOption.allCases) { option in
                            Label(option.localizedTitle, systemImage: option.iconName).tag(option)
                        }
                    }
                }
                
                // 5. About & Version Information
                Section(.Strings.settingsSectionAbout) {
                    LabeledContent(.Strings.settingsAppName, value: "Fichier")
                    LabeledContent(.Strings.settingsVersion, value: appVersionString)
                    LabeledContent(.Strings.settingsProtocol, value: "SMB2 / SMB3")
                }
            }
            .navigationTitle(.Strings.settingsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(.Strings.commonDone) {
                        dismiss()
                    }
                    .font(.body.bold())
                }
            }
        }
    }
    
    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
    
    private func clearCache() {
        isClearingCache = true
        Task {
            MediaCacheManager.shared.clearAllCache()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            await MainActor.run {
                cacheSizeString = MediaCacheManager.shared.formattedCacheSize()
                isClearingCache = false
            }
        }
    }
}
