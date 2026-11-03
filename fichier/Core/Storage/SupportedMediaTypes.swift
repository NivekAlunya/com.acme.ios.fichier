//
//  SupportedMediaTypes.swift
//  fichier
//

import Foundation

nonisolated public enum SupportedMediaTypes: Sendable {
    public static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "jif", "jfif",
        "png", "heic", "heif", "webp", "avif",
        "gif", "tiff", "tif", "bmp", "ico",
        "jp2", "j2k", "jpf", "jpx",
        "cr2", "cr3", "nef", "arw", "dng", "orf", "rw2", "pef", "raf"
    ]
    
    public static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v"
    ]
    
    public static let documentExtensions: Set<String> = [
        "pdf"
    ]
    
    public static let allExtensions: Set<String> = imageExtensions.union(videoExtensions).union(documentExtensions)
    
    public static func isSupported(extension ext: String) -> Bool {
        allExtensions.contains(ext.lowercased())
    }
    
    public static func isVideo(extension ext: String) -> Bool {
        videoExtensions.contains(ext.lowercased())
    }
    
    public static func isImage(extension ext: String) -> Bool {
        imageExtensions.contains(ext.lowercased())
    }
    
    public static func isDocument(extension ext: String) -> Bool {
        documentExtensions.contains(ext.lowercased())
    }
    
    public static func isPDF(extension ext: String) -> Bool {
        ext.lowercased() == "pdf"
    }
    
    public static func isGIF(extension ext: String) -> Bool {
        ext.lowercased() == "gif"
    }
}
