import Foundation

public enum FrameTransportError: Error, CustomStringConvertible, LocalizedError {
    case invalidMagic
    case unsupportedVersion(UInt16)
    case invalidHeaderSize(UInt32)
    case invalidMessageType(UInt16)
    case payloadTooLarge(UInt32)
    case invalidTextPayload
    case truncated
    case socketCreationFailed(Int32)
    case socketConnectionFailed(Int32)
    case socketReadTimeout
    case pngEncodingFailed

    public var description: String {
        switch self {
        case .invalidMagic:
            return "Invalid frame protocol magic."
        case let .unsupportedVersion(version):
            return "Unsupported protocol version: \(version)."
        case let .invalidHeaderSize(size):
            return "Invalid header size: \(size)."
        case let .invalidMessageType(type):
            return "Invalid message type: \(type)."
        case let .payloadTooLarge(size):
            return "Frame payload exceeds the limit: \(size)."
        case .invalidTextPayload:
            return "Frame agent returned a non-UTF-8 text payload."
        case .truncated:
            return "Connection closed before the message was complete."
        case let .socketCreationFailed(error):
            return "Socket creation failed: errno \(error)."
        case let .socketConnectionFailed(error):
            return "Socket connection failed: errno \(error)."
        case .socketReadTimeout:
            return "Timed out waiting for the next frame."
        case .pngEncodingFailed:
            return "Could not encode the frame as PNG."
        }
    }

    public var errorDescription: String? {
        description
    }
}
