//
//  TVVideoTestFixtureGenerator.swift
//  FichierTVTests
//

import Foundation
import AVFoundation
import CoreVideo

/// Synthesizes minimal valid `.mp4` test fixtures for host-app video thumbnail verification.
enum TVVideoTestFixtureGenerator {
    static func createSampleMP4File(width: Int = 192, height: Int = 108) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fichiertv_test_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let pixelAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: pixelAttributes
        )

        guard writer.canAdd(input) else {
            throw NSError(domain: "TVVideoTestFixtureGenerator", code: 1)
        }
        writer.add(input)

        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "TVVideoTestFixtureGenerator", code: 2)
        }
        writer.startSession(atSourceTime: .zero)

        let timestamps = [
            CMTime(value: 0, timescale: 30),
            CMTime(value: 15, timescale: 30),
            CMTime(value: 30, timescale: 30)
        ]

        for timestamp in timestamps {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            guard let pool = adaptor.pixelBufferPool else {
                throw NSError(domain: "TVVideoTestFixtureGenerator", code: 3)
            }
            var bufferOut: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &bufferOut)
            guard status == kCVReturnSuccess, let buffer = bufferOut else {
                throw NSError(domain: "TVVideoTestFixtureGenerator", code: 4)
            }

            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
                memset(base, 0x5A, bytesPerRow * height)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: timestamp)
        }

        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            throw writer.error ?? NSError(domain: "TVVideoTestFixtureGenerator", code: 5)
        }

        return outputURL
    }
}
