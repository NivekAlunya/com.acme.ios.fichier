//
//  PictureEXIFData.swift
//  fichier
//

import Foundation

nonisolated public struct PictureEXIFData: Identifiable, Sendable {
    public var id: String { fileName }
    public let fileName: String
    public let fileSize: String
    public let dimensions: String?
    public let megapixels: String?
    public let cameraModel: String?
    public let lensModel: String?
    public let focalLength: String?
    public let aperture: String?
    public let shutterSpeed: String?
    public let iso: String?
    public let dateTaken: String?
    public let fileFormat: String?
}
