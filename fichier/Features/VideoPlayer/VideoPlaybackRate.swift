//
//  VideoPlaybackRate.swift
//  fichier
//

import Foundation

public enum VideoPlaybackRate: Float, CaseIterable, Identifiable, Sendable {
    case speed0_5 = 0.5
    case speed0_75 = 0.75
    case normal = 1.0
    case speed1_25 = 1.25
    case speed1_5 = 1.5
    case speed2_0 = 2.0
    
    public var id: Float { rawValue }
    
    public var displayName: String {
        switch self {
        case .speed0_5:
            return "0.5×"
        case .speed0_75:
            return "0.75×"
        case .normal:
            return "1.0×"
        case .speed1_25:
            return "1.25×"
        case .speed1_5:
            return "1.5×"
        case .speed2_0:
            return "2.0×"
        }
    }
}
