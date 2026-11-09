//
//  StubSMBConnectionValidator.swift
//  FichierTVTests
//
//

import Foundation
import FichierKit

struct StubSMBConnectionValidator: SMBConnectionValidatorProtocol {
    let result: Result<[String], SMBError>

    init(shares: [String] = ["Media"]) {
        self.result = .success(shares)
    }

    init(error: SMBError) {
        self.result = .failure(error)
    }

    func validateAndListShares(for server: SavedSMBConnection, password: String) async throws -> [String] {
        switch result {
        case .success(let shares):
            if shares.isEmpty {
                throw SMBError.noShares
            }
            return shares
        case .failure(let error):
            throw error
        }
    }
}
