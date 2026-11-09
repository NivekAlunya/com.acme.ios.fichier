//
//  MockRemoteUIPress.swift
//  FichierTVTests
//
//

import UIKit

@MainActor
final class MockRemoteUIPress: UIPress {
    private let stubType: UIPress.PressType
    private let stubTimestamp: TimeInterval

    init(type: UIPress.PressType, timestamp: TimeInterval) {
        self.stubType = type
        self.stubTimestamp = timestamp
        super.init()
    }

    override var type: UIPress.PressType {
        stubType
    }

    override var timestamp: TimeInterval {
        stubTimestamp
    }
}
