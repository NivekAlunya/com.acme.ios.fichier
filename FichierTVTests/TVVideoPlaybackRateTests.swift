//
//  TVVideoPlaybackRateTests.swift
//  FichierTVTests
//

import Foundation
import Testing
@testable import FichierTV

@Suite("TVVideoPlaybackRate Tests")
struct TVVideoPlaybackRateTests {

    @Test("Verify raw Float rate multiplier conversions")
    func rawMultiplierValues() {
        #expect(TVVideoPlaybackRate.speed0_5.rawValue == 0.5)
        #expect(TVVideoPlaybackRate.speed0_75.rawValue == 0.75)
        #expect(TVVideoPlaybackRate.normal.rawValue == 1.0)
        #expect(TVVideoPlaybackRate.speed1_25.rawValue == 1.25)
        #expect(TVVideoPlaybackRate.speed1_5.rawValue == 1.5)
        #expect(TVVideoPlaybackRate.speed2_0.rawValue == 2.0)
    }

    @Test("Verify user-facing display titles")
    func displayTitles() {
        #expect(TVVideoPlaybackRate.speed0_5.displayName == "0.5×")
        #expect(TVVideoPlaybackRate.speed0_75.displayName == "0.75×")
        #expect(TVVideoPlaybackRate.normal.displayName == "1.0×")
        #expect(TVVideoPlaybackRate.speed1_25.displayName == "1.25×")
        #expect(TVVideoPlaybackRate.speed1_5.displayName == "1.5×")
        #expect(TVVideoPlaybackRate.speed2_0.displayName == "2.0×")
    }

    @Test("Verify ID conformance matches raw value")
    func idConformance() {
        for rate in TVVideoPlaybackRate.allCases {
            #expect(rate.id == rate.rawValue)
        }
    }
}
