import AppKit
import CoreGraphics
import DroidHatchFrameTransport
import SwiftUI

final class InputCaptureView: NSView {
    var frameSize: CGSize?
    var sendKey: ((UInt16, InputKeyAction) -> Void)?
    var sendTouch: ((InputTouchAction, UInt32, UInt32) -> Void)? {
        didSet {
            preciseScrollController.sendTouch = sendTouch
        }
    }
    var sendScroll: ((ScrollInputEvent) -> Void)?
    var sendSystemAction: ((InputSystemAction) -> Void)?

    private var touchIsActive = false
    private var lastTouchCoordinates: (x: UInt32, y: UInt32)?
    private var scrollSequence: UInt32 = 0
    private var windowObservers: [NSObjectProtocol] = []
    private var pressedUsages = Set<UInt16>()
    private var suppressedShortcutKeyUps = Set<UInt16>()
    private var keyEventMonitor: Any?
    private let preciseScrollController = PreciseScrollInputController()

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeWindowObservers()
        removeKeyEventMonitor()
        if window == nil {
            cancelTouch()
            releasePressedKeys()
            return
        }
        observeWindowLifecycle()
        installKeyEventMonitor()
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        cancelTouch()
        releasePressedKeys()
        return super.resignFirstResponder()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if sendShortcut(for: event) {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if sendShortcut(for: event) {
            return
        }

        if let action = InputKeyMapping.systemAction(forKeyCode: event.keyCode) {
            sendSystemAction?(action)
            return
        }

        guard let usage = InputKeyMapping.hidUsage(forKeyCode: event.keyCode) else {
            return
        }
        guard pressedUsages.insert(usage).inserted else {
            return
        }
        sendKey?(usage, .down)
    }

    override func keyUp(with event: NSEvent) {
        if suppressedShortcutKeyUps.remove(event.keyCode) != nil {
            return
        }

        if InputKeyMapping.systemAction(forKeyCode: event.keyCode) != nil {
            return
        }

        guard let usage = InputKeyMapping.hidUsage(forKeyCode: event.keyCode) else {
            return
        }
        pressedUsages.remove(usage)
        sendKey?(usage, .up)
    }

    override func flagsChanged(with event: NSEvent) {
        guard let usage = InputKeyMapping.modifierUsage(forKeyCode: event.keyCode) else {
            return
        }

        if usage == 0xE3 {
            return
        }

        let isPressed: Bool
        switch usage {
        case 0xE0:
            isPressed = event.modifierFlags.contains(.control)
        case 0xE1:
            isPressed = event.modifierFlags.contains(.shift)
        case 0xE2:
            isPressed = event.modifierFlags.contains(.option)
        case 0xE3:
            isPressed = event.modifierFlags.contains(.command)
        default:
            isPressed = false
        }
        if isPressed {
            pressedUsages.insert(usage)
            sendKey?(usage, .down)
            return
        }

        guard pressedUsages.remove(usage) != nil else {
            return
        }
        sendKey?(usage, .up)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        preciseScrollController.finish()
        guard let coordinates = normalizedCoordinates(for: event.locationInWindow) else {
            return
        }
        touchIsActive = true
        lastTouchCoordinates = coordinates
        sendTouch?(.down, coordinates.x, coordinates.y)
    }

    override func mouseDragged(with event: NSEvent) {
        guard touchIsActive,
              let coordinates = normalizedCoordinates(for: event.locationInWindow) else {
            return
        }
        lastTouchCoordinates = coordinates
        sendTouch?(.move, coordinates.x, coordinates.y)
    }

    override func mouseUp(with event: NSEvent) {
        guard touchIsActive else {
            return
        }
        touchIsActive = false
        guard let lastTouchCoordinates else {
            return
        }
        let coordinates: (x: UInt32, y: UInt32)
        if let currentCoordinates = normalizedCoordinates(for: event.locationInWindow) {
            coordinates = currentCoordinates
        } else {
            coordinates = lastTouchCoordinates
        }
        self.lastTouchCoordinates = nil
        sendTouch?(.up, coordinates.x, coordinates.y)
    }

    override func scrollWheel(with event: NSEvent) {
        guard !touchIsActive else {
            return
        }

        if event.hasPreciseScrollingDeltas {
            preciseScrollController.handle(
                event: event,
                frameSize: frameSize,
                boundsSize: bounds.size,
                pointInView: convert(event.locationInWindow, from: nil))
            return
        }

        let directionMultiplier: CGFloat = event.isDirectionInvertedFromDevice ? -1 : 1
        guard let deltaX = fixedPointDelta(event.scrollingDeltaX),
              let deltaY = fixedPointDelta(
                  event.scrollingDeltaY * directionMultiplier),
              deltaX != 0 || deltaY != 0 else {
            return
        }

        var flags = InputScrollFlags()
        if event.hasPreciseScrollingDeltas {
            flags.insert(.precise)
        }
        if !event.momentumPhase.isEmpty {
            flags.insert(.momentum)
        }
        if event.isDirectionInvertedFromDevice {
            flags.insert(.directionInverted)
        }

        scrollSequence &+= 1
        sendScroll?(ScrollInputEvent(
            deltaX: deltaX,
            deltaY: deltaY,
            phase: inputPhase(for: event.phase),
            momentumPhase: inputPhase(for: event.momentumPhase),
            flags: flags,
            sequence: scrollSequence))
    }

    private func sendShortcut(for event: NSEvent) -> Bool {
        if InputKeyMapping.isPlayPauseShortcut(event) {
            if !event.isARepeat {
                NSLog(
                    "DroidHatch play/pause shortcut keyCode=%hu",
                    event.keyCode)
                sendSystemAction?(.playPause)
                suppressedShortcutKeyUps.insert(event.keyCode)
            }
            return true
        }

        guard event.modifierFlags.contains(.command) else {
            return false
        }

        let action: InputSystemAction
        switch event.keyCode {
        case MacKeyboardLayout.homeShortcutKeyCode:
            action = .home
        case MacKeyboardLayout.backShortcutKeyCode:
            action = .back
        case MacKeyboardLayout.volumeUpShortcutKeyCode:
            action = .volumeUp
        case MacKeyboardLayout.volumeDownShortcutKeyCode:
            action = .volumeDown
        default:
            return false
        }

        NSLog(
            "DroidHatch shortcut keyCode=%hu action=%@",
            event.keyCode,
            String(describing: action))
        sendSystemAction?(action)
        return true
    }

    private func installKeyEventMonitor() {
        guard keyEventMonitor == nil else {
            return
        }

        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self, event.window === self.window else {
                return event
            }
            return self.sendShortcut(for: event) ? nil : event
        }
    }

    private func removeKeyEventMonitor() {
        guard let keyEventMonitor else {
            return
        }
        NSEvent.removeMonitor(keyEventMonitor)
        self.keyEventMonitor = nil
    }

    private func releasePressedKeys() {
        let usages = pressedUsages
        pressedUsages.removeAll(keepingCapacity: true)
        for usage in usages {
            sendKey?(usage, .up)
        }
    }

    private func observeWindowLifecycle() {
        guard let window else {
            return
        }

        let notificationCenter = NotificationCenter.default
        windowObservers.append(
            notificationCenter.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.resetInputState()
                    }
                })
        windowObservers.append(
            notificationCenter.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: NSApp,
                queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.resetInputState()
                    }
                })
    }

    private func removeWindowObservers() {
        let notificationCenter = NotificationCenter.default
        for observer in windowObservers {
            notificationCenter.removeObserver(observer)
        }
        windowObservers.removeAll(keepingCapacity: true)
    }

    private func resetInputState() {
        cancelTouch()
        preciseScrollController.finish()
        releasePressedKeys()
    }

    private func cancelTouch() {
        guard touchIsActive else {
            return
        }
        touchIsActive = false
        guard let coordinates = lastTouchCoordinates else {
            return
        }
        lastTouchCoordinates = nil
        sendTouch?(.up, coordinates.x, coordinates.y)
    }

    private func normalizedCoordinates(for pointInWindow: NSPoint) -> (x: UInt32, y: UInt32)? {
        guard let frameSize,
              frameSize.width > 0,
              frameSize.height > 0 else {
            return nil
        }

        let point = convert(pointInWindow, from: nil)
        let contentRect = ViewerAspectFitLayout.rect(
            sourceSize: frameSize,
            boundsSize: bounds.size)
        guard contentRect.contains(point) else {
            return nil
        }

        let x = (point.x - contentRect.minX) / contentRect.width
        let y = 1 - ((point.y - contentRect.minY) / contentRect.height)
        let maximum = CGFloat(InputProtocolConstants.normalizedCoordinateMaximum)
        return (
            UInt32(max(0, min(maximum, x * maximum))),
            UInt32(max(0, min(maximum, y * maximum))))
    }

    private func fixedPointDelta(_ value: CGFloat) -> Int32? {
        guard value.isFinite else {
            return nil
        }

        let scaledValue = value * CGFloat(InputProtocolConstants.scrollFixedPointScale)
        guard scaledValue >= CGFloat(Int32.min),
              scaledValue <= CGFloat(Int32.max) else {
            return nil
        }
        return Int32(scaledValue.rounded(.towardZero))
    }

    private func inputPhase(for phase: NSEvent.Phase) -> InputScrollPhase {
        if phase.contains(.began) {
            return .began
        }
        if phase.contains(.changed) {
            return .changed
        }
        if phase.contains(.ended) {
            return .ended
        }
        if phase.contains(.cancelled) {
            return .cancelled
        }
        return .none
    }

}
