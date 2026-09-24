public enum AudioMessageType: UInt16, Sendable {
    case hello = 1
    case format = 2
    case audio = 3
    case status = 4
    case error = 5
    case end = 6
}
