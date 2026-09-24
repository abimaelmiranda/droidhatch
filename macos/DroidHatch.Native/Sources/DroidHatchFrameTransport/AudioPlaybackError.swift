import Foundation

public enum AudioPlaybackError: Error, LocalizedError {
    case unsupportedFormat

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "The native audio format is unavailable on this Mac."
        }
    }
}
