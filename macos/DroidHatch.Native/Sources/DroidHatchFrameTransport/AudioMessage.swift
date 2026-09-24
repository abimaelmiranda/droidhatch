public enum AudioMessage: Sendable {
    case hello
    case format(AudioStreamDescriptor)
    case audio(AudioPacket)
    case status(String)
    case error(String)
    case end
}
