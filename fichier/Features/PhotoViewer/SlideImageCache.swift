//
//  SlideImageCache.swift
//  fichier
//
//

import UIKit

/// Bounded in-memory image cache with cost-based eviction to prevent OOM crashes during photo browsing.
public final class SlideImageCache: @unchecked Sendable {
    private let storage: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 16
        cache.totalCostLimit = 120 * 1024 * 1024 // 120 MB maximum
        return cache
    }()

    public init() {}

    public subscript(id: String) -> UIImage? {
        get {
            storage.object(forKey: id as NSString)
        }
        set {
            if let newValue {
                let cost = Int(newValue.size.width * newValue.size.height * 4)
                storage.setObject(newValue, forKey: id as NSString, cost: cost)
            } else {
                storage.removeObject(forKey: id as NSString)
            }
        }
    }

    public func removeAll() {
        storage.removeAllObjects()
    }
}
