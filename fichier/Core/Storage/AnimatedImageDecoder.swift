//
//  AnimatedImageDecoder.swift
//  fichier
//

import UIKit
import ImageIO

nonisolated public enum AnimatedImageDecoder: Sendable {
    nonisolated public static func decode(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        
        let count = CGImageSourceGetCount(source)
        guard count > 1 else {
            if let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                return UIImage(cgImage: cgImage)
            }
            return UIImage(data: data)
        }
        
        var images: [UIImage] = []
        var totalDuration: Double = 0
        
        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            
            let frameDuration = getFrameDuration(from: source, at: i)
            totalDuration += frameDuration
            images.append(UIImage(cgImage: cgImage))
        }
        
        if totalDuration <= 0 {
            totalDuration = Double(count) * 0.1
        }
        
        return UIImage.animatedImage(with: images, duration: totalDuration) ?? UIImage(data: data)
    }
    
    nonisolated private static func getFrameDuration(from source: CGImageSource, at index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return 0.1
        }
        
        // GIF Frame Delay
        if let gifDict = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            if let unclamped = gifDict[kCGImagePropertyGIFUnclampedDelayTime] as? Double, unclamped > 0 {
                return unclamped
            }
            if let delay = gifDict[kCGImagePropertyGIFDelayTime] as? Double, delay > 0 {
                return delay
            }
        }
        
        // WebP Frame Delay
        if let webpDict = properties[kCGImagePropertyWebPDictionary] as? [CFString: Any] {
            if let unclamped = webpDict[kCGImagePropertyWebPUnclampedDelayTime] as? Double, unclamped > 0 {
                return unclamped
            }
            if let delay = webpDict[kCGImagePropertyWebPDelayTime] as? Double, delay > 0 {
                return delay
            }
        }
        
        return 0.1
    }
}
