import Combine
import DroidHatchViewer

@MainActor
final class UpscalingModeSelection: ObservableObject {
    @Published var mode = UpscalingMode.defaultMode
}
