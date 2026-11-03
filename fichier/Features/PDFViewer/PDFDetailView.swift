//
//  PDFDetailView.swift
//  fichier
//

import SwiftUI
import PDFKit

struct PDFDetailView: View {
    var manager: SMBDirectManager
    let item: MediaItem
    
    @Environment(\.dismiss) private var dismiss
    @State private var document: PDFDocument?
    @State private var localFileURL: URL?
    @State private var isLoading = true
    @State private var bytesReceived: Int64 = 0
    @State private var totalBytes: Int64 = 0
    @State private var lastReportedBytes: Int64 = 0
    @State private var errorMessage: String?
    @State private var showControls = true
    @State private var currentPage = 1
    @State private var endVisiblePage = 1
    @State private var totalPages = 1
    @State private var isBookMode = false
    @State private var displaysAsBook = true
    @State private var activePDFView: PDFView?
    @State private var reloadAttempt = 0
    
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
                PDFKitRepresentedView(
                    document: document,
                    isBookMode: isBookMode,
                    displaysAsBook: displaysAsBook,
                    onPageChange: { cur, total in
                        self.currentPage = cur
                        self.totalPages = max(1, total)
                    },
                    onPageRangeChange: { first, last, total in
                        self.currentPage = first
                        self.endVisiblePage = last
                        self.totalPages = max(1, total)
                    },
                    onTap: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showControls.toggle()
                        }
                    },
                    onPDFViewCreated: { view in
                        self.activePDFView = view
                    }
                )
                .ignoresSafeArea()
            } else if isLoading {
                loadingOverlay
            } else if let error = errorMessage {
                errorOverlay(error: error)
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
        .background {
            Group {
                Button("") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isBookMode.toggle()
                    }
                }
                .keyboardShortcut("b", modifiers: [])
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
    }
    
    // MARK: - Top HUD
    
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
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isBookMode = false
                    }
                } label: {
                    Label(
                        String(localized: "Single Page", comment: "Single page continuous scroll"),
                        systemImage: !isBookMode ? "checkmark" : "doc.text"
                    )
                }
                
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isBookMode = true
                    }
                } label: {
                    Label(
                        String(localized: "Book View (Two Pages)", comment: "Two pages side-by-side book display"),
                        systemImage: isBookMode ? "checkmark" : "book"
                    )
                }
                
                if isBookMode {
                    Divider()
                    Toggle(isOn: $displaysAsBook) {
                        Label(
                            String(localized: "First Page as Cover", comment: "Display first page standalone as cover"),
                            systemImage: "book.closed"
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
                    isBookMode.toggle()
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
    
    private var bottomHUD: some View {
        VStack(spacing: 10) {
            // Page Indicator Pill
            Text(pageInfoText)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.7)))
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
            
            // Thumbnail Scrubber Bar
            if totalPages > 1, let activePDFView {
                PDFThumbnailScrubberView(pdfView: activePDFView)
                    .frame(height: 64)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.black.opacity(0.75))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                            )
                    )
                    .padding(.horizontal, 16)
            }
        }
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
                self.document = doc
                self.totalPages = max(1, doc.pageCount)
                self.isLoading = false
                return
            }
        }
        
        // Check if cached locally in documentsDirectory
        if MediaCacheManager.shared.hasCachedDocument(for: item) {
            let cachedURL = MediaCacheManager.shared.localDocumentURL(for: item)
            if let doc = PDFDocument(url: cachedURL) {
                self.localFileURL = cachedURL
                self.document = doc
                self.totalPages = max(1, doc.pageCount)
                self.isLoading = false
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
                self.document = doc
                self.totalPages = max(1, doc.pageCount)
                self.isLoading = false
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
