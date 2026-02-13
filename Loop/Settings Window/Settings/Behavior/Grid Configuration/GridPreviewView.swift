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
    let showGridLines: Bool

    @State private var selectedCells: Set<GridCell> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScreenView(containerContentMode: .fit, backgroundContentMode: .fit) {
                GeometryReader { geometry in
                    let safeColumns = Swift.max(columns, 1)
                    let safeRows = Swift.max(rows, 1)
                    let cellSpacing: CGFloat = 4
                    let horizontalSpacing = CGFloat(safeColumns - 1) * cellSpacing
                    let verticalSpacing = CGFloat(safeRows - 1) * cellSpacing
                    let cellWidth = Swift.max((geometry.size.width - horizontalSpacing) / CGFloat(safeColumns), 0)
                    let cellHeight = Swift.max((geometry.size.height - verticalSpacing) / CGFloat(safeRows), 0)

                    VStack(alignment: .leading, spacing: cellSpacing) {
                        ForEach(0..<safeRows, id: \.self) { row in
                            HStack(spacing: cellSpacing) {
                                ForEach(0..<safeColumns, id: \.self) { column in
                                    let cell = GridCell(row: row, column: column)
                                    let isSelected = selectedCells.contains(cell)

                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(isSelected ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.06))
                                        .overlay {
                                            if showGridLines {
                                                RoundedRectangle(cornerRadius: 4)
                                                    .stroke(.white.opacity(0.25), lineWidth: 1)
                                            }
                                        }
                                        .frame(width: cellWidth, height: cellHeight)
                                        .contentShape(Rectangle())
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
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                    .animation(luminareAnimationFast, value: selectedCells)
                }
            }
            .frame(height: 128)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.bottom, 2)

            Text("Click cells to preview multi-cell selection")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
