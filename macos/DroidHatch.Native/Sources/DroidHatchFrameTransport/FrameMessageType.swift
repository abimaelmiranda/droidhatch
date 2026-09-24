public enum FrameMessageType: UInt16, Sendable {
    case hello = 1
    case frame = 2
    case error = 3
    case status = 4
}
