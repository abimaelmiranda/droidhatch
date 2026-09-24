import Foundation

public enum AudioTransportError: Error, CustomStringConvertible, LocalizedError {
    case invalidMagic
    case unsupportedVersion(UInt16)
    case invalidHeaderSize(UInt32)
    case invalidMessageType(UInt16)
    case invalidSampleFormat(UInt16)
    case payloadTooLarge(UInt32)
    case invalidAudioPayload
    case connectionClosed
    case socketCreationFailed(Int32)
    case socketConnectionFailed(Int32)
    case invalidEndpoint
    case socketReadTimeout

    public var description: String {
        switch self {
        case .invalidMagic:
            return "Invalid audio protocol magic."
        case let .unsupportedVersion(version):
            return "Unsupported audio protocol version: \(version)."
        case let .invalidHeaderSize(size):
            return "Invalid audio protocol header size: \(size)."
        case let .invalidMessageType(type):
            return "Invalid audio message type: \(type)."
        case let .invalidSampleFormat(format):
            return "Unsupported audio sample format: \(format)."
        case let .payloadTooLarge(size):
            return "Audio payload exceeds the limit: \(size)."
        case .invalidAudioPayload:
            return "Audio payload does not match its frame count."
        case .connectionClosed:
            return "The audio agent closed the connection."
        case let .socketCreationFailed(error):
            return "Audio socket creation failed: errno \(error)."
        case let .socketConnectionFailed(error):
            return "Audio socket connection failed: errno \(error)."
        case .invalidEndpoint:
            return "The audio endpoint is incomplete."
        case .socketReadTimeout:
            return "Timed out waiting for audio data."
        }
    }

    public var errorDescription: String? {
        description
    }
}
