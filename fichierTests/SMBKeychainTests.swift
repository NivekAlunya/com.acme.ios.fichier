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
