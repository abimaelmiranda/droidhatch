import Foundation

public struct AudioPlaybackMetrics: Sendable {
    public let packetCount: UInt64
    public let sequenceGapPackets: UInt64
    public let outOfOrderPackets: UInt64
    public let totalPacketFrames: UInt64
    public let sourcePacketIntervalNanoseconds: AudioPacketIntervalMetrics
    public let arrivalPacketIntervalNanoseconds: AudioPacketIntervalMetrics
    public let renderCallbackCount: UInt64
    public let lastPacketSequence: UInt64?
    public let lastPacketTimestampNanoseconds: UInt64?
    public let lastPacketFrameCount: UInt32?
    public let ringBuffer: AudioRingBufferMetrics

    public init(
        packetCount: UInt64,
        sequenceGapPackets: UInt64,
        outOfOrderPackets: UInt64,
        totalPacketFrames: UInt64,
        sourcePacketIntervalNanoseconds: AudioPacketIntervalMetrics,
        arrivalPacketIntervalNanoseconds: AudioPacketIntervalMetrics,
        renderCallbackCount: UInt64,
        lastPacketSequence: UInt64?,
        lastPacketTimestampNanoseconds: UInt64?,
        lastPacketFrameCount: UInt32?,
        ringBuffer: AudioRingBufferMetrics) {
        self.packetCount = packetCount
        self.sequenceGapPackets = sequenceGapPackets
        self.outOfOrderPackets = outOfOrderPackets
        self.totalPacketFrames = totalPacketFrames
        self.sourcePacketIntervalNanoseconds = sourcePacketIntervalNanoseconds
        self.arrivalPacketIntervalNanoseconds = arrivalPacketIntervalNanoseconds
        self.renderCallbackCount = renderCallbackCount
        self.lastPacketSequence = lastPacketSequence
        self.lastPacketTimestampNanoseconds = lastPacketTimestampNanoseconds
        self.lastPacketFrameCount = lastPacketFrameCount
        self.ringBuffer = ringBuffer
    }
}
