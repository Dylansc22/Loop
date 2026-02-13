//
//  RadialMenuController.swift
//  Loop
//
//  Created by Kai Azim on 2023-01-23.
//

import Scribe
import SwiftUI

@Loggable
@MainActor
final class RadialMenuController: WindowActionIndicator {
    private var viewModel: RadialMenuViewModel = .init(isSettingsPreview: false)
    private var controller: NSWindowController?

    func open(context: ResizeContext) {
        defer { viewModel.updateContext(with: context) }

        if let window = controller?.window {
            window.orderFrontRegardless()
            return
        }

        let mouseX: CGFloat = context.initialMousePosition.x
        let mouseY: CGFloat = context.initialMousePosition.y
        let windowSize: CGFloat = 100 + 80

        let panel = ActivePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        controller = .init(window: panel)

        panel.ignoresMouseEvents = true
        panel.collectionBehavior = .canJoinAllSpaces
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.level = .screenSaver
        panel.contentView = NSHostingView(rootView: RadialMenuView(viewModel: viewModel))

        // Position at the same anchor used by interaction logic.
        panel.setFrameOrigin(
            NSPoint(
                x: mouseX - windowSize / 2,
                y: mouseY - windowSize / 2
            )
        )

        panel.orderFrontRegardless()

        log.ui("Initialized controller")
    }

    func close() {
        guard let windowController = controller else { return }
        controller = nil

        Task {
            viewModel.setIsShown(false, animationDuration: 0.15)
            try? await Task.sleep(for: .seconds(0.15))
            windowController.window?.orderOut(nil)
            windowController.close()

            log.ui("Controller closed")
        }
    }
}
