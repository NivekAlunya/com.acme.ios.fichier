//
//  SMBPasswordStoreTests.swift
//  fichierTests
//

#if DEBUG
import Foundation
import Testing
import FichierKit
@testable import fichier

@Suite("SMBPasswordStore Tests")
struct SMBPasswordStoreTests {

    @Test("Save, load, and delete password")
    func saveLoadAndDeletePassword() async {
        let store = SMBPasswordStore(service: "com.acme.ios.fichier.tests.\(UUID().uuidString)")
        let account = "test-user@test-host"
        let password = "test-password-123"

        await store.savePassword(password, for: account)
        let loaded = await store.loadPassword(for: account)
        #expect(loaded == password)

        await store.deletePassword(for: account)
        let afterDelete = await store.loadPassword(for: account)
        #expect(afterDelete == nil)
    }

    @Test("Saving existing account updates password")
    func savingExistingAccountUpdatesPassword() async {
        let store = SMBPasswordStore(service: "com.acme.ios.fichier.tests.\(UUID().uuidString)")
        let account = "update-user-\(UUID().uuidString)@host.local"

        await store.savePassword("initial-password", for: account)
        await store.savePassword("updated-password", for: account)

        let loadedPassword = await store.loadPassword(for: account)
        #expect(loadedPassword == "updated-password")

        await store.deletePassword(for: account)
    }

    @Test("Concurrent access across multiple tasks")
    func concurrentAccessAcrossMultipleTasks() async {
        let store = SMBPasswordStore(service: "com.acme.ios.fichier.tests.\(UUID().uuidString)")

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<25 {
                group.addTask {
                    let account = "concurrent-user-\(index)@host.local"
                    let password = "pass-\(index)"

                    await store.savePassword(password, for: account)
                    let loaded = await store.loadPassword(for: account)
                    #expect(loaded == password)
                    await store.deletePassword(for: account)
                    let afterDelete = await store.loadPassword(for: account)
                    #expect(afterDelete == nil)
                }
            }
        }
    }
}
#endif
