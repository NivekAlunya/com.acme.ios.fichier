//
//  SupportedMediaTypes.swift
//  fichier
//

import Foundation
import UniformTypeIdentifiers

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
    
    /// Set of recognized native video file extensions supported by AVFoundation hardware acceleration.
    public static let nativeVideoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "3gp"
    ]
    
    /// Set of extended video container and codec extensions decoded via extended hardware/FFmpeg engine.
    public static let extendedVideoExtensions: Set<String> = [
        "mkv", "avi", "webm", "flv", "f4v", "wmv", "asf",
        "ts", "m2ts", "mts", "m2v", "mpg", "mpeg", "vob",
        "ogv", "rm", "mxf", "wtv", "hevc", "mjpeg"
    ]
    
    /// Unified union set of all recognized video file extensions.
    public static let videoExtensions: Set<String> = nativeVideoExtensions.union(extendedVideoExtensions)
    
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
    
    /// Checks whether the file extension corresponds to an Apple-native AVFoundation video format.
    public static func isNativeVideo(extension ext: String) -> Bool {
        nativeVideoExtensions.contains(ext.lowercased())
    }
    
    /// Checks whether the file extension corresponds to an extended video format requiring non-native demuxing/decoding.
    public static func isExtendedVideo(extension ext: String) -> Bool {
        extendedVideoExtensions.contains(ext.lowercased())
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
    
    /// Resolves the appropriate MIME content-type string for a given file extension.
    ///
    /// - Parameter ext: The file extension string (e.g. "mkv", "avi", "webm").
    /// - Returns: A standard MIME type string (e.g. "video/x-matroska", "video/webm").
    public static func mimeType(for ext: String) -> String {
        let normalized = ext.trimmingCharacters(in: .punctuationCharacters).lowercased()
        switch normalized {
        case "mkv":
            return "video/x-matroska"
        case "webm":
            return "video/webm"
        case "avi":
            return "video/x-msvideo"
        case "mp4":
            return "video/mp4"
        case "mov":
            return "video/quicktime"
        case "m4v":
            return "video/x-m4v"
        case "3gp":
            return "video/3gpp"
        case "flv", "f4v":
            return "video/x-flv"
        case "wmv", "asf":
            return "video/x-ms-wmv"
        case "ts", "m2ts", "mts":
            return "video/mp2t"
        case "mpg", "mpeg", "m2v", "vob":
            return "video/mpeg"
        case "ogv":
            return "video/ogg"
        case "rm":
            return "application/vnd.rn-realmedia"
        case "mxf":
            return "application/mxf"
        case "pdf":
            return "application/pdf"
        default:
            if let utType = UTType(filenameExtension: normalized), let mime = utType.preferredMIMEType {
                return mime
            }
            return "video/x-matroska"
        }
    }
}
