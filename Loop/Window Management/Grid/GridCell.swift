//
//  GridCell.swift
//  Loop
//
//  Created by Codex on 2026-02-13.
//

import Foundation

struct GridCell: Hashable, Identifiable {
    let row: Int
    let column: Int

    var id: String {
        "\(row)-\(column)"
    }
}
