//
//  PhotoLibrarySaver.swift
//  fichier
//

import UIKit
import Photos

@MainActor
public enum PhotoLibrarySaver {
    private static func ensureAuthorization() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw CocoaError(.fileWriteNoPermission)
        }
    }
    
    public static func saveImageToPhotos(_ image: UIImage) async throws {
        try await ensureAuthorization()
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }
    
    public static func saveVideoToPhotos(at fileURL: URL) async throws {
        try await ensureAuthorization()
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
        }
    }
}
