//
//  GridOverlayController.swift
//  Loop
//
//  Created by Codex on 2026-02-13.
//

import AppKit
import Scribe
import SwiftUI

@Loggable
@MainActor
final class GridOverlayController: WindowActionIndicator {
    private let viewModel = GridOverlayViewModel()
    private var controller: NSWindowController?
    private var closeTask: Task<Void, Never>?

    func open(context: ResizeContext) {
        closeTask?.cancel()
        closeTask = nil

        guard let screen = context.screen else {
            return
        }

        if let window = controller?.window {
            if window.screen != screen {
                window.setFrame(screen.frame, display: true)
            }

            window.orderFrontRegardless()
            viewModel.updateContext(with: context)
            return
        }

        defer { viewModel.updateContext(with: context) }

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
        panel.level = NSWindow.Level(NSWindow.Level.screenSaver.rawValue - 2)
        panel.contentView = NSHostingView(rootView: GridOverlayView(viewModel: viewModel))
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()

        log.ui("Initialized controller")
    }

    func close() {
        guard closeTask == nil, let windowController = controller else { return }

        closeTask = Task { [weak self] in
            viewModel.setIsShown(false)
            try? await Task.sleep(for: .seconds(0.15))
            guard !Task.isCancelled else { return }
            windowController.window?.orderOut(nil)
            windowController.close()
            self?.controller = nil
            self?.closeTask = nil

            log.ui("Controller closed")
        }
    }
}
