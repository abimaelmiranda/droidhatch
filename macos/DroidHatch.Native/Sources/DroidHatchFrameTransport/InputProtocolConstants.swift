import Foundation

public enum InputProtocolConstants {
    public static let version: UInt16 = 1
    public static let headerSize = 16
    public static let maximumPayloadSize: UInt32 = 1024
    public static let messageTypeOffset = 6
    public static let headerSizeFieldOffset = 8
    public static let payloadSizeOffset = 12
    public static let normalizedCoordinateMaximum: UInt32 = 1_000_000
    public static let scrollFixedPointScale: Double = 1_024
    public static let magic = Data([68, 72, 73, 78])
}
