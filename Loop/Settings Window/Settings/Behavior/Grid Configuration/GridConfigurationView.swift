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

    var body: some View {
        LuminareSection(String(localized: "Grid", comment: "Section header shown in settings")) {
            LuminareToggle("Enable grid mode", isOn: $gridModeEnabled)

            if gridModeEnabled {
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

                GridPreviewView(columns: gridColumns, rows: gridRows)
                    .padding(.top, 4)
            }
        }
        .animation(luminareAnimation, value: [gridModeEnabled, gridColumns, gridRows])
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
            }
        )
    }
}
