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
            let safeRect = safeRectInOverlay(geometry: geometry)

            ZStack(alignment: .topLeading) {
                subtleBackground()

                if safeRect.width > 0, safeRect.height > 0 {
                    gridSurface()
                        .frame(width: safeRect.width, height: safeRect.height)
                        .offset(x: safeRect.minX, y: safeRect.minY)
                }
            }
            .animation(luminareAnimationFast, value: viewModel.highlightedCells)
            .animation(luminareAnimationFast, value: viewModel.isDragging)
        }
        .opacity(viewModel.isShown ? 1 : 0)
    }

    private func subtleBackground() -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.005))
            .overlay {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, state: .active)
                    .opacity(0.02)
            }
            .overlay {
                LinearGradient(
                    colors: [accentColorController.color1, accentColorController.color2],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(0.006)
            }
    }

    private func gridSurface() -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: previewCornerRadius)
                .fill(Color.white.opacity(0.012))

            highlightedCellsLayer()

            gridLineLayer()

            RoundedRectangle(cornerRadius: previewCornerRadius)
                .stroke(.white.opacity(0.2), lineWidth: viewModel.isDragging ? 1.5 : 1)
        }
        .clipShape(.rect(cornerRadius: previewCornerRadius))
    }

    private func highlightedCellsLayer() -> some View {
        let cells = viewModel.highlightedCells.sorted {
            $0.row == $1.row ? $0.column < $1.column : $0.row < $1.row
        }

        return ForEach(cells, id: \.self) { cell in
            let frame = localCellFrame(cell: cell)

            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: [accentColorController.color1, accentColorController.color2],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .opacity(viewModel.isDragging ? 0.12 : 0.07)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
        }
    }

    private func gridLineLayer() -> some View {
        let columns = Swift.max(viewModel.gridConfiguration.columns, 1)
        let rows = Swift.max(viewModel.gridConfiguration.rows, 1)
        let width = viewModel.safeBounds.width
        let height = viewModel.safeBounds.height

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

    private func safeRectInOverlay(geometry: GeometryProxy) -> CGRect {
        guard viewModel.displayBounds.width > 0, viewModel.displayBounds.height > 0 else {
            return CGRect(origin: .zero, size: geometry.size)
        }

        let localRect = CGRect(
            x: viewModel.safeBounds.minX - viewModel.displayBounds.minX,
            y: viewModel.safeBounds.minY - viewModel.displayBounds.minY,
            width: viewModel.safeBounds.width,
            height: viewModel.safeBounds.height
        )

        let overlayRect = CGRect(origin: .zero, size: geometry.size)
        return localRect.intersection(overlayRect)
    }

    private func localCellFrame(cell: GridCell) -> CGRect {
        let absoluteFrame = viewModel.gridConfiguration.calculateCellFrame(
            row: cell.row,
            column: cell.column,
            in: viewModel.safeBounds
        )

        return CGRect(
            x: absoluteFrame.minX - viewModel.safeBounds.minX,
            y: absoluteFrame.minY - viewModel.safeBounds.minY,
            width: absoluteFrame.width,
            height: absoluteFrame.height
        )
    }
}
