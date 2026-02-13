//
//  WindowActionIndicatorService.swift
//  Loop
//
//  Created by Kai Azim on 2026-01-19.
//

import AppKit
import Defaults

@MainActor
final class WindowActionIndicatorService {
    private let radialMenuController = RadialMenuController()
    private let gridOverlayController = GridOverlayController()
    private let previewController = PreviewController()

    func openAndUpdate(context: ResizeContext) {
        if Defaults[.gridModeEnabled] {
            radialMenuController.close()

            if Defaults[.previewVisibility] {
                previewController.open(context: context)
            } else {
                previewController.close()
            }

            gridOverlayController.open(context: context)
            return
        }

        gridOverlayController.close()

        if Defaults[.hideOnNoSelection], context.action.direction == .noSelection {
            closeAll()
            return
        }

        if Defaults[.previewVisibility] {
            previewController.open(context: context)
        } else {
            previewController.close()
        }

        if Defaults[.radialMenuVisibility] {
            radialMenuController.open(context: context)
        } else {
            radialMenuController.close()
        }
    }

    func closeAll() {
        radialMenuController.close()
        gridOverlayController.close()
        previewController.close()
    }
}
