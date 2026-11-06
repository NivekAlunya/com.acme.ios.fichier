//
//  VideoThumbnailLimiterTests.swift
//  fichier
//

#if DEBUG && canImport(XCTest)
import XCTest
@testable import fichier

final class VideoThumbnailLimiterTests: XCTestCase {
    func testPermitAcquisitionAndRelease() async throws {
        let limiter = VideoThumbnailLimiter(maxConcurrent: 1)
        let result = try await limiter.withPermit {
            100
        }
        XCTAssertEqual(result, 100)
    }
    
    func testReleasesPermitOnTaskCancellationWhileQueued() async {
        let limiter = VideoThumbnailLimiter(maxConcurrent: 1)
        
        let acquired = expectation(description: "Task 1 acquired permit")
        let task1 = Task {
            try await limiter.withPermit {
                acquired.fulfill()
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        
        await fulfillment(of: [acquired], timeout: 2.0)
        
        // Task 2 attempts to acquire permit while capacity is full
        let task2 = Task {
            try await limiter.withPermit {
                XCTFail("Task 2 should not execute body when cancelled")
            }
        }
        
        // Allow Task 2 to queue in waiters
        try? await Task.sleep(nanoseconds: 50_000_000)
        task2.cancel()
        
        do {
            _ = try await task2.value
            XCTFail("Expected CancellationError from Task 2")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        
        // Cancel Task 1 to free the limiter
        task1.cancel()
        _ = try? await task1.value
        
        // Task 3 verifies permits are not leaked and can be acquired immediately
        let completed = try? await limiter.withPermit {
            true
        }
        XCTAssertEqual(completed, true)
    }
    
    func testPreCancelledTaskThrowsCancellationError() async {
        let limiter = VideoThumbnailLimiter(maxConcurrent: 1)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await limiter.withPermit {
                XCTFail("Should not execute")
            }
        }
        task.cancel()
        
        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}
#endif
