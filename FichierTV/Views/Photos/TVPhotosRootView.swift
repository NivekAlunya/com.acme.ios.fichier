//
//  TVPhotosRootView.swift
//  FichierTV
//

import SwiftUI
import FichierKit

/// Entry view for Photos, managing authorization states and displaying albums in a 4-column grid.
public struct TVPhotosRootView: View {
    @State private var authorizationStatus: PhotosAuthorizationStatus = .notDetermined
    private let source = PhotosMediaSource()

    public init() {}

    public var body: some View {
        Group {
            switch authorizationStatus {
            case .notDetermined:
                permissionRequestView
            case .denied, .restricted:
                permissionDeniedView
            case .limited:
                limitedAccessView
            case .authorized:
                TVMediaBrowserView(source: source, folder: nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            authorizationStatus = source.authorizationStatus
        }
    }

    // MARK: - Authorization Subviews

    @ViewBuilder
    private var permissionRequestView: some View {
        VStack(spacing: 36) {
            Image(systemName: "photo.badge.plus")
                .font(.system(.largeTitle))
                .imageScale(.large)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("Photos Access Required")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Fichier requires access to display your photo and video library.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Grant Access") {
                Task {
                    authorizationStatus = await source.requestAuthorization()
                }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Grant access to Photos")
        }
        .focusSection()
    }

    @ViewBuilder
    private var permissionDeniedView: some View {
        VStack(spacing: 36) {
            Image(systemName: "hand.raised.slash.fill")
                .font(.system(.largeTitle))
                .imageScale(.large)
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("Photos Access Denied")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Access to Photos is disabled. Please enable it in Apple TV Settings > Apps > Fichier.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)
            }
        }
        .focusSection()
    }

    @ViewBuilder
    private var limitedAccessView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                Text("Limited Access: Showing only photos and albums selected in system permissions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 20)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 16)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Limited Access: Showing only photos and albums selected in system permissions.")

            TVMediaBrowserView(source: source, folder: nil)
        }
    }
}
