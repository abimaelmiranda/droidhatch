public enum UpscalingMode: String, CaseIterable, Sendable {
    case nearest
    case linear
    case fsr1

    public static let defaultMode = UpscalingMode.fsr1

    public var title: String {
        switch self {
        case .nearest: "Nearest"
        case .linear: "Linear"
        case .fsr1: "FSR 1"
        }
    }
}
