//
//  PictureEXIFBox.swift
//  fichier
//

import Foundation

nonisolated public final class PictureEXIFBox: NSObject, Sendable {
    public let value: PictureEXIFData
    
    public init(_ value: PictureEXIFData) {
        self.value = value
        super.init()
    }
}
