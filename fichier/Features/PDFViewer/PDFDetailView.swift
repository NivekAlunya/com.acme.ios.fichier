//
//  PDFDetailView.swift
//  fichier
//

#if !os(tvOS)
import SwiftUI
import PDFKit
import FichierKit

/// Full-screen viewModel.document viewer presenting PDF files with continuous and horizontal book spread modes.
///
/// ### Core Capabilities
/// - **Dual Reading Modes**:
///   1. *Continuous Scroll*: Vertical single-page viewModel.document scrolling using native `PDFKitRepresentedView`.
///   2. *Book Mode*: Interactive horizontal swipe `TabView` rendering facing page spreads (`PDFSpreadPageView`).
/// - **Leading Thumbnail Sidebar**: Docked thumbnail strip (`PDFLeadingThumbnailSidebarView`) allowing rapid
///   jumping to any page with synchronized scrolling and haptic feedback.
/// - **Progressive Document Ingestion**: Retrieves local or cached files immediately, or streams from SMB servers
///   via `manager.fetchDocumentURL`, throttling UI progress updates to 128 KB byte intervals.
/// - **Hardware Keyboard Support**: Complete iPad / Mac shortcuts (`Esc` to dismiss, `B` to toggle book mode, Arrow keys to turn pages).
struct PDFDetailView: View {
    /// Shared storage location manager handling viewModel.document streaming and caching.
    var manager: StorageLocationManager
    
    /// Playlist of viewModel.document items available in this browsing session.
    let documents: [MediaItem]
    
    /// The initial viewModel.document item focused when the viewer opened.
    let initialItem: MediaItem
    
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: PDFDetailViewModel

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

    
    /// Designated public initializer.
    ///
    /// - Parameters:
    ///   - manager: Shared storage location manager.
    ///   - documents: Array of candidate media items.
    ///   - initialItem: Initial focused viewModel.document item.
    public init(
        manager: StorageLocationManager,
        documents: [MediaItem] = [],
        initialItem: MediaItem
    ) {
        self.manager = manager
        var pdfs = documents.filter(\.isPDF)
        if !pdfs.contains(where: { $0.id == initialItem.id }) {
            pdfs.append(initialItem)
        }
        self.documents = pdfs.isEmpty ? [initialItem] : pdfs
        self.initialItem = initialItem
        self._viewModel = State(
            initialValue: PDFDetailViewModel(
                manager: manager,
                documents: self.documents,
                initialItem: initialItem
            )
        )
    }
    
    /// Zero-based index of the current viewModel.document within the active playlist.
    private var currentIndex: Int {
        documents.firstIndex(where: { $0.id == viewModel.currentItem.id }) ?? 0
    }
    
    /// Ordered array of page spreads synthesized for the current viewModel.document.
    private var spreads: [PDFSpread] {
        guard let document = viewModel.document else { return [] }
        return PDFSpread.buildSpreads(pageCount: document.pageCount, displaysAsBook: displaysAsBook)
    }
    
    /// Synchronizes the active book spread index with the current visible page number.
    private func syncCurrentSpread() {
        if let match = spreads.firstIndex(where: { $0.pageIndices.contains(viewModel.currentPage - 1) }) {
            viewModel.currentSpreadIndex = match
            let spread = spreads[match]
            self.viewModel.currentPage = spread.firstPageNumber
            self.viewModel.endVisiblePage = spread.lastPageNumber
        }
    }
    
    /// Formatted status string displaying page numbers (e.g. "Page 1 of 40" or "Pages 2–3 of 40").
    private var pageInfoText: String {
        if isBookMode && viewModel.currentPage != viewModel.endVisiblePage && viewModel.endVisiblePage > viewModel.currentPage {
            return "Pages \(viewModel.currentPage)–\(viewModel.endVisiblePage) of \(viewModel.totalPages)"
        } else {
            return "Page \(viewModel.currentPage) of \(viewModel.totalPages)"
        }
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let document = viewModel.document {
                if isBookMode {
                    // Book Mode: Interactive 1:1 finger swipe TabView (like PictureDetailView)
                    TabView(selection: $viewModel.currentSpreadIndex) {
                        ForEach(spreads) { spread in
                            PDFSpreadPageView(
                                document: document,
                                spread: spread,
                                onTap: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        viewModel.showControls.toggle()
                                    }
                                }
                            )
                            .tag(spread.id)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea()
                    .onChange(of: viewModel.currentSpreadIndex) { _, newIndex in
                        guard newIndex >= 0 && newIndex < spreads.count else { return }
                        let spread = spreads[newIndex]
                        self.viewModel.currentPage = spread.firstPageNumber
                        self.viewModel.endVisiblePage = spread.lastPageNumber
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
                                if self.viewModel.currentPage != cur {
                                    self.viewModel.currentPage = cur
                                }
                                let maxTotal = max(1, total)
                                if self.viewModel.totalPages != maxTotal {
                                    self.viewModel.totalPages = maxTotal
                                }
                            }
                        },
                        onPageRangeChange: { first, last, total in
                            Task { @MainActor in
                                if self.viewModel.currentPage != first {
                                    self.viewModel.currentPage = first
                                }
                                if self.viewModel.endVisiblePage != last {
                                    self.viewModel.endVisiblePage = last
                                }
                                let maxTotal = max(1, total)
                                if self.viewModel.totalPages != maxTotal {
                                    self.viewModel.totalPages = maxTotal
                                }
                            }
                        },
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.showControls.toggle()
                            }
                        },
                        onCoordinatorCreated: { coord in
                            self.viewModel.coordinator = coord
                        },
                        onPDFViewCreated: { view in
                            self.viewModel.activePDFView = view
                        }
                    )
                    .ignoresSafeArea()
                }
            } else if viewModel.isLoading {
                loadingOverlay
            } else if let error = viewModel.errorMessage {
                errorOverlay(error: error)
            }
            
            // Leading-Edge Thumbnail Sidebar
            if viewModel.totalPages > 1, let document = viewModel.document {
                HStack {
                    PDFLeadingThumbnailSidebarView(
                        document: document,
                        currentPage: viewModel.currentPage,
                        endVisiblePage: viewModel.endVisiblePage,
                        onPageSelected: { targetPage in
                            if isBookMode {
                                if let match = spreads.firstIndex(where: { $0.pageIndices.contains(targetPage - 1) }) {
                                    viewModel.currentSpreadIndex = match
                                }
                            } else {
                                viewModel.coordinator?.goToPage(index: targetPage - 1)
                            }
                        }
                    )
                    .id(viewModel.currentItem.id)
                    .padding(.leading, 12)
                    .padding(.top, 70)
                    .padding(.bottom, 80)
                    
                    Spacer()
                }
                .opacity(viewModel.showControls ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.2), value: viewModel.showControls)
                .transition(.identity)
            }
            
            // HUD Overlays
            if viewModel.showControls && viewModel.document != nil {
                VStack {
                    PDFViewerTopBarView(
                        item: viewModel.currentItem,
                        currentIndex: currentIndex,
                        totalCount: documents.count,
                        onDismiss: { dismiss() }
                    )
                    Spacer()
                    PDFViewerBottomBarView(
                        hasMultipleDocuments: documents.count > 1,
                        readingMode: $readingMode,
                        pageInfoText: pageInfoText,
                        isFavorite: FavoritesManager.shared.isFavorite(viewModel.currentItem),
                        localFileURL: viewModel.localFileURL,
                        currentName: viewModel.currentItem.name,
                        onPreviousDocument: { goToPreviousDocument() },
                        onNextDocument: { goToNextDocument() },
                        onToggleFavorite: { FavoritesManager.shared.toggleFavorite(viewModel.currentItem) }
                    )
                    .padding(.bottom, 20)
                }
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .task(id: "\(viewModel.currentItem.id)-\(viewModel.reloadAttempt)") {
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
                // Turn pages backward (Left arrow)
                Button("") {
                    if isBookMode {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            viewModel.currentSpreadIndex = max(0, viewModel.currentSpreadIndex - 1)
                        }
                    } else {
                        viewModel.coordinator?.goToPrevious()
                    }
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                // Turn pages forward (Right arrow)
                Button("") {
                    if isBookMode {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            viewModel.currentSpreadIndex = min(spreads.count - 1, viewModel.currentSpreadIndex + 1)
                        }
                    } else {
                        viewModel.coordinator?.goToNext()
                    }
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                // Document playlist navigation shortcuts: "p" and "Cmd + Left Arrow"
                Button("") { goToPreviousDocument() }
                    .keyboardShortcut("p", modifiers: [])
                Button("") { goToPreviousDocument() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
                // Document playlist navigation shortcuts: "n" and "Cmd + Right Arrow"
                Button("") { goToNextDocument() }
                    .keyboardShortcut("n", modifiers: [])
                Button("") { goToNextDocument() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
    }
    
    // MARK: - Document Playlist Navigation
    
    /// Navigates to the next PDF viewModel.document in the queue with cyclic wrapping.
    private func goToNextDocument() {
        guard !documents.isEmpty else { return }
        let nextIndex = (currentIndex + 1) % documents.count
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            viewModel.currentItem = documents[nextIndex]
            resetDocumentState()
        }
    }
    
    /// Navigates to the previous PDF viewModel.document in the queue with cyclic wrapping.
    private func goToPreviousDocument() {
        guard !documents.isEmpty else { return }
        let prevIndex = (currentIndex - 1 + documents.count) % documents.count
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            viewModel.currentItem = documents[prevIndex]
            resetDocumentState()
        }
    }
    
    /// Resets transient reader state before loading a newly switched viewModel.document.
    private func resetDocumentState() {
        viewModel.document = nil
        viewModel.localFileURL = nil
        viewModel.isLoading = true
        viewModel.errorMessage = nil
        viewModel.currentPage = 1
        viewModel.endVisiblePage = 1
        viewModel.totalPages = 1
        viewModel.currentSpreadIndex = 0
        viewModel.bytesReceived = 0
        viewModel.totalBytes = 0
        viewModel.lastReportedBytes = 0
    }
    
    // MARK: - Loading Overlay
    
    /// Loading view displaying determinate progress percentage or indeterminate spinner.
    private var loadingOverlay: some View {
        VStack(spacing: 16) {
            if viewModel.totalBytes > 0 {
                let progress = Double(viewModel.bytesReceived) / Double(viewModel.totalBytes)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                    .tint(.white)
                Text("\(Int(progress * 100))% • \(viewModel.currentItem.formattedSize)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            } else {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.4)
                Text(viewModel.currentItem.name)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 32)
                Text(viewModel.currentItem.formattedSize)
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
                    viewModel.reloadAttempt += 1
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
    }
    
    // MARK: - Loading Logic
    
    /// Configures reader state once the PDF viewModel.document is successfully parsed, and triggers background thumbnail generation.
    @MainActor
    private func onDocumentLoaded(_ doc: PDFDocument) {
        self.viewModel.document = doc
        self.viewModel.totalPages = max(1, doc.pageCount)
        self.syncCurrentSpread()
        self.viewModel.isLoading = false
        
        // Asynchronously generate or upgrade the thumbnail from the in-memory viewModel.document while reading
        Task {
            await manager.upgradePDFThumbnail(for: viewModel.currentItem, from: doc)
        }
    }
    
    /// Asynchronously locates or streams the PDF viewModel.document, updating progress and instantiating `PDFDocument`.
    @MainActor
    private func loadDocument() async {
        viewModel.isLoading = true
        viewModel.errorMessage = nil
        viewModel.bytesReceived = 0
        viewModel.totalBytes = 0
        viewModel.lastReportedBytes = 0
        
        // Check if localURL is available
        if let local = viewModel.currentItem.localURL, FileManager.default.fileExists(atPath: local.path) {
            self.viewModel.localFileURL = local
            if let doc = PDFDocument(url: local) {
                onDocumentLoaded(doc)
                return
            }
        }
        
        // Check if cached locally in documentsDirectory
        if MediaCacheManager.shared.hasCachedDocument(for: viewModel.currentItem) {
            let cachedURL = MediaCacheManager.shared.localDocumentURL(for: viewModel.currentItem)
            if let doc = PDFDocument(url: cachedURL) {
                self.viewModel.localFileURL = cachedURL
                onDocumentLoaded(doc)
                return
            }
        }
        
        // Fetch/download via manager
        do {
            let url = try await manager.fetchDocumentURL(for: viewModel.currentItem) { received, total in
                Task { @MainActor in
                    if received == total || (received - self.viewModel.lastReportedBytes) > 131_072 {
                        self.viewModel.bytesReceived = received
                        self.viewModel.totalBytes = total
                        self.viewModel.lastReportedBytes = received
                    }
                }
            }
            guard !Task.isCancelled else { return }
            self.viewModel.localFileURL = url
            if let doc = PDFDocument(url: url) {
                onDocumentLoaded(doc)
            } else {
                self.viewModel.errorMessage = String(localized: "Unable to parse PDF content", comment: "Invalid PDF format")
                self.viewModel.isLoading = false
            }
        } catch {
            guard !Task.isCancelled else { return }
            self.viewModel.errorMessage = error.localizedDescription
            self.viewModel.isLoading = false
        }
    }
}

#endif // !os(tvOS)
