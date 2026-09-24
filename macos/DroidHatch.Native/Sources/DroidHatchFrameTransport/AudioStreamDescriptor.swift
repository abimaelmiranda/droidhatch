public struct AudioStreamDescriptor: Sendable {
    public let sampleRate: UInt32
    public let channelCount: UInt16
    public let sampleFormat: AudioSampleFormat
}
