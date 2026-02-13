//
//  GridInteractionObserver.swift
//  Loop
//
//  Created by Codex on 2026-02-13.
//

import AppKit
import Scribe

@Loggable
final class GridInteractionObserver {
    struct SelectionUpdate {
        let configuration: GridConfiguration
        let cells: Set<GridCell>
        let action: WindowAction
        let screen: NSScreen?
        let isDragging: Bool
    }

    private struct SelectionState: Equatable {
        let cells: Set<GridCell>
        let screenDisplayID: CGDirectDisplayID?
        let isDragging: Bool
    }

    // Parameters
    private let selectionChanged: (SelectionUpdate) -> ()
    private let selectionCompleted: (SelectionUpdate) -> ()
    private let checkIfLoopOpen: () -> Bool
    private let configurationProvider: () -> GridConfiguration
    private let interactionBoundsProvider: (NSScreen) -> CGRect

    // Event monitors
    private var mouseMovementMonitor: PassiveEventMonitor?
    private var leftClickMonitor: ActiveEventMonitor?

    // State tracking
    private var currentScreen: NSScreen?
    private var currentHoveredCell: GridCell?
    private var selectedCells: Set<GridCell> = []
    private var shouldPreserveSelectionFootprint: Bool = false
    private var hoverFootprintSpan: (rows: Int, columns: Int)?
    private var hoverFootprintAnchorOffset: (row: Int, column: Int)?

    private var isDragging: Bool = false
    private var dragSelection: GridSelection?
    private var dragStartPoint: CGPoint = .zero
    private var dragStartScreen: NSScreen?

    private var previousSelectionState: SelectionState?

    init(
        selectionChanged: @escaping (SelectionUpdate) -> (),
        selectionCompleted: @escaping (SelectionUpdate) -> (),
        checkIfLoopOpen: @escaping () -> Bool,
        configurationProvider: @escaping () -> GridConfiguration,
        interactionBoundsProvider: @escaping (NSScreen) -> CGRect
    ) {
        self.selectionChanged = selectionChanged
        self.selectionCompleted = selectionCompleted
        self.checkIfLoopOpen = checkIfLoopOpen
        self.configurationProvider = configurationProvider
        self.interactionBoundsProvider = interactionBoundsProvider
    }

    func start(initialSelection: Set<GridCell> = [], initialScreen: NSScreen? = nil) {
        stop()

        let mouseMovementMonitor = PassiveEventMonitor(
            events: [.mouseMoved],
            callback: { [weak self] event in
                self?.handleMouseMoved(event)
            }
        )
        mouseMovementMonitor.start()
        self.mouseMovementMonitor = mouseMovementMonitor

        let leftClickMonitor = ActiveEventMonitor(
            events: [.leftMouseDown, .leftMouseDragged, .leftMouseUp],
            callback: { [weak self] event in
                self?.handleLeftMouse(event) ?? .forward
            }
        )
        leftClickMonitor.start()
        self.leftClickMonitor = leftClickMonitor

        let pointerLocation = CGEvent.mouseLocation ?? NSEvent.mouseLocation

        if initialSelection.isEmpty {
            // Publish initial state so the overlay can open with the current screen.
            processPointer(at: pointerLocation)
        } else {
            let initialScreen = initialScreen ?? screenContaining(point: pointerLocation)
            currentScreen = initialScreen
            selectedCells = initialSelection

            let config = configurationProvider()
            let pointerCell = initialScreen
                .flatMap {
                    config.cellAt(
                        point: pointerLocation,
                        in: interactionBoundsProvider($0)
                    )
                }
            configureHoverFootprint(cells: initialSelection, pointerCell: pointerCell)
        }

        log.info("Started")
    }

    func stop() {
        mouseMovementMonitor?.stop()
        mouseMovementMonitor = nil

        leftClickMonitor?.stop()
        leftClickMonitor = nil

        currentScreen = nil
        currentHoveredCell = nil
        selectedCells = []
        shouldPreserveSelectionFootprint = false
        hoverFootprintSpan = nil
        hoverFootprintAnchorOffset = nil

        isDragging = false
        dragSelection = nil
        dragStartPoint = .zero
        dragStartScreen = nil

        previousSelectionState = nil

        log.success("Stopped, all stored states cleared.")
    }

    private func handleMouseMoved(_ event: CGEvent) {
        guard checkIfLoopOpen() else { return }
        processPointer(at: event.location)
    }

    private func handleLeftMouse(_ event: CGEvent) -> ActiveEventMonitor.EventHandling {
        guard checkIfLoopOpen() else {
            return .forward
        }

        switch event.type {
        case .leftMouseDown:
            beginDrag(at: event.location)
        case .leftMouseDragged:
            updateDrag(at: event.location)
        case .leftMouseUp:
            endDrag(at: event.location)
        default:
            break
        }

        // Consume left click and drag events while Loop is active in grid mode to avoid click-through.
        return .ignore
    }

    private func processPointer(at location: CGPoint) {
        guard !isDragging else { return }

        let config = configurationProvider()
        guard let screen = screenContaining(point: location) else {
            currentHoveredCell = nil
            selectedCells = []
            dispatchSelectionUpdate(makeSelectionUpdate(configuration: config, screen: nil))
            return
        }

        currentScreen = screen

        let interactionBounds = interactionBoundsProvider(screen)
        let hoveredCell = config.cellAt(point: location, in: interactionBounds)

        currentHoveredCell = hoveredCell
        if let hoveredCell {
            if shouldPreserveSelectionFootprint,
               let translatedSelection = translatedHoverSelection(
                   hoveredCell: hoveredCell,
                   configuration: config
               ) {
                selectedCells = translatedSelection
            } else {
                selectedCells = [hoveredCell]
            }
        } else {
            selectedCells = []
        }

        dispatchSelectionUpdate(makeSelectionUpdate(configuration: config, screen: screen))
    }

    private func beginDrag(at location: CGPoint) {
        isDragging = true
        shouldPreserveSelectionFootprint = false
        dragStartPoint = location

        let config = configurationProvider()
        guard let screen = screenContaining(point: location) else {
            dragStartScreen = nil
            dragSelection = GridSelection()
            selectedCells = []
            dispatchSelectionUpdate(makeSelectionUpdate(configuration: config, screen: nil))
            return
        }

        dragStartScreen = screen
        currentScreen = screen

        let interactionBounds = interactionBoundsProvider(screen)
        let startCell = config.cellAt(point: location, in: interactionBounds)

        var selection = GridSelection()
        selection.startCell = startCell
        selection.currentCells = startCell.map { [$0] } ?? []
        selection.boundingFrame = selectionBoundingFrame(
            cells: selection.currentCells,
            configuration: config,
            in: interactionBounds
        )

        dragSelection = selection
        selectedCells = selection.currentCells

        dispatchSelectionUpdate(makeSelectionUpdate(configuration: config, screen: screen))
    }

    private func updateDrag(at location: CGPoint) {
        guard isDragging else {
            beginDrag(at: location)
            return
        }

        let config = configurationProvider()
        guard let screen = screenContaining(point: location) else {
            selectedCells = []
            dispatchSelectionUpdate(makeSelectionUpdate(configuration: config, screen: dragStartScreen))
            return
        }

        if dragStartScreen?.isSameScreen(screen) != true {
            dragStartScreen = screen
            dragStartPoint = location

            var resetSelection = GridSelection()
            let interactionBounds = interactionBoundsProvider(screen)
            let startCell = config.cellAt(point: location, in: interactionBounds)
            resetSelection.startCell = startCell
            resetSelection.currentCells = startCell.map { [$0] } ?? []
            resetSelection.boundingFrame = selectionBoundingFrame(
                cells: resetSelection.currentCells,
                configuration: config,
                in: interactionBounds
            )
            dragSelection = resetSelection
        }

        currentScreen = dragStartScreen

        guard let dragStartScreen else {
            selectedCells = []
            dispatchSelectionUpdate(makeSelectionUpdate(configuration: config, screen: nil))
            return
        }

        let interactionBounds = interactionBoundsProvider(dragStartScreen)
        let dragRect = CGRect(
            x: min(dragStartPoint.x, location.x),
            y: min(dragStartPoint.y, location.y),
            width: abs(location.x - dragStartPoint.x),
            height: abs(location.y - dragStartPoint.y)
        )

        let isClickSelection = dragRect.width < 1 && dragRect.height < 1
        let intersectingCells: Set<GridCell> = if isClickSelection {
            if let startCell = dragSelection?.startCell {
                [startCell]
            } else if let hoveredCell = config.cellAt(point: location, in: interactionBounds) {
                [hoveredCell]
            } else {
                []
            }
        } else {
            Set(config.cellsIntersecting(rect: dragRect, in: interactionBounds))
        }
        selectedCells = intersectingCells

        if var dragSelection {
            dragSelection.currentCells = intersectingCells
            dragSelection.boundingFrame = selectionBoundingFrame(
                cells: intersectingCells,
                configuration: config,
                in: interactionBounds
            )
            self.dragSelection = dragSelection
        }

        dispatchSelectionUpdate(makeSelectionUpdate(configuration: config, screen: dragStartScreen))
    }

    private func endDrag(at location: CGPoint) {
        updateDrag(at: location)

        isDragging = false
        dragSelection = nil
        dragStartScreen = nil

        let config = configurationProvider()
        let update = makeSelectionUpdate(configuration: config, screen: currentScreen)
        dispatchSelectionUpdate(update)

        if !update.cells.isEmpty {
            selectionCompleted(update)
        }
    }

    private func makeSelectionUpdate(configuration: GridConfiguration, screen: NSScreen?) -> SelectionUpdate {
        let screenBounds = screen.map(interactionBoundsProvider) ?? .zero
        let action = GridWindowAction.createAction(from: selectedCells, config: configuration, screen: screenBounds)

        return .init(
            configuration: configuration,
            cells: selectedCells,
            action: action,
            screen: screen,
            isDragging: isDragging
        )
    }

    private func dispatchSelectionUpdate(_ update: SelectionUpdate) {
        let state = SelectionState(
            cells: update.cells,
            screenDisplayID: update.screen?.displayID,
            isDragging: update.isDragging
        )

        guard previousSelectionState != state else {
            return
        }

        previousSelectionState = state

        selectionChanged(update)
    }

    private func selectionBoundingFrame(cells: Set<GridCell>, configuration: GridConfiguration, in screen: CGRect) -> CGRect {
        guard let firstCell = cells.first else {
            return .zero
        }

        var result = configuration.calculateCellFrame(
            row: firstCell.row,
            column: firstCell.column,
            in: screen
        )

        for cell in cells.dropFirst() {
            result = result.union(
                configuration.calculateCellFrame(
                    row: cell.row,
                    column: cell.column,
                    in: screen
                )
            )
        }

        return result
    }

    private func screenContaining(point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    private func configureHoverFootprint(cells: Set<GridCell>, pointerCell: GridCell?) {
        guard
            let minRow = cells.map(\.row).min(),
            let maxRow = cells.map(\.row).max(),
            let minColumn = cells.map(\.column).min(),
            let maxColumn = cells.map(\.column).max()
        else {
            shouldPreserveSelectionFootprint = false
            hoverFootprintSpan = nil
            hoverFootprintAnchorOffset = nil
            return
        }

        hoverFootprintSpan = (
            rows: maxRow - minRow + 1,
            columns: maxColumn - minColumn + 1
        )

        if let pointerCell {
            hoverFootprintAnchorOffset = (
                row: Swift.min(Swift.max(pointerCell.row - minRow, 0), maxRow - minRow),
                column: Swift.min(Swift.max(pointerCell.column - minColumn, 0), maxColumn - minColumn)
            )
        } else {
            hoverFootprintAnchorOffset = (row: 0, column: 0)
        }

        shouldPreserveSelectionFootprint = true
    }

    private func translatedHoverSelection(
        hoveredCell: GridCell,
        configuration: GridConfiguration
    ) -> Set<GridCell>? {
        guard
            let span = hoverFootprintSpan,
            let anchor = hoverFootprintAnchorOffset,
            span.rows > 0,
            span.columns > 0
        else {
            return nil
        }

        let maxOriginRow = Swift.max(configuration.rows - span.rows, 0)
        let maxOriginColumn = Swift.max(configuration.columns - span.columns, 0)

        let originRow = Swift.min(
            Swift.max(hoveredCell.row - anchor.row, 0),
            maxOriginRow
        )
        let originColumn = Swift.min(
            Swift.max(hoveredCell.column - anchor.column, 0),
            maxOriginColumn
        )

        var cells: Set<GridCell> = []
        for row in originRow..<(originRow + span.rows) {
            for column in originColumn..<(originColumn + span.columns) {
                cells.insert(GridCell(row: row, column: column))
            }
        }

        return cells
    }
}
