import Foundation

public enum DroidHatchViewerNotifications {
    public static let playPauseShortcut = Notification.Name(
        "DroidHatch.playPauseShortcut")
    public static let toggleDiagnostics = Notification.Name(
        "DroidHatch.toggleDiagnostics")
    public static let setUpscalingMode = Notification.Name(
        "DroidHatch.setUpscalingMode")
    public static let showUpscalingSettings = Notification.Name(
        "DroidHatch.showUpscalingSettings")
    public static let didShow = Notification.Name(
        "DroidHatch.viewerDidShow")
    public static let didClose = Notification.Name(
        "DroidHatch.viewerDidClose")
}
