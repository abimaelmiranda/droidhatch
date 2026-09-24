import Foundation

public enum FrameMessage: Sendable {
    case hello
    case frame(FrameHeader, Data)
    case error(FrameHeader, String)
    case status(FrameHeader, String)
}
