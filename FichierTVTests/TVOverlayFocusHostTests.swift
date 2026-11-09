//
//  TVOverlayFocusHostTests.swift
//  FichierTVTests
//
//

import Foundation
import SwiftUI
import Testing
import UIKit
@testable import FichierTV
import FichierKit

@Suite("Host App Focus Engine Tests")
struct TVOverlayFocusHostTests {
    @Test("Video overlay scrubber and playback buttons receive @FocusState focus and expose UIKit focus items")
    @MainActor
    func testVideoOverlayButtonsAreFocusableInHostWindow() async throws {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            return
        }

        var recordedTargets: [TVVideoOverlayFocusTarget?] = []

        let hostingController = UIHostingController(
            rootView: TVVideoOverlayControlsView(
                title: "Sample.mkv",
                currentTime: 30,
                duration: 120,
                isPlaying: true,
                isScrubbing: false,
                scrubbingTime: nil,
                isTracksSheetPresented: false,
                initialFocusTarget: .playPause,
                onFocusChanged: { target in
                    recordedTargets.append(target)
                },
                onScrubStep: { _ in },
                onScrubberSelect: {},
                onPrevious: {},
                onTogglePlayPause: {},
                onNext: {},
                onOpenTracks: {}
            )
        )

        let window = UIWindow(windowScene: windowScene)
        window.frame = windowScene.coordinateSpace.bounds
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        window.setNeedsFocusUpdate()
        window.updateFocusIfNeeded()

        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            hostingController.view.layoutIfNeeded()
            window.updateFocusIfNeeded()
            let focusItems = collectFocusableItems(in: hostingController.view, bounds: window.bounds)
            if focusItems.count >= 5 && recordedTargets.contains(.playPause) {
                break
            }
        }

        let focusItems = collectFocusableItems(in: hostingController.view, bounds: window.bounds)
        #expect(focusItems.count >= 5)

        let focusSystem = UIFocusSystem.focusSystem(for: window)
        let focusedItem = try #require(focusSystem?.focusedItem)
        #expect(focusedItem.frame.width < window.bounds.width * 0.5)
        #expect(focusedItem.frame.height < window.bounds.height * 0.3)
        #expect(focusedItem.frame.midY > window.bounds.midY)
        #expect(recordedTargets.contains(.playPause))
    }

    @Test("TVVideoPlayerView swaps hidden full-screen button for multi-button overlay focus hierarchy")
    @MainActor
    func testVideoPlayerViewRevealOverlayTransfersFocus() async throws {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            return
        }

        let videoURL = try await TVVideoTestFixtureGenerator.createSampleMP4File()
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let item1 = MediaSourceItem(
            id: "v1",
            name: "clip1.mp4",
            path: "clip1.mp4",
            type: .video,
            localURL: videoURL
        )
        let item2 = MediaSourceItem(
            id: "v2",
            name: "clip2.mp4",
            path: "clip2.mp4",
            type: .video,
            localURL: videoURL
        )

        let viewModel = TVVideoPlayerViewModel(initialItem: item1, videos: [item1, item2])
        defer { viewModel.tearDown() }

        let hostingController = UIHostingController(
            rootView: TVVideoPlayerView(viewModel: viewModel)
        )
        let window = UIWindow(windowScene: windowScene)
        window.frame = windowScene.coordinateSpace.bounds
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            hostingController.view.layoutIfNeeded()
            window.updateFocusIfNeeded()
            if !collectFocusableItems(in: hostingController.view, bounds: window.bounds).isEmpty {
                break
            }
        }

        let hiddenFocusItems = collectFocusableItems(in: hostingController.view, bounds: window.bounds)
        #expect(hiddenFocusItems.count == 1)

        viewModel.revealOverlay()

        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            hostingController.view.layoutIfNeeded()
            window.updateFocusIfNeeded()
            let focusItems = collectFocusableItems(in: hostingController.view, bounds: window.bounds)
            if focusItems.count >= 5 {
                break
            }
        }

        let overlayFocusItems = collectFocusableItems(in: hostingController.view, bounds: window.bounds)
        #expect(overlayFocusItems.count >= 5)

        let focusSystem = UIFocusSystem.focusSystem(for: window)
        let focusedItem = try #require(focusSystem?.focusedItem)
        #expect(focusedItem.frame.width < window.bounds.width * 0.5)
        #expect(focusedItem.frame.height < window.bounds.height * 0.3)
        #expect(viewModel.currentFocusTarget == .playPause)
    }

    @Test("TVVideoPlayerView seek preview HUD while overlay hidden preserves single focusable catcher without stealing focus")
    @MainActor
    func testSeekPreviewHUDWhileOverlayHiddenPreservesCatcherFocus() async throws {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            return
        }

        let videoURL = try await TVVideoTestFixtureGenerator.createSampleMP4File()
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let item = MediaSourceItem(
            id: "v_preview_focus",
            name: "preview.mp4",
            path: "preview.mp4",
            type: .video,
            localURL: videoURL
        )
        let clock = StubUptimeClock(now: 100.0)
        let bridge = StubRemoteCommandBridge()
        let viewModel = TVVideoPlayerViewModel(
            initialItem: item,
            videos: [item],
            playbackStore: StubVideoPlaybackStore(),
            resolver: StubMediaSourceResolver(),
            remoteCommandBridge: bridge,
            uptimeProvider: { clock.now }
        )
        defer { viewModel.tearDown() }

        let hostingController = UIHostingController(
            rootView: TVVideoPlayerView(viewModel: viewModel)
        )
        let window = UIWindow(windowScene: windowScene)
        window.frame = windowScene.coordinateSpace.bounds
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            hostingController.view.layoutIfNeeded()
            window.updateFocusIfNeeded()
            if !collectFocusableItems(in: hostingController.view, bounds: window.bounds).isEmpty {
                break
            }
        }

        // Start a hold and force preview visible while HUD overlay remains hidden
        viewModel.nativeEngine.onDurationUpdate?(300.0)
        viewModel.beginRemoteSeek(isForward: true, source: .siriRemoteDirection, timestamp: 100.0)
        viewModel.refreshActiveRemoteSeekPreview(at: 102.0)
        #expect(!viewModel.showOverlay)
        #expect(viewModel.remoteSeekPreview != nil)

        try? await Task.sleep(nanoseconds: 100_000_000)
        hostingController.view.layoutIfNeeded()
        window.updateFocusIfNeeded()

        let focusItemsDuringHold = collectFocusableItems(in: hostingController.view, bounds: window.bounds)
        #expect(focusItemsDuringHold.count == 1)

        let focusSystem = UIFocusSystem.focusSystem(for: window)
        let focusedItem = try #require(focusSystem?.focusedItem)
        #expect(focusedItem is TVPlayerRemoteCatcherUIView)
    }

    @Test("Image viewer overlay controls expose focusable UIKit focus items")
    @MainActor
    func testImageViewerOverlayButtonsAreFocusableInHostWindow() async throws {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            return
        }

        let hostingController = UIHostingController(
            rootView: TVImageViewerOverlayView(
                title: "Photo.jpg",
                currentIndex: 1,
                totalCount: 3,
                isSlideshowPlaying: false,
                canNavigatePrevious: true,
                canNavigateNext: true,
                onPrevious: {},
                onToggleSlideshow: {},
                onNext: {},
                onOpenSettings: {},
                onClose: {}
            )
        )

        let window = UIWindow(windowScene: windowScene)
        window.frame = windowScene.coordinateSpace.bounds
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        window.setNeedsFocusUpdate()
        window.updateFocusIfNeeded()

        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            hostingController.view.layoutIfNeeded()
            window.updateFocusIfNeeded()
            let focusItems = collectFocusableItems(in: hostingController.view, bounds: window.bounds)
            if focusItems.count >= 5 {
                break
            }
        }

        let focusItems = collectFocusableItems(in: hostingController.view, bounds: window.bounds)
        #expect(focusItems.count >= 5)

        let focusSystem = UIFocusSystem.focusSystem(for: window)
        let focusedItem = try #require(focusSystem?.focusedItem)
        #expect(focusedItem.frame.width < window.bounds.width * 0.5)
        #expect(focusedItem.frame.height < window.bounds.height * 0.3)
    }

    @Test("Image viewer overlay bottom focus section covers top Close/Settings X-ranges and keeps boundary focus on bottom row")
    @MainActor
    func testImageViewerOverlayFocusGuidesAndBoundaryTransition() async throws {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            return
        }

        var recordedTargets: [TVImageViewerFocusTarget?] = []

        func makeOverlay(canNext: Bool, initial: TVImageViewerFocusTarget) -> TVImageViewerOverlayView {
            TVImageViewerOverlayView(
                title: "Photo.jpg",
                currentIndex: canNext ? 1 : 2,
                totalCount: 3,
                isSlideshowPlaying: false,
                canNavigatePrevious: true,
                canNavigateNext: canNext,
                initialFocusTarget: initial,
                onFocusChanged: { target in
                    recordedTargets.append(target)
                },
                onPrevious: {},
                onToggleSlideshow: {},
                onNext: {},
                onOpenSettings: {},
                onClose: {}
            )
        }

        let hostingController = UIHostingController(
            rootView: makeOverlay(canNext: true, initial: .next)
        )

        let window = UIWindow(windowScene: windowScene)
        window.frame = windowScene.coordinateSpace.bounds
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        for _ in 0..<25 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            hostingController.view.layoutIfNeeded()
            window.updateFocusIfNeeded()
            let focusItems = collectFocusableItems(in: hostingController.view, bounds: window.bounds)
            if focusItems.count >= 5 && recordedTargets.contains(.next) {
                break
            }
        }

        let itemsWithFrames = collectFocusItemFrames(in: hostingController.view, window: window)
        let topFrames = itemsWithFrames.filter { $0.midY < window.bounds.midY }.sorted { $0.minX < $1.minX }
        let bottomFrames = itemsWithFrames.filter { $0.midY >= window.bounds.midY }.sorted { $0.minX < $1.minX }

        #expect(topFrames.count == 2)
        #expect(bottomFrames.count == 3)

        let closeFrame = try #require(topFrames.first)
        let settingsFrame = try #require(topFrames.last)
        let bottomGuides = collectBottomFocusContainerFrames(in: hostingController.view, window: window)
            .filter { $0.minY > window.bounds.midY && $0.height > 0 && $0.height < window.bounds.height * 0.4 }
        let coversCloseColumn = bottomGuides.contains { rect in
            rect.minX <= closeFrame.maxX && rect.maxX >= closeFrame.minX
        }
        let coversSettingsColumn = bottomGuides.contains { rect in
            rect.minX <= settingsFrame.maxX && rect.maxX >= settingsFrame.minX
        }
        #expect(coversCloseColumn, "Bottom focus section must cover Close button X-range (\(closeFrame)), found guides: \(bottomGuides)")
        #expect(coversSettingsColumn, "Bottom focus section must cover Settings button X-range (\(settingsFrame)), found guides: \(bottomGuides)")

        // Now simulate reaching the final image where Next becomes disabled while Next had focus.
        recordedTargets.removeAll()
        hostingController.rootView = makeOverlay(canNext: false, initial: .next)

        for _ in 0..<25 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            hostingController.view.layoutIfNeeded()
            window.updateFocusIfNeeded()
            if recordedTargets.contains(.toggleSlideshow) {
                break
            }
        }

        let focusSystem = UIFocusSystem.focusSystem(for: window)
        let updatedFocus = try #require(focusSystem?.focusedItem)
        let updatedFrame = windowFrame(of: updatedFocus, window: window)
        #expect(updatedFrame.midY > window.bounds.midY)
        #expect(recordedTargets.last == .toggleSlideshow)
    }

    @Test("Shares root view positions server and Add Server cards near top under segmented tab bar")
    @MainActor
    func testSharesRootViewShelfPositionedNearTop() async throws {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            return
        }

        let sampleServer = SavedSMBConnection(
            host: "192.168.1.10",
            username: "kevin",
            lastConnected: Date(),
            hostname: "Kevin's Mac"
        )
        let store = StubSMBServerStore(
            servers: [sampleServer],
            statuses: [sampleServer.id: .online]
        )
        let resolver = StubMediaSourceResolver()
        let viewModel = TVSharesViewModel(store: store, resolver: resolver)

        let hostingController = UIHostingController(
            rootView: NavigationStack {
                TVSharesRootView(viewModel: viewModel)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Picker("Source", selection: .constant(TVRootSection.shares)) {
                                ForEach(TVRootSection.allCases) { section in
                                    Text(section.rawValue).tag(section)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
            }
        )

        let window = UIWindow(windowScene: windowScene)
        window.frame = windowScene.coordinateSpace.bounds
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        for _ in 0..<25 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            hostingController.view.layoutIfNeeded()
            window.updateFocusIfNeeded()
            let cardFrames = collectCardWindowFrames(in: hostingController.view, window: window)
            if cardFrames.count >= 2 && viewModel.serverCards.count == 1 {
                break
            }
        }

        let cardFrames = collectCardWindowFrames(in: hostingController.view, window: window)
        #expect(cardFrames.count >= 2)
        for cardFrame in cardFrames {
            #expect(cardFrame.minY < window.bounds.height * 0.32)
        }
    }

    @MainActor
    private func collectCardWindowFrames(in rootView: UIView, window: UIWindow) -> [CGRect] {
        let items = collectFocusableItems(in: rootView, bounds: window.bounds)
        var frames: [CGRect] = []
        for item in items {
            let windowRect: CGRect
            if let coordinateSpace = item.parentFocusEnvironment?.focusItemContainer?.coordinateSpace {
                windowRect = window.convert(item.frame, from: coordinateSpace)
            } else if let view = item as? UIView {
                windowRect = window.convert(view.bounds, from: view)
            } else {
                windowRect = item.frame
            }
            if windowRect.width >= 260 && windowRect.height >= 180 {
                frames.append(windowRect)
            }
        }
        return frames
    }

    @MainActor
    private func collectFocusableItems(in environment: any UIFocusEnvironment, bounds: CGRect) -> [any UIFocusItem] {
        var collected: [any UIFocusItem] = []
        var visitedIDs: Set<ObjectIdentifier> = []

        func visit(_ env: any UIFocusEnvironment) {
            if let obj = env as AnyObject? {
                let id = ObjectIdentifier(obj)
                if visitedIDs.contains(id) {
                    return
                }
                visitedIDs.insert(id)
            }

            if let item = env as? any UIFocusItem, item.canBecomeFocused {
                collected.append(item)
            }

            if let container = env as? any UIFocusItemContainer {
                let items = container.focusItems(in: bounds)
                for child in items {
                    visit(child)
                }
            } else if let view = env as? UIView {
                for item in view.focusItems(in: bounds) {
                    visit(item)
                }
                for subview in view.subviews {
                    visit(subview)
                }
            }
        }

        visit(environment)
        return collected
    }

    @MainActor
    private func collectFocusItemFrames(in rootView: UIView, window: UIWindow) -> [CGRect] {
        collectFocusableItems(in: rootView, bounds: window.bounds).map { item in
            windowFrame(of: item, window: window)
        }
    }

    @MainActor
    private func windowFrame(of item: any UIFocusItem, window: UIWindow) -> CGRect {
        if let coordinateSpace = item.parentFocusEnvironment?.focusItemContainer?.coordinateSpace {
            return window.convert(item.frame, from: coordinateSpace)
        } else if let view = item as? UIView {
            return window.convert(view.bounds, from: view)
        }
        return item.frame
    }

    @MainActor
    private func collectBottomFocusContainerFrames(in rootView: UIView, window: UIWindow) -> [CGRect] {
        var rects: [CGRect] = []
        var visitedIDs: Set<ObjectIdentifier> = []

        func visit(_ env: any UIFocusEnvironment) {
            if let obj = env as AnyObject? {
                let id = ObjectIdentifier(obj)
                if !visitedIDs.insert(id).inserted {
                    return
                }
            }

            if let guide = env as? UIFocusGuide, guide.isEnabled, let owningView = guide.owningView {
                rects.append(window.convert(guide.layoutFrame, from: owningView))
            }

            if let view = env as? UIView {
                for guide in view.layoutGuides {
                    if let focusGuide = guide as? UIFocusGuide, focusGuide.isEnabled {
                        rects.append(window.convert(focusGuide.layoutFrame, from: view))
                    }
                }
                for child in view.focusItems(in: window.bounds) {
                    if !child.canBecomeFocused {
                        rects.append(windowFrame(of: child, window: window))
                    }
                    visit(child)
                }
                for subview in view.subviews {
                    visit(subview)
                }
            } else if let container = env as? any UIFocusItemContainer {
                for child in container.focusItems(in: window.bounds) {
                    if !child.canBecomeFocused {
                        rects.append(windowFrame(of: child, window: window))
                    }
                    visit(child)
                }
            }
        }

        visit(rootView)
        return rects
    }
}
