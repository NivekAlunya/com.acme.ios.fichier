//
//  PDFDetailView.swift
//  fichier
//

#if !os(tvOS)
import SwiftUI
import PDFKit

/// Full-screen document viewer presenting PDF files with continuous and horizontal book spread modes.
///
/// ### Core Capabilities
/// - **Dual Reading Modes**:
///   1. *Continuous Scroll*: Vertical single-page document scrolling using native `PDFKitRepresentedView`.
///   2. *Book Mode*: Interactive horizontal swipe `TabView` rendering facing page spreads (`PDFSpreadPageView`).
/// - **Leading Thumbnail Sidebar**: Docked thumbnail strip (`PDFLeadingThumbnailSidebarView`) allowing rapid
///   jumping to any page with synchronized scrolling and haptic feedback.
/// - **Progressive Document Ingestion**: Retrieves local or cached files immediately, or streams from SMB servers
///   via `manager.fetchDocumentURL`, throttling UI progress updates to 128 KB byte intervals.
/// - **Hardware Keyboard Support**: Complete iPad / Mac shortcuts (`Esc` to dismiss, `B` to toggle book mode, Arrow keys to turn pages).
struct PDFDetailView: View {
    /// Shared storage location manager handling document streaming and caching.
    var manager: StorageLocationManager
    
    /// Target document media item.
    let item: MediaItem
    
    @Environment(\.dismiss) private var dismiss
    
    /// Loaded and parsed PDFKit document instance.
    @State private var document: PDFDocument?
    
    /// Local file URL for the cached or downloaded PDF document.
    @State private var localFileURL: URL?
    
    /// Indicates whether document download or parsing is actively in flight.
    @State private var isLoading = true
    
    /// Number of bytes received so far during network download.
    @State private var bytesReceived: Int64 = 0
    
    /// Total expected byte size of the document.
    @State private var totalBytes: Int64 = 0
    
    /// Tracks byte progress milestones to throttle `@MainActor` UI re-renders to 128 KB intervals.
    @State private var lastReportedBytes: Int64 = 0
    
    /// Error description string if loading or parsing fails.
    @State private var errorMessage: String?
    
    /// Controls visibility of floating top and bottom navigation HUD toolbars.
    @State private var showControls = true
    
    /// 1-based index of the currently active starting visible page.
    @State private var currentPage = 1
    
    /// 1-based index of the currently active ending visible page.
    @State private var endVisiblePage = 1
    
    /// Total number of pages in the document.
    @State private var totalPages = 1
    
    /// User preference reading mode persisted across sessions.
    @AppStorage("pdf_reading_mode") private var readingMode: PDFReadingMode = .continuous
    
    /// Indicates whether book spread mode is currently active.
    private var isBookMode: Bool {
        readingMode.isBookMode
    }
    
    /// Indicates whether Page 1 is displayed as an isolated cover page in book mode.
    private var displaysAsBook: Bool {
        readingMode.displaysAsBook
    }
    
    /// Currently focused spread index in book mode `TabView`.
    @State private var currentSpreadIndex = 0
    
    /// Active `PDFView` reference captured from `PDFKitRepresentedView`.
    @State private var activePDFView: PDFView?
    
    /// Active coordinator managing gestures and PDFKit notifications.
    @State private var coordinator: PDFKitCoordinator?
    
    /// Retry attempt counter used to force `.task` reload upon tap.
    @State private var reloadAttempt = 0
    
    /// Ordered array of page spreads synthesized for the current document.
    private var spreads: [PDFSpread] {
        guard let document else { return [] }
        return PDFSpread.buildSpreads(pageCount: document.pageCount, displaysAsBook: displaysAsBook)
    }
    
    /// Synchronizes the active book spread index with the current visible page number.
    private func syncCurrentSpread() {
        if let match = spreads.firstIndex(where: { $0.pageIndices.contains(currentPage - 1) }) {
            currentSpreadIndex = match
            let spread = spreads[match]
            self.currentPage = spread.firstPageNumber
            self.endVisiblePage = spread.lastPageNumber
        }
    }
    
    /// Formatted status string displaying page numbers (e.g. "Page 1 of 40" or "Pages 2–3 of 40").
    private var pageInfoText: String {
        if isBookMode && currentPage != endVisiblePage && endVisiblePage > currentPage {
            return "Pages \(currentPage)–\(endVisiblePage) of \(totalPages)"
        } else {
            return "Page \(currentPage) of \(totalPages)"
        }
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let document {
                if isBookMode {
                    // Book Mode: Interactive 1:1 finger swipe TabView (like PictureDetailView)
                    TabView(selection: $currentSpreadIndex) {
                        ForEach(spreads) { spread in
                            PDFSpreadPageView(
                                document: document,
                                spread: spread,
                                onTap: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showControls.toggle()
                                    }
                                }
                            )
                            .tag(spread.id)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea()
                    .onChange(of: currentSpreadIndex) { _, newIndex in
                        guard newIndex >= 0 && newIndex < spreads.count else { return }
                        let spread = spreads[newIndex]
                        self.currentPage = spread.firstPageNumber
                        self.endVisiblePage = spread.lastPageNumber
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                } else {
                    // Continuous Single-Page Mode
                    PDFKitRepresentedView(
                        document: document,
                        isBookMode: false,
                        displaysAsBook: false,
                        onPageChange: { cur, total in
                            Task { @MainActor in
                                if self.currentPage != cur {
                                    self.currentPage = cur
                                }
                                let maxTotal = max(1, total)
                                if self.totalPages != maxTotal {
                                    self.totalPages = maxTotal
                                }
                            }
                        },
                        onPageRangeChange: { first, last, total in
                            Task { @MainActor in
                                if self.currentPage != first {
                                    self.currentPage = first
                                }
                                if self.endVisiblePage != last {
                                    self.endVisiblePage = last
                                }
                                let maxTotal = max(1, total)
                                if self.totalPages != maxTotal {
                                    self.totalPages = maxTotal
                                }
                            }
                        },
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showControls.toggle()
                            }
                        },
                        onCoordinatorCreated: { coord in
                            self.coordinator = coord
                        },
                        onPDFViewCreated: { view in
                            self.activePDFView = view
                        }
                    )
                    .ignoresSafeArea()
                }
            } else if isLoading {
                loadingOverlay
            } else if let error = errorMessage {
                errorOverlay(error: error)
            }
            
            // Leading-Edge Thumbnail Sidebar
            if totalPages > 1, let document {
                HStack {
                    PDFLeadingThumbnailSidebarView(
                        document: document,
                        currentPage: currentPage,
                        endVisiblePage: endVisiblePage,
                        onPageSelected: { targetPage in
                            if isBookMode {
                                if let match = spreads.firstIndex(where: { $0.pageIndices.contains(targetPage - 1) }) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        currentSpreadIndex = match
                                    }
                                }
                            } else {
                                coordinator?.goToPage(index: targetPage - 1)
                            }
                        }
                    )
                    .padding(.leading, 12)
                    .padding(.top, 70)
                    .padding(.bottom, 80)
                    
                    Spacer()
                }
                .opacity(showControls ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.2), value: showControls)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            
            // HUD Overlays
            if showControls && document != nil {
                VStack {
                    topHUD
                    Spacer()
                    bottomHUD
                }
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .task(id: "\(item.id)-\(reloadAttempt)") {
            await loadDocument()
        }
        .onChange(of: readingMode) { _, newMode in
            if newMode.isBookMode {
                syncCurrentSpread()
            }
        }
        .background {
            Group {
                Button("") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        readingMode = isBookMode ? .continuous : .book
                        if readingMode.isBookMode {
                            syncCurrentSpread()
                        }
                    }
                }
                .keyboardShortcut("b", modifiers: [])
                Button("") {
                    if isBookMode {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            currentSpreadIndex = max(0, currentSpreadIndex - 1)
                        }
                    } else {
                        coordinator?.goToPrevious()
                    }
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                Button("") {
                    if isBookMode {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            currentSpreadIndex = min(spreads.count - 1, currentSpreadIndex + 1)
                        }
                    } else {
                        coordinator?.goToNext()
                    }
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
    }
    
    // MARK: - Top HUD
    
    /// Translucent top action bar displaying file title, pagination, book mode selector, and export tools.
    private var topHUD: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Close", comment: "Accessibility label to close document viewer"))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                HStack(spacing: 6) {
                    Text(item.formattedSize)
                    Text("•")
                    Text(pageInfoText)
                }
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            // Book Mode (Two Pages Side-by-Side) Toggle & Options
            Menu {
                ForEach(PDFReadingMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            readingMode = mode
                            if mode.isBookMode {
                                syncCurrentSpread()
                            }
                        }
                    } label: {
                        Label(
                            mode.localizedTitle,
                            systemImage: readingMode == mode ? "checkmark" : mode.iconName
                        )
                    }
                }
            } label: {
                Image(systemName: isBookMode ? "book.fill" : "book")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isBookMode ? Color.blue : Color.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            } primaryAction: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    readingMode = isBookMode ? .continuous : .book
                    if readingMode.isBookMode {
                        syncCurrentSpread()
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isBookMode ? String(localized: "Switch to Single Page View", comment: "Accessibility label") : String(localized: "Switch to Book View", comment: "Accessibility label"))
            
            Button {
                FavoritesManager.shared.toggleFavorite(item)
            } label: {
                Image(systemName: FavoritesManager.shared.isFavorite(item) ? "heart.fill" : "heart")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(FavoritesManager.shared.isFavorite(item) ? Color.red : Color.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(FavoritesManager.shared.isFavorite(item) ? String(localized: "Remove from Favorites", comment: "Accessibility label to unfavorite") : String(localized: "Add to Favorites", comment: "Accessibility label to favorite"))
            
            if let localFileURL {
                ShareLink(item: localFileURL, preview: SharePreview(item.name)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Share Document", comment: "Accessibility label to share document"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.75), Color.black.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }
    
    // MARK: - Bottom HUD
    
    /// Docked translucent status pill displaying the active page numbers and document length.
    private var bottomHUD: some View {
        Text(pageInfoText)
            .font(.system(size: 12, weight: .semibold))
            .monospacedDigit()
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 20)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.0), Color.black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            )
    }
    
    // MARK: - Loading Overlay
    
    /// Loading view displaying determinate progress percentage or indeterminate spinner.
    private var loadingOverlay: some View {
        VStack(spacing: 16) {
            if totalBytes > 0 {
                let progress = Double(bytesReceived) / Double(totalBytes)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                    .tint(.white)
                Text("\(Int(progress * 100))% • \(item.formattedSize)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            } else {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.4)
                Text(item.name)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 32)
                Text(item.formattedSize)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Button(String(localized: "Cancel", comment: "Cancel loading button")) {
                dismiss()
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .padding(.top, 8)
        }
    }
    
    // MARK: - Error Overlay
    
    /// Error overlay view presenting descriptive failure messages with retry and close buttons.
    private func errorOverlay(error: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.yellow)
            
            Text(String(localized: "Unable to Open Document", comment: "PDF load error title"))
                .font(.headline)
                .foregroundColor(.white)
            
            Text(error)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            HStack(spacing: 16) {
                Button(String(localized: "Close", comment: "Close button")) {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .tint(.white)
                
                Button(String(localized: "Retry", comment: "Retry button")) {
                    reloadAttempt += 1
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
    }
    
    // MARK: - Loading Logic
    
    /// Configures reader state once the PDF document is successfully parsed, and triggers background thumbnail generation.
    @MainActor
    private func onDocumentLoaded(_ doc: PDFDocument) {
        self.document = doc
        self.totalPages = max(1, doc.pageCount)
        self.syncCurrentSpread()
        self.isLoading = false
        
        // Asynchronously generate or upgrade the thumbnail from the in-memory document while reading
        Task {
            await manager.upgradePDFThumbnail(for: item, from: doc)
        }
    }
    
    /// Asynchronously locates or streams the PDF document, updating progress and instantiating `PDFDocument`.
    @MainActor
    private func loadDocument() async {
        isLoading = true
        errorMessage = nil
        bytesReceived = 0
        totalBytes = 0
        lastReportedBytes = 0
        
        // Check if localURL is available
        if let local = item.localURL, FileManager.default.fileExists(atPath: local.path) {
            self.localFileURL = local
            if let doc = PDFDocument(url: local) {
                onDocumentLoaded(doc)
                return
            }
        }
        
        // Check if cached locally in documentsDirectory
        if MediaCacheManager.shared.hasCachedDocument(for: item) {
            let cachedURL = MediaCacheManager.shared.localDocumentURL(for: item)
            if let doc = PDFDocument(url: cachedURL) {
                self.localFileURL = cachedURL
                onDocumentLoaded(doc)
                return
            }
        }
        
        // Fetch/download via manager
        do {
            let url = try await manager.fetchDocumentURL(for: item) { received, total in
                Task { @MainActor in
                    if received == total || (received - self.lastReportedBytes) > 131_072 {
                        self.bytesReceived = received
                        self.totalBytes = total
                        self.lastReportedBytes = received
                    }
                }
            }
            guard !Task.isCancelled else { return }
            self.localFileURL = url
            if let doc = PDFDocument(url: url) {
                onDocumentLoaded(doc)
            } else {
                self.errorMessage = String(localized: "Unable to parse PDF content", comment: "Invalid PDF format")
                self.isLoading = false
            }
        } catch {
            guard !Task.isCancelled else { return }
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }
}

#endif // !os(tvOS)
