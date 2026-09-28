import SwiftUI
import DroidHatchViewer

@main
struct DroidHatchGUIApp: App {
    @StateObject private var upscalingSelection = UpscalingModeSelection()
    @AppStorage(ViewerPictureInPicturePreference.defaultsKey)
    private var pictureInPictureEnabled = false

    var body: some Scene {
        WindowGroup("DroidHatch") {
            LauncherView()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("DroidHatch") {
                Toggle("Picture in Picture", isOn: $pictureInPictureEnabled)
                    .onChange(of: pictureInPictureEnabled) { _, isEnabled in
                        NotificationCenter.default.post(
                            name: ViewerPictureInPicturePreference.didChange,
                            object: isEnabled)
                    }
                Divider()
                Menu("Video Scaling") {
                    Picker("Video Scaling", selection: $upscalingSelection.mode) {
                        ForEach(UpscalingMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .onChange(of: upscalingSelection.mode) { _, mode in
                        NotificationCenter.default.post(
                            name: DroidHatchViewerNotifications.setUpscalingMode,
                            object: mode.rawValue)
                    }
                }
                Button("Upscaling Controls…") {
                    NotificationCenter.default.post(
                        name: DroidHatchViewerNotifications.showUpscalingSettings,
                        object: nil)
                }
                Button("Show/Hide statistics") {
                    NotificationCenter.default.post(
                        name: DroidHatchViewerNotifications.toggleDiagnostics,
                        object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command])
            }
        }
    }
}
