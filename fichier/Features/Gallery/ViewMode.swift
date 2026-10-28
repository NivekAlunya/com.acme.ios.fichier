//
//  ViewMode.swift
//  fichier
//

import Foundation

enum ViewMode: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case grid = "Grid"
    case list = "List"
}
