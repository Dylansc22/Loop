//
//  GridPreviewView.swift
//  Loop
//
//  Created by Codex on 2026-02-13.
//

import SwiftUI

struct GridPreviewView: View {
    @Environment(\.luminareAnimationFast) private var luminareAnimationFast

    let columns: Int
    let rows: Int

    @State private var selectedCells: Set<GridCell> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScreenView {
                GeometryReader { geometry in
                    let safeColumns = Swift.max(columns, 1)
                    let safeRows = Swift.max(rows, 1)
                    let rowIndices = Array(0..<safeRows)
                    let columnIndices = Array(0..<safeColumns)
                    let cellWidth = geometry.size.width / CGFloat(safeColumns)
                    let cellHeight = geometry.size.height / CGFloat(safeRows)

                    ZStack(alignment: .topLeading) {
                        ForEach(rowIndices, id: \.self) { row in
                            ForEach(columnIndices, id: \.self) { column in
                                let cell = GridCell(row: row, column: column)
                                let isSelected = selectedCells.contains(cell)

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isSelected ? .tint.opacity(0.35) : .white.opacity(0.06))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(.white.opacity(0.25), lineWidth: 1)
                                    }
                                    .frame(width: cellWidth, height: cellHeight)
                                    .offset(x: CGFloat(column) * cellWidth, y: CGFloat(row) * cellHeight)
                                    .onTapGesture {
                                        if isSelected {
                                            selectedCells.remove(cell)
                                        } else {
                                            selectedCells.insert(cell)
                                        }
                                    }
                            }
                        }
                    }
                    .animation(luminareAnimationFast, value: selectedCells)
                }
            }
            .frame(height: 140)

            Text("Click cells to preview multi-cell selection")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
