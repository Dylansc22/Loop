//
//  GridConfigurationView.swift
//  Loop
//
//  Created by Codex on 2026-02-13.
//

import Defaults
import Luminare
import SwiftUI

struct GridConfigurationView: View {
    @Environment(\.luminareAnimation) private var luminareAnimation

    @Default(.gridModeEnabled) private var gridModeEnabled
    @Default(.gridColumns) private var gridColumns
    @Default(.gridRows) private var gridRows
    @Default(.gridShowLines) private var gridShowLines
    @Default(.gridMinColumns) private var gridMinColumns
    @Default(.gridMinRows) private var gridMinRows

    var body: some View {
        LuminareSection(String(localized: "Grid", comment: "Section header shown in settings")) {
            LuminareToggle("Enable grid mode", isOn: $gridModeEnabled)

            if gridModeEnabled {
                LuminareToggle("Show grid lines", isOn: $gridShowLines)

                LuminareSlider(
                    "Columns",
                    value: columnsBinding,
                    in: Double(GridConfiguration.minDimension)...Double(GridConfiguration.maxDimension),
                    step: 1,
                    format: .number.precision(.fractionLength(0...0)),
                    clampsUpper: false
                )
                .luminareSliderLayout(.compact(textBoxWidth: 48))

                LuminareSlider(
                    "Rows",
                    value: rowsBinding,
                    in: Double(GridConfiguration.minDimension)...Double(GridConfiguration.maxDimension),
                    step: 1,
                    format: .number.precision(.fractionLength(0...0)),
                    clampsUpper: false
                )
                .luminareSliderLayout(.compact(textBoxWidth: 48))

                LuminareSlider(
                    "Min columns",
                    value: minColumnsBinding,
                    in: 1...Double(gridColumns),
                    step: 1,
                    format: .number.precision(.fractionLength(0...0)),
                    clampsUpper: false
                )
                .luminareSliderLayout(.compact(textBoxWidth: 48))

                LuminareSlider(
                    "Min rows",
                    value: minRowsBinding,
                    in: 1...Double(gridRows),
                    step: 1,
                    format: .number.precision(.fractionLength(0...0)),
                    clampsUpper: false
                )
                .luminareSliderLayout(.compact(textBoxWidth: 48))

                GridPreviewView(columns: gridColumns, rows: gridRows, showGridLines: gridShowLines)
                    .padding(.top, 4)
            }
        }
        .animation(luminareAnimation, value: gridModeEnabled)
        .animation(luminareAnimation, value: gridColumns)
        .animation(luminareAnimation, value: gridRows)
    }

    private var columnsBinding: Binding<Double> {
        Binding(
            get: { Double(gridColumns) },
            set: {
                let value = Int($0.rounded())
                gridColumns = min(
                    max(value, GridConfiguration.minDimension),
                    GridConfiguration.maxDimension
                )
                if gridMinColumns > gridColumns {
                    gridMinColumns = gridColumns
                }
            }
        )
    }

    private var rowsBinding: Binding<Double> {
        Binding(
            get: { Double(gridRows) },
            set: {
                let value = Int($0.rounded())
                gridRows = min(
                    max(value, GridConfiguration.minDimension),
                    GridConfiguration.maxDimension
                )
                if gridMinRows > gridRows {
                    gridMinRows = gridRows
                }
            }
        )
    }

    private var minColumnsBinding: Binding<Double> {
        Binding(
            get: { Double(gridMinColumns) },
            set: {
                gridMinColumns = min(max(Int($0.rounded()), 1), gridColumns)
            }
        )
    }

    private var minRowsBinding: Binding<Double> {
        Binding(
            get: { Double(gridMinRows) },
            set: {
                gridMinRows = min(max(Int($0.rounded()), 1), gridRows)
            }
        )
    }
}
