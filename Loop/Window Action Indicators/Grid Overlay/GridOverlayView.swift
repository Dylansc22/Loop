//
//  GridOverlayView.swift
//  Loop
//
//  Created by Codex on 2026-02-13.
//

import Defaults
import SwiftUI

struct GridOverlayView: View {
    @Environment(\.luminareAnimationFast) private var luminareAnimationFast
    @ObservedObject private var accentColorController: AccentColorController = .shared
    @ObservedObject private var viewModel: GridOverlayViewModel

    @Default(.previewCornerRadius) private var previewCornerRadius

    init(viewModel: GridOverlayViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        LinearGradient(
                            colors: [accentColorController.color1, accentColorController.color2],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .opacity(0.08)
                    }

                highlightedCellsLayer(geometry: geometry)

                gridLineLayer(geometry: geometry)

                RoundedRectangle(cornerRadius: previewCornerRadius)
                    .stroke(.white.opacity(0.24), lineWidth: viewModel.isDragging ? 2 : 1)
            }
            .clipShape(.rect(cornerRadius: previewCornerRadius))
            .animation(luminareAnimationFast, value: viewModel.highlightedCells)
            .animation(luminareAnimationFast, value: viewModel.isDragging)
        }
        .opacity(viewModel.isShown ? 1 : 0)
    }

    private func highlightedCellsLayer(geometry: GeometryProxy) -> some View {
        let columns = max(viewModel.gridConfiguration.columns, 1)
        let rows = max(viewModel.gridConfiguration.rows, 1)
        let cellWidth = geometry.size.width / CGFloat(columns)
        let cellHeight = geometry.size.height / CGFloat(rows)
        let cells = viewModel.highlightedCells.sorted {
            $0.row == $1.row ? $0.column < $1.column : $0.row < $1.row
        }

        return ForEach(cells) { cell in
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: [accentColorController.color1, accentColorController.color2],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .opacity(viewModel.isDragging ? 0.38 : 0.28)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.white.opacity(0.25), lineWidth: 1)
                }
                .frame(
                    width: cell.column == columns - 1 ? geometry.size.width - (CGFloat(cell.column) * cellWidth) : cellWidth,
                    height: cell.row == rows - 1 ? geometry.size.height - (CGFloat(cell.row) * cellHeight) : cellHeight
                )
                .offset(
                    x: CGFloat(cell.column) * cellWidth,
                    y: CGFloat(cell.row) * cellHeight
                )
        }
    }

    private func gridLineLayer(geometry: GeometryProxy) -> some View {
        let columns = max(viewModel.gridConfiguration.columns, 1)
        let rows = max(viewModel.gridConfiguration.rows, 1)
        let width = geometry.size.width
        let height = geometry.size.height

        return Path { path in
            guard width > 0, height > 0 else { return }

            for row in 1..<rows {
                let y = (CGFloat(row) / CGFloat(rows)) * height
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: width, y: y))
            }

            for column in 1..<columns {
                let x = (CGFloat(column) / CGFloat(columns)) * width
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: height))
            }
        }
        .stroke(.white.opacity(0.3), lineWidth: 1)
    }
}
