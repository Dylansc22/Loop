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
    // Keep two-finger grid resize metrics aligned with single-finger movement thresholds.
    private static let axisLockDistancePx: Double = 4
    private static let activationDistancePx: Double = 4
    private static let stepDistancePx: Double = 110

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
        let rows: Int
        let columns: Int
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
    private var scrollWheelMonitor: ActiveEventMonitor?

    // State tracking
    private var activeConfiguration: GridConfiguration = .fromDefaults()
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
    private var activeScrollAxis: ScrollAxis?
    private var pendingAxisLockVerticalSignedPx: Double = 0
    private var pendingAxisLockHorizontalSignedPx: Double = 0
    private var pendingAxisLockVerticalTravelPx: Double = 0
    private var pendingAxisLockHorizontalTravelPx: Double = 0
    private var lockedAxisSignedTravelPx: Double = 0
    private var appliedDetentIndex: Int = 0

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
        activeConfiguration = configurationProvider()

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

        let scrollWheelMonitor = ActiveEventMonitor(
            events: [.scrollWheel],
            callback: { [weak self] event in
                self?.handleScrollWheel(event) ?? .forward
            }
        )
        scrollWheelMonitor.start()
        self.scrollWheelMonitor = scrollWheelMonitor

        let pointerLocation = CGEvent.mouseLocation ?? NSEvent.mouseLocation

        if initialSelection.isEmpty {
            // Publish initial state so the overlay can open with the current screen.
            processPointer(at: pointerLocation)
        } else {
            let initialScreen = initialScreen ?? screenContaining(point: pointerLocation)
            currentScreen = initialScreen
            selectedCells = initialSelection

            let config = activeConfiguration
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

        scrollWheelMonitor?.stop()
        scrollWheelMonitor = nil

        activeConfiguration = configurationProvider()
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
        resetScrollGestureState()

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

    private func handleScrollWheel(_ event: CGEvent) -> ActiveEventMonitor.EventHandling {
        guard checkIfLoopOpen() else {
            return .forward
        }

        guard !isDragging else {
            return .ignore
        }

        // Two-finger trackpad scrolling emits continuous events.
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 else {
            return .ignore
        }

        let scrollPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        if scrollPhase == Int64(CGScrollPhase.began.rawValue) {
            resetScrollGestureState()
        }
        if scrollPhase == Int64(CGScrollPhase.ended.rawValue)
            || scrollPhase == Int64(CGScrollPhase.cancelled.rawValue) {
            resetScrollGestureState()
            return .ignore
        }

        // Ignore inertia/momentum to mirror direct single-finger movement feel.
        let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        if momentumPhase != 0 {
            return .ignore
        }

        let verticalPointDelta = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let horizontalPointDelta = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        let verticalLineDelta = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
        let horizontalLineDelta = event.getDoubleValueField(.scrollWheelEventDeltaAxis2)

        let verticalDelta = verticalPointDelta != 0 ? verticalPointDelta : verticalLineDelta
        let horizontalDelta = horizontalPointDelta != 0 ? horizontalPointDelta : horizontalLineDelta

        let verticalMagnitude = abs(verticalDelta)
        let horizontalMagnitude = abs(horizontalDelta)
        guard max(verticalMagnitude, horizontalMagnitude) > 0 else {
            return .ignore
        }

        let lockedAxis: ScrollAxis
        if activeScrollAxis == nil {
            pendingAxisLockVerticalSignedPx += verticalDelta
            pendingAxisLockHorizontalSignedPx += horizontalDelta
            pendingAxisLockVerticalTravelPx += verticalMagnitude
            pendingAxisLockHorizontalTravelPx += horizontalMagnitude

            guard let resolvedAxis = lockScrollAxisIfNeeded(
                verticalTravel: pendingAxisLockVerticalTravelPx,
                horizontalTravel: pendingAxisLockHorizontalTravelPx
            ) else {
                return .ignore
            }
            lockedAxis = resolvedAxis

            if lockedAxis == .vertical {
                lockedAxisSignedTravelPx = pendingAxisLockVerticalSignedPx
            } else {
                lockedAxisSignedTravelPx = pendingAxisLockHorizontalSignedPx
            }
            pendingAxisLockVerticalSignedPx = 0
            pendingAxisLockHorizontalSignedPx = 0
            pendingAxisLockVerticalTravelPx = 0
            pendingAxisLockHorizontalTravelPx = 0
        } else {
            guard let resolvedAxis = activeScrollAxis else {
                return .ignore
            }
            lockedAxis = resolvedAxis
            if lockedAxis == .vertical {
                lockedAxisSignedTravelPx += verticalDelta
            } else {
                lockedAxisSignedTravelPx += horizontalDelta
            }
        }

        applyDetentSteps(for: lockedAxis)

        return .ignore
    }

    private enum ScrollAxis {
        case vertical
        case horizontal
    }

    private func resetScrollGestureState() {
        activeScrollAxis = nil
        pendingAxisLockVerticalSignedPx = 0
        pendingAxisLockHorizontalSignedPx = 0
        pendingAxisLockVerticalTravelPx = 0
        pendingAxisLockHorizontalTravelPx = 0
        lockedAxisSignedTravelPx = 0
        appliedDetentIndex = 0
    }

    private func lockScrollAxisIfNeeded(
        verticalTravel: Double,
        horizontalTravel: Double
    ) -> ScrollAxis? {
        if let activeScrollAxis {
            return activeScrollAxis
        }

        if verticalTravel >= Self.axisLockDistancePx,
           verticalTravel > horizontalTravel {
            activeScrollAxis = .vertical
            return .vertical
        }

        if horizontalTravel >= Self.axisLockDistancePx,
           horizontalTravel > verticalTravel {
            activeScrollAxis = .horizontal
            return .horizontal
        }

        return nil
    }

    private func detentIndex(for signedTravel: Double) -> Int {
        let travelMagnitude = abs(signedTravel)
        guard travelMagnitude > Self.activationDistancePx else {
            return 0
        }

        let additionalSteps = Int(((travelMagnitude - Self.activationDistancePx) / Self.stepDistancePx).rounded(.down))
        let stepMagnitude = 1 + additionalSteps
        return signedTravel > 0 ? stepMagnitude : -stepMagnitude
    }

    private func applyDetentSteps(for axis: ScrollAxis) {
        let targetDetentIndex = detentIndex(for: lockedAxisSignedTravelPx)
        var remaining = targetDetentIndex - appliedDetentIndex

        while remaining != 0 {
            let direction = remaining > 0 ? 1 : -1

            let resizeApplied: Bool
            if axis == .vertical {
                let rowDelta = direction < 0 ? 1 : -1 // down adds a bottom row, up removes bottom row
                resizeApplied = applyFootprintResizeStep(rowDelta: rowDelta, columnDelta: 0)
            } else {
                let columnDelta = direction < 0 ? 1 : -1 // right adds a right column, left removes right column
                resizeApplied = applyFootprintResizeStep(rowDelta: 0, columnDelta: columnDelta)
            }

            guard resizeApplied else {
                break
            }

            appliedDetentIndex += direction
            remaining -= direction
        }
    }

    private func applyFootprintResizeStep(rowDelta: Int, columnDelta: Int) -> Bool {
        guard rowDelta != 0 || columnDelta != 0 else {
            return false
        }

        let config = activeConfiguration
        var workingSelection = selectedCells
        if workingSelection.isEmpty {
            if let hoveredCell = currentHoveredCell {
                workingSelection = [hoveredCell]
            } else if let resolved = resolvePointerCellAndScreen() {
                currentScreen = resolved.screen
                currentHoveredCell = resolved.cell
                workingSelection = [resolved.cell]
            } else {
                return false
            }
        }

        guard let bounds = selectionBounds(for: workingSelection) else {
            return false
        }

        var updatedSelection = workingSelection

        if rowDelta > 0 {
            if bounds.maxRow < config.rows - 1 {
                // Grow downward.
                for column in bounds.minColumn...bounds.maxColumn {
                    updatedSelection.insert(GridCell(row: bounds.maxRow + 1, column: column))
                }
            } else if bounds.minRow < bounds.maxRow {
                // At bottom edge — shrink from top instead.
                for column in bounds.minColumn...bounds.maxColumn {
                    updatedSelection.remove(GridCell(row: bounds.minRow, column: column))
                }
            } else {
                return false
            }
        } else if rowDelta < 0 {
            // Shrink from bottom only.
            guard bounds.maxRow > bounds.minRow else {
                return false
            }
            for column in bounds.minColumn...bounds.maxColumn {
                updatedSelection.remove(GridCell(row: bounds.maxRow, column: column))
            }
        }

        if columnDelta > 0 {
            if bounds.maxColumn < config.columns - 1 {
                // Grow to the right.
                for row in bounds.minRow...bounds.maxRow {
                    updatedSelection.insert(GridCell(row: row, column: bounds.maxColumn + 1))
                }
            } else if bounds.minColumn < bounds.maxColumn {
                // At right edge — shrink from left instead.
                for row in bounds.minRow...bounds.maxRow {
                    updatedSelection.remove(GridCell(row: row, column: bounds.minColumn))
                }
            } else {
                return false
            }
        } else if columnDelta < 0 {
            // Shrink from the right only.
            guard bounds.maxColumn > bounds.minColumn else {
                return false
            }
            for row in bounds.minRow...bounds.maxRow {
                updatedSelection.remove(GridCell(row: row, column: bounds.maxColumn))
            }
        }

        guard updatedSelection != selectedCells else {
            return false
        }

        selectedCells = updatedSelection

        let pointerCell = currentHoveredCell ?? resolvePointerCellAndScreen()?.cell
        if let pointerCell {
            currentHoveredCell = pointerCell
        }
        configureHoverFootprint(cells: updatedSelection, pointerCell: pointerCell)

        let resolvedScreen = currentScreen ?? resolvePointerCellAndScreen()?.screen
        if let resolvedScreen {
            currentScreen = resolvedScreen
        }

        dispatchSelectionUpdate(makeSelectionUpdate(configuration: config, screen: currentScreen))
        return true
    }

    private func resolvePointerCellAndScreen() -> (screen: NSScreen, cell: GridCell)? {
        let pointerLocation = CGEvent.mouseLocation ?? NSEvent.mouseLocation
        guard let screen = currentScreen ?? screenContaining(point: pointerLocation) else {
            return nil
        }

        let interactionBounds = interactionBoundsProvider(screen)
        guard let cell = activeConfiguration.cellAt(point: pointerLocation, in: interactionBounds) else {
            return nil
        }

        return (screen, cell)
    }

    private func selectionBounds(for cells: Set<GridCell>) -> (minRow: Int, maxRow: Int, minColumn: Int, maxColumn: Int)? {
        guard
            let minRow = cells.map(\.row).min(),
            let maxRow = cells.map(\.row).max(),
            let minColumn = cells.map(\.column).min(),
            let maxColumn = cells.map(\.column).max()
        else {
            return nil
        }

        return (minRow, maxRow, minColumn, maxColumn)
    }

    private func processPointer(at location: CGPoint) {
        guard !isDragging else { return }

        let config = activeConfiguration
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

        let config = activeConfiguration
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

        let config = activeConfiguration
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

        let config = activeConfiguration
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
            rows: update.configuration.rows,
            columns: update.configuration.columns,
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

        let clampedSpanRows = Swift.min(span.rows, configuration.rows)
        let clampedSpanColumns = Swift.min(span.columns, configuration.columns)
        guard clampedSpanRows > 0, clampedSpanColumns > 0 else {
            return nil
        }

        let clampedAnchorRow = Swift.min(anchor.row, clampedSpanRows - 1)
        let clampedAnchorColumn = Swift.min(anchor.column, clampedSpanColumns - 1)

        let maxOriginRow = Swift.max(configuration.rows - clampedSpanRows, 0)
        let maxOriginColumn = Swift.max(configuration.columns - clampedSpanColumns, 0)

        let originRow = Swift.min(
            Swift.max(hoveredCell.row - clampedAnchorRow, 0),
            maxOriginRow
        )
        let originColumn = Swift.min(
            Swift.max(hoveredCell.column - clampedAnchorColumn, 0),
            maxOriginColumn
        )

        var cells: Set<GridCell> = []
        for row in originRow..<(originRow + clampedSpanRows) {
            for column in originColumn..<(originColumn + clampedSpanColumns) {
                cells.insert(GridCell(row: row, column: column))
            }
        }

        return cells
    }
}
