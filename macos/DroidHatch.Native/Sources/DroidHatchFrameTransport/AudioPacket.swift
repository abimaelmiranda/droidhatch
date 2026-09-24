import Foundation

public struct AudioPacket: Sendable {
    public let sequence: UInt64
    public let timestampNanoseconds: UInt64
    public let descriptor: AudioStreamDescriptor
    public let frameCount: UInt32
    public let payload: Data
}
