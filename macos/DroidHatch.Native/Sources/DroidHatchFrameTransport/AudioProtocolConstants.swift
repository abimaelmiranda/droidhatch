import Foundation

enum AudioProtocolConstants {
    static let version: UInt16 = 1
    static let headerSize = 48
    static let maximumPayloadSize: UInt32 = 1 * 1024 * 1024
    static let messageTypeOffset = 6
    static let headerSizeFieldOffset = 8
    static let payloadSizeOffset = 12
    static let sequenceOffset = 16
    static let timestampOffset = 24
    static let sampleRateOffset = 32
    static let channelCountOffset = 36
    static let sampleFormatOffset = 38
    static let frameCountOffset = 40
    static let readChunkSize = 1024 * 1024
    static let pcmSigned16LittleEndian: UInt16 = 1
    static let magic = Data([68, 72, 65, 68])
}
