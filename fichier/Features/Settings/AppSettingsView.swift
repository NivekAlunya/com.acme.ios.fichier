//
//  AppSettingsView.swift
//  fichier
//

import SwiftUI
import UIKit
import FichierKit

/// Modal settings view configuring application-wide preferences, cache storage, and system permissions.
///
/// Organized into distinct functional sections:
/// 1. **System Settings**: Direct deep-link to the iOS Settings app for Network and Privacy permissions.
/// 2. **Storage & Cache**: Live telemetry of on-disk thumbnail and video cache usage with a destructive clear action.
/// 3. **Slideshow Preferences**: Transition animation style (`.slide`, `.dissolve`, etc.) and cycling duration.
/// 4. **Gallery Defaults**: Preferred view mode (`.grid` vs `.list`), grid density (`GridSize`), and sort order.
/// 5. **PDF Reader Defaults**: Default page layout reading mode (`PDFReadingMode`).
/// 6. **Diagnostics**: Share the most recent crash report captured by `CrashReporting` (a placeholder is shown when none exists).
/// 7. **About**: Application version, build number, and SMB protocol support details.
struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
    // Gallery & Slideshow Settings
    @AppStorage("slideshow_timer_interval") private var slideshowInterval: Double = 3.0
    @AppStorage("slideshow_transition_style") private var transitionStyle: SlideshowTransitionStyle = .slide
    @AppStorage("gallery_view_mode") private var viewMode: ViewMode = .grid
    @AppStorage("gallery_sort_option") private var sortOption: SortOption = .nameAsc
    @AppStorage("gallery_grid_size") private var gridSize: GridSize = .medium
    
    // PDF Reader Settings
    #if !os(tvOS)
    @AppStorage("pdf_reading_mode") private var readingMode: PDFReadingMode = .continuous
    #endif
    
    // Cache State
    @State private var cacheSizeString: String = "…"
    @State private var isShowingClearConfirmation = false
    @State private var isClearingCache = false
    
    // Diagnostics State
    @State private var latestCrashReportURL: URL?
    
    var body: some View {
        NavigationStack {
            Form {
                // 1. iOS System Settings (Local Network, Permissions, Language)
                #if !os(tvOS)
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
                #endif
                
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
                
                // 5. PDF Reader Defaults
                #if !os(tvOS)
                Section(String(localized: "PDF Reader", comment: "PDF Reader settings section")) {
                    Picker(String(localized: "Default Reading Mode", comment: "Default PDF reading mode"), selection: $readingMode) {
                        ForEach(PDFReadingMode.allCases) { mode in
                            Label(mode.localizedTitle, systemImage: mode.iconName).tag(mode)
                        }
                    }
                }
                #endif
                
                // 6. Diagnostics (crash report sharing; Wappn is debug-only, see `CrashReporting`)
                #if DEBUG
                Section {
                    if let latestCrashReportURL {
                        ShareLink(item: latestCrashReportURL) {
                            Label(.Strings.settingsButtonShareCrashReport, systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Text(.Strings.settingsCrashReportNone)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(.Strings.settingsSectionDiagnostics)
                } footer: {
                    Text(.Strings.settingsCrashReportFooter)
                }
                #endif
                
                // 7. About & Version Information
                Section(.Strings.settingsSectionAbout) {
                    LabeledContent(.Strings.settingsAppName, value: "Fichier")
                    LabeledContent(.Strings.settingsVersion, value: appVersionString)
                    LabeledContent(.Strings.settingsProtocol, value: "SMB2 / SMB3")
                }
            }
            .navigationTitle(.Strings.settingsTitle)
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(.Strings.commonDone) {
                        dismiss()
                    }
                    .font(.body.bold())
                }
            }
            .task {
                cacheSizeString = await MediaCacheManager.shared.formattedCacheSize()
            }
            #if DEBUG
            .onAppear {
                latestCrashReportURL = CrashReportStore().latestReportURL()
            }
            #endif
        }
    }
    
    /// Formatted application version and build string from the main bundle dictionary.
    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
    
    /// Asynchronously deletes all cached thumbnails and downloaded media files, updating telemetry.
    private func clearCache() {
        isClearingCache = true
        Task {
            await MediaCacheManager.shared.clearAllCacheAsync()
            AppHapticFeedback.medium()
            let newSize = await MediaCacheManager.shared.formattedCacheSize()
            cacheSizeString = newSize
            isClearingCache = false
        }
    }
}
