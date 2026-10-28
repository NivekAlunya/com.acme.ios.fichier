//
//  ImageMetadataExtractor.swift
//  fichier
//

import Foundation
import CoreGraphics
import ImageIO

nonisolated public enum ImageMetadataExtractor {
    public static func extract(from data: Data, fileName: String, fileSize: String) -> PictureEXIFData {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return PictureEXIFData(
                fileName: fileName,
                fileSize: fileSize,
                dimensions: nil,
                megapixels: nil,
                cameraModel: nil,
                lensModel: nil,
                focalLength: nil,
                aperture: nil,
                shutterSpeed: nil,
                iso: nil,
                dateTaken: nil,
                fileFormat: (fileName as NSString).pathExtension.uppercased()
            )
        }
        
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        
        // Dimensions & Megapixels
        var dimString: String?
        var megaPixelsString: String?
        let width = props[kCGImagePropertyPixelWidth] as? Int ?? exif?[kCGImagePropertyExifPixelXDimension] as? Int
        let height = props[kCGImagePropertyPixelHeight] as? Int ?? exif?[kCGImagePropertyExifPixelYDimension] as? Int
        
        if let w = width, let h = height {
            dimString = "\(w) × \(h)"
            let mp = Double(w * h) / 1_000_000.0
            megaPixelsString = String(format: "%.1f MP", mp)
        }
        
        // Camera & Lens
        let make = tiff?[kCGImagePropertyTIFFMake] as? String
        let model = tiff?[kCGImagePropertyTIFFModel] as? String
        var camera: String?
        if let model {
            if let make, !model.localizedCaseInsensitiveContains(make) {
                camera = "\(make) \(model)"
            } else {
                camera = model
            }
        }
        
        let lens = exif?[kCGImagePropertyExifLensModel] as? String
        
        // Exposure: Aperture, Shutter, ISO, Focal
        var apertureStr: String?
        if let fNumber = exif?[kCGImagePropertyExifFNumber] as? Double {
            apertureStr = String(format: "ƒ/%.1f", fNumber)
        }
        
        var shutterStr: String?
        if let expTime = exif?[kCGImagePropertyExifExposureTime] as? Double {
            if expTime >= 1.0 {
                shutterStr = String(format: "%.1fs", expTime)
            } else if expTime > 0 {
                let denom = Int(round(1.0 / expTime))
                shutterStr = "1/\(denom)s"
            }
        }
        
        var isoStr: String?
        if let isoArray = exif?[kCGImagePropertyExifISOSpeedRatings] as? [Int], let first = isoArray.first {
            isoStr = "ISO \(first)"
        }
        
        var focalStr: String?
        if let fl = exif?[kCGImagePropertyExifFocalLength] as? Double {
            focalStr = String(format: "%.0f mm", fl)
        }
        
        // Date
        let dateTaken = exif?[kCGImagePropertyExifDateTimeOriginal] as? String ?? tiff?[kCGImagePropertyTIFFDateTime] as? String
        
        return PictureEXIFData(
            fileName: fileName,
            fileSize: fileSize,
            dimensions: dimString,
            megapixels: megaPixelsString,
            cameraModel: camera,
            lensModel: lens,
            focalLength: focalStr,
            aperture: apertureStr,
            shutterSpeed: shutterStr,
            iso: isoStr,
            dateTaken: dateTaken,
            fileFormat: (fileName as NSString).pathExtension.uppercased()
        )
    }
}
