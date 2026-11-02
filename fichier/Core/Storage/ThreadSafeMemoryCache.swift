//
//  ThreadSafeMemoryCache.swift
//  fichier
//

import Foundation

/// A thread-safe, `@unchecked Sendable` generic in-memory cache wrapper around Apple's `NSCache`.
///
/// Apple's `NSCache` is inherently thread-safe according to official documentation:
/// "You can add, remove, and query items in the cache from different threads without having to lock the cache yourself."
/// However, because `NSCache` is an Objective-C class not explicitly annotated as `Sendable` in the Swift SDK overlay,
/// this wrapper satisfies Swift 6 strict concurrency checks without resorting to `nonisolated(unsafe)`.
nonisolated public final class ThreadSafeMemoryCache<Key: AnyObject, Value: AnyObject>: @unchecked Sendable {
    private let cache = NSCache<Key, Value>()
    
    public init(countLimit: Int = 0, totalCostLimit: Int = 0) {
        if countLimit > 0 {
            cache.countLimit = countLimit
        }
        if totalCostLimit > 0 {
            cache.totalCostLimit = totalCostLimit
        }
    }
    
    /// Retrieves a cached value for the specified key.
    public func object(forKey key: Key) -> Value? {
        cache.object(forKey: key)
    }
    
    /// Caches a value for the specified key.
    public func setObject(_ obj: Value, forKey key: Key) {
        cache.setObject(obj, forKey: key)
    }
    
    /// Caches a value for the specified key with an associated cost.
    public func setObject(_ obj: Value, forKey key: Key, cost: Int) {
        cache.setObject(obj, forKey: key, cost: cost)
    }
    
    /// Removes a cached value for the specified key.
    public func removeObject(forKey key: Key) {
        cache.removeObject(forKey: key)
    }
    
    /// Clears all objects from the cache.
    public func removeAllObjects() {
        cache.removeAllObjects()
    }
}
