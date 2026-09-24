import SwiftUI
import DroidHatchViewer

@main
struct DroidHatchGUIApp: App {
    var body: some Scene {
        WindowGroup("DroidHatch") {
            LauncherView()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("DroidHatch") {
                Button("Show/Hide statistics") {
                    NotificationCenter.default.post(
                        name: .droidHatchToggleDiagnostics,
                        object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command])
            }
        }
    }
}
