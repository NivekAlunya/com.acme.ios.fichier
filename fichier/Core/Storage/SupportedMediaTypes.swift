//
//  SupportedMediaTypes.swift
//  fichier
//

import Foundation

/// Centralized file extension registry and MIME type classification utility.
///
/// Categorizes local and remote file paths into images, videos, and PDF documents, supporting standard formats,
/// animated image formats (GIF/APNG/WebP), and DSLR/mirrorless RAW files.
nonisolated public enum SupportedMediaTypes: Sendable {
    
    /// Set of recognized raster, vector, animated, and camera RAW image file extensions (lowercase).
    public static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "jif", "jfif",
        "png", "heic", "heif", "webp", "avif",
        "gif", "tiff", "tif", "bmp", "ico",
        "jp2", "j2k", "jpf", "jpx",
        "cr2", "cr3", "nef", "arw", "dng", "orf", "rw2", "pef", "raf"
    ]
    
    /// Set of recognized video file extensions supported by AVFoundation hardware acceleration.
    public static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v"
    ]
    
    /// Set of recognized document extensions rendered via PDFKit.
    public static let documentExtensions: Set<String> = [
        "pdf"
    ]
    
    /// Unified union set of all supported media file extensions.
    public static let allExtensions: Set<String> = imageExtensions.union(videoExtensions).union(documentExtensions)
    
    /// Checks whether the given extension belongs to any supported media category.
    ///
    /// - Parameter ext: The file extension string (case-insensitive).
    /// - Returns: `true` if supported; `false` otherwise.
    public static func isSupported(extension ext: String) -> Bool {
        allExtensions.contains(ext.lowercased())
    }
    
    /// Determines whether the file extension corresponds to a video format.
    public static func isVideo(extension ext: String) -> Bool {
        videoExtensions.contains(ext.lowercased())
    }
    
    /// Determines whether the file extension corresponds to an image format.
    public static func isImage(extension ext: String) -> Bool {
        imageExtensions.contains(ext.lowercased())
    }
    
    /// Determines whether the file extension corresponds to a document format (PDF).
    public static func isDocument(extension ext: String) -> Bool {
        documentExtensions.contains(ext.lowercased())
    }
    
    /// Checks if the extension strictly represents a PDF document.
    public static func isPDF(extension ext: String) -> Bool {
        ext.lowercased() == "pdf"
    }
    
    /// Checks if the extension strictly represents an animated or static GIF.
    public static func isGIF(extension ext: String) -> Bool {
        ext.lowercased() == "gif"
    }
}
