//
//  GridSizeTypographyTests.swift
//  fichierTests
//
//

import Foundation
import Testing
@testable import Fichier

@Suite("GridSizeTypography")
@MainActor
struct GridSizeTypographyTests {
    
    @Test("Typography strictly satisfies: font small < font medium < font large")
    func gridFontSizesAscending() {
        let smallTitle = GridSize.compact.titleFontSize
        let mediumTitle = GridSize.medium.titleFontSize
        let largeTitle = GridSize.large.titleFontSize
        
        #expect(smallTitle < mediumTitle)
        #expect(mediumTitle < largeTitle)
        
        let smallDetail = GridSize.compact.detailFontSize
        let mediumDetail = GridSize.medium.detailFontSize
        let largeDetail = GridSize.large.detailFontSize
        
        #expect(smallDetail < mediumDetail)
        #expect(mediumDetail < largeDetail)
    }
    
    @Test("List mode uses the exact same typography as grid large")
    func listModeMatchesGridLarge() {
        let listTitleFontSize = GridSize.large.titleFontSize
        let listDetailFontSize = GridSize.large.detailFontSize
        
        #expect(listTitleFontSize == GridSize.large.titleFontSize)
        #expect(listDetailFontSize == GridSize.large.detailFontSize)
        
        #expect(GridSize.compact.titleFontSize < GridSize.medium.titleFontSize)
        #expect(GridSize.medium.titleFontSize < listTitleFontSize)
        
        #expect(GridSize.compact.detailFontSize < GridSize.medium.detailFontSize)
        #expect(GridSize.medium.detailFontSize < listDetailFontSize)
    }
    
    @Test("Pictogram badge and icon sizes scale across grid densities")
    func pictogramBadgeScaling() {
        #expect(GridSize.compact.pictogramBadgeSize < GridSize.medium.pictogramBadgeSize)
        #expect(GridSize.medium.pictogramBadgeSize < GridSize.large.pictogramBadgeSize)
        
        #expect(GridSize.compact.pictogramIconSize < GridSize.medium.pictogramIconSize)
        #expect(GridSize.medium.pictogramIconSize < GridSize.large.pictogramIconSize)
    }
}
