import Foundation

public enum ViewerPictureInPicturePreference {
    public static let defaultsKey = "DroidHatch.viewer.pictureInPictureEnabled"
    public static let didChange = Notification.Name(
        "DroidHatch.viewer.pictureInPictureDidChange")
}
