//
//  GridOverlayViewModel.swift
//  Loop
//
//  Created by Codex on 2026-02-13.
//

import Defaults
import SwiftUI

@MainActor
final class GridOverlayViewModel: ObservableObject {
    @Published private(set) var gridConfiguration: GridConfiguration = .fromDefaults()
    @Published private(set) var highlightedCells: Set<GridCell> = []
    @Published private(set) var isShown: Bool = false
    @Published private(set) var isDragging: Bool = false
    @Published private(set) var gridBounds: CGRect = .zero
    @Published private(set) var displayBounds: CGRect = .zero

    func setIsShown(_ shown: Bool) {
        withAnimation(Defaults[.animationConfiguration].previewWindow) {
            isShown = shown
        }
    }

    func updateContext(with context: ResizeContext) {
        gridConfiguration = context.gridConfiguration ?? .fromDefaults()
        highlightedCells = context.selectedCells
        isDragging = context.isGridDragging
        gridBounds = context.gridInteractionBounds
        displayBounds = context.screen?.displayBounds ?? context.gridInteractionBounds

        if !isShown {
            setIsShown(true)
        }
    }
}
