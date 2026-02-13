//
//  GridSelection.swift
//  Loop
//
//  Created by Codex on 2026-02-13.
//

import CoreGraphics

struct GridSelection {
    var startCell: GridCell?
    var currentCells: Set<GridCell> = []
    var boundingFrame: CGRect = .zero

    mutating func reset() {
        startCell = nil
        currentCells = []
        boundingFrame = .zero
    }
}
