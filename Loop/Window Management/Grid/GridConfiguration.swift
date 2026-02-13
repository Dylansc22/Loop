//
//  GridConfiguration.swift
//  Loop
//
//  Created by Codex on 2026-02-13.
//

import Defaults
import CoreGraphics
import Foundation

struct GridConfiguration: Codable, Hashable {
    static let minDimension = 1
    static let maxDimension = 10

    var isEnabled: Bool
    var columns: Int
    var rows: Int

    init(isEnabled: Bool, columns: Int, rows: Int) {
        self.isEnabled = isEnabled
        self.columns = columns.clamped(to: Self.minDimension...Self.maxDimension)
        self.rows = rows.clamped(to: Self.minDimension...Self.maxDimension)
    }

    static func fromDefaults() -> GridConfiguration {
        GridConfiguration(
            isEnabled: Defaults[.gridModeEnabled],
            columns: Defaults[.gridColumns],
            rows: Defaults[.gridRows]
        )
    }

    func calculateCellFrame(row: Int, column: Int, in screen: CGRect) -> CGRect {
        guard
            rows > 0,
            columns > 0,
            screen.width > 0,
            screen.height > 0,
            row >= 0,
            column >= 0,
            row < rows,
            column < columns
        else {
            return .zero
        }

        let cellWidth = screen.width / CGFloat(columns)
        let cellHeight = screen.height / CGFloat(rows)

        let x = screen.minX + (CGFloat(column) * cellWidth)
        let y = screen.minY + (CGFloat(row) * cellHeight)

        let width = column == columns - 1 ? screen.maxX - x : cellWidth
        let height = row == rows - 1 ? screen.maxY - y : cellHeight

        return CGRect(x: x, y: y, width: width, height: height)
    }

    func cellAt(point: CGPoint, in screen: CGRect) -> GridCell? {
        guard
            rows > 0,
            columns > 0,
            screen.width > 0,
            screen.height > 0,
            point.x >= screen.minX,
            point.x <= screen.maxX,
            point.y >= screen.minY,
            point.y <= screen.maxY
        else {
            return nil
        }

        let cellWidth = screen.width / CGFloat(columns)
        let cellHeight = screen.height / CGFloat(rows)

        var column = Int((point.x - screen.minX) / cellWidth)
        var row = Int((point.y - screen.minY) / cellHeight)

        // Include the trailing screen edges in the last cell.
        if point.x >= screen.maxX {
            column = columns - 1
        }
        if point.y >= screen.maxY {
            row = rows - 1
        }

        column = column.clamped(to: 0...(columns - 1))
        row = row.clamped(to: 0...(rows - 1))

        return GridCell(row: row, column: column)
    }

    func cellsIntersecting(rect: CGRect, in screen: CGRect) -> [GridCell] {
        guard
            rows > 0,
            columns > 0,
            screen.width > 0,
            screen.height > 0
        else {
            return []
        }

        let clippedRect = rect.intersection(screen)
        guard !clippedRect.isNull, !clippedRect.isEmpty else {
            return []
        }

        let cellWidth = screen.width / CGFloat(columns)
        let cellHeight = screen.height / CGFloat(rows)
        let epsilon: CGFloat = 0.001

        let minColumn = Int(floor((clippedRect.minX - screen.minX) / cellWidth))
        let maxColumn = Int(floor((min(clippedRect.maxX, screen.maxX) - screen.minX - epsilon) / cellWidth))
        let minRow = Int(floor((clippedRect.minY - screen.minY) / cellHeight))
        let maxRow = Int(floor((min(clippedRect.maxY, screen.maxY) - screen.minY - epsilon) / cellHeight))

        let clampedMinColumn = minColumn.clamped(to: 0...(columns - 1))
        let clampedMaxColumn = maxColumn.clamped(to: 0...(columns - 1))
        let clampedMinRow = minRow.clamped(to: 0...(rows - 1))
        let clampedMaxRow = maxRow.clamped(to: 0...(rows - 1))

        guard clampedMinColumn <= clampedMaxColumn, clampedMinRow <= clampedMaxRow else {
            return []
        }

        var cells: [GridCell] = []
        cells.reserveCapacity((clampedMaxColumn - clampedMinColumn + 1) * (clampedMaxRow - clampedMinRow + 1))

        for row in clampedMinRow...clampedMaxRow {
            for column in clampedMinColumn...clampedMaxColumn {
                cells.append(GridCell(row: row, column: column))
            }
        }

        return cells
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
