import AppKit

extension Notification.Name {
    static let droidHatchPlayPauseShortcut = Notification.Name(
        "DroidHatch.playPauseShortcut")
    public static let droidHatchToggleDiagnostics = Notification.Name(
        "DroidHatch.toggleDiagnostics")
    static let droidHatchViewerDidShow = Notification.Name(
        "DroidHatch.viewerDidShow")
    static let droidHatchViewerDidClose = Notification.Name(
        "DroidHatch.viewerDidClose")
}

final class ViewerNSWindow: NSWindow {
    private var suppressedKeyUps = Set<UInt16>()

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           InputKeyMapping.isPlayPauseShortcut(event) {
            if !event.isARepeat {
                NSLog(
                    "DroidHatch window play/pause shortcut keyCode=%hu",
                    event.keyCode)
                NotificationCenter.default.post(
                    name: .droidHatchPlayPauseShortcut,
                    object: nil)
            }
            suppressedKeyUps.insert(event.keyCode)
            return
        }

        if event.type == .keyUp,
           suppressedKeyUps.remove(event.keyCode) != nil {
            return
        }

        super.sendEvent(event)
    }
}
