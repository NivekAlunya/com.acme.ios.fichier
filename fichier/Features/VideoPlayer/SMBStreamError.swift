//
//  SMBStreamError.swift
//  fichier
//

import Foundation

/// Specific error conditions encountered during progressive SMB media streaming via `SMBResourceLoaderDelegate`.
public enum SMBStreamError: LocalizedError, Sendable {
    /// An unexpected empty chunk (EOF) was encountered before the requested byte range was fulfilled.
    case unexpectedEndOfFile(expectedOffset: Int64, actualOffset: Int64)
    
    /// Fewer bytes were retrieved from the SMB network connection than requested by AVFoundation.
    case incompleteData(expectedOffset: Int64, actualOffset: Int64)
    
    /// The remote media item has an unknown or zero byte size and cannot be streamed.
    case unknownContentLength
    
    public var errorDescription: String? {
        switch self {
        case .unexpectedEndOfFile(let expected, let actual):
            return "Unexpected end of file while streaming SMB range (expected up to offset \(expected), reached \(actual))."
        case .incompleteData(let expected, let actual):
            return "Incomplete SMB data stream delivered (expected up to offset \(expected), received \(actual))."
        case .unknownContentLength:
            return "Cannot stream SMB media with unknown or non-positive content length."
        }
    }
}
