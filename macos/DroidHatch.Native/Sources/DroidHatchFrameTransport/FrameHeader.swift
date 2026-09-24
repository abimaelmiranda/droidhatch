public struct FrameHeader: Sendable {
    public let messageType: FrameMessageType
    public let sequence: UInt64
    public let timestampNanoseconds: UInt64
    public let width: UInt32
    public let height: UInt32
    public let strideBytes: UInt32
    public let pixelFormat: UInt32
    public let payloadSize: UInt32
}
