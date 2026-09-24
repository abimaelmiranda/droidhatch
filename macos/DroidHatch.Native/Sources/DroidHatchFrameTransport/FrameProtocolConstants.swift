import Foundation

public enum FrameProtocolConstants {
    public static let version: UInt16 = 1
    public static let headerSize = 48
    public static let maximumPayloadSize: UInt32 = 256 * 1024 * 1024
    public static let messageTypeOffset = 6
    public static let headerSizeFieldOffset = 8
    public static let payloadSizeOffset = 12
    public static let sequenceOffset = 16
    public static let timestampOffset = 24
    public static let widthOffset = 32
    public static let heightOffset = 36
    public static let strideOffset = 40
    public static let pixelFormatOffset = 44
    public static let readChunkSize = 1024 * 1024
    public static let rgba8888PixelFormat: UInt32 = 1
    public static let yv12PixelFormat: UInt32 = 0x32315659
    public static let magic = Data([68, 72, 70, 82])
}
