import Foundation

public enum InputTransportError: Error, CustomStringConvertible, LocalizedError {
    case invalidMagic
    case unsupportedVersion(UInt16)
    case invalidHeaderSize(UInt32)
    case invalidMessageType(UInt16)
    case payloadTooLarge(UInt32)
    case capabilityRejected
    case socketCreationFailed(Int32)
    case socketConnectionFailed(Int32)
    case socketReadTimeout
    case connectionClosed
    case writeFailed(Int32)

    public var description: String {
        switch self {
        case .invalidMagic:
            return "Invalid input protocol magic."
        case let .unsupportedVersion(version):
            return "Unsupported input protocol version: \(version)."
        case let .invalidHeaderSize(size):
            return "Invalid input protocol header size: \(size)."
        case let .invalidMessageType(type):
            return "Invalid input message type: \(type)."
        case let .payloadTooLarge(size):
            return "Input payload exceeds the limit: \(size)."
        case .capabilityRejected:
            return "The input agent did not advertise the required uinput capabilities."
        case let .socketCreationFailed(error):
            return "Input socket creation failed: errno \(error)."
        case let .socketConnectionFailed(error):
            return "Input socket connection failed: errno \(error)."
        case .socketReadTimeout:
            return "Timed out waiting for the input agent."
        case .connectionClosed:
            return "The input agent closed the connection."
        case let .writeFailed(error):
            return "Writing to the input agent failed: errno \(error)."
        }
    }

    public var errorDescription: String? {
        description
    }
}
