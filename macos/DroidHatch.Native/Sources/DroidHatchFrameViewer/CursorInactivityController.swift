import AppKit

final class CursorInactivityController {
    private static let inactivityInterval: TimeInterval = 2

    private var eventMonitor: Any?
    private var inactivityTimer: Timer?

    func start() {
        guard eventMonitor == nil else {
            return
        }

        let activityEvents: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ]
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: activityEvents) {
            [weak self] event in
            self?.registerActivity()
            return event
        }
        registerActivity()
    }

    func stop() {
        inactivityTimer?.invalidate()
        inactivityTimer = nil
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        NSCursor.setHiddenUntilMouseMoves(false)
    }

    private func registerActivity() {
        NSCursor.setHiddenUntilMouseMoves(false)
        inactivityTimer?.invalidate()
        inactivityTimer = Timer.scheduledTimer(
            withTimeInterval: Self.inactivityInterval,
            repeats: false) { _ in
                NSCursor.setHiddenUntilMouseMoves(true)
            }
    }

    deinit {
        stop()
    }
}
