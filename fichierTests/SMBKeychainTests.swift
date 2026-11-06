//
//  SMBKeychainTests.swift
//  fichierTests
//

#if DEBUG && canImport(XCTest)
import XCTest
@testable import fichier

final class SMBKeychainTests: XCTestCase {
    
    func testSaveLoadAndDeletePassword() async {
        let account = "test-user@test-host"
        let password = "test-password-123"
        
        let saved = await SMBKeychain.savePassword(password, for: account)
        XCTAssertTrue(saved)
        
        let loaded = await SMBKeychain.loadPassword(for: account)
        XCTAssertEqual(loaded, password)
        
        await SMBKeychain.deletePassword(for: account)
        let afterDelete = await SMBKeychain.loadPassword(for: account)
        XCTAssertNil(afterDelete)
    }

    func testSavingExistingAccountUpdatesPassword() async {
        let account = "update-user-\(UUID().uuidString)@host.local"

        let firstSaveSucceeded = await SMBKeychain.savePassword("initial-password", for: account)
        XCTAssertTrue(firstSaveSucceeded)

        let secondSaveSucceeded = await SMBKeychain.savePassword("updated-password", for: account)
        XCTAssertTrue(secondSaveSucceeded)

        let loadedPassword = await SMBKeychain.loadPassword(for: account)
        XCTAssertEqual(loadedPassword, "updated-password")

        await SMBKeychain.deletePassword(for: account)
    }

    func testConcurrentAccessAcrossMultipleTasks() async {
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<25 {
                group.addTask {
                    let account = "concurrent-user-\(index)@host.local"
                    let password = "pass-\(index)"
                    
                    _ = await SMBKeychain.savePassword(password, for: account)
                    let loaded = await SMBKeychain.loadPassword(for: account)
                    XCTAssertEqual(loaded, password)
                    await SMBKeychain.deletePassword(for: account)
                    let afterDelete = await SMBKeychain.loadPassword(for: account)
                    XCTAssertNil(afterDelete)
                }
            }
        }
    }
}
#endif
