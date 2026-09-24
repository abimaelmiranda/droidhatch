import Darwin
import Foundation

public final class FrameConnection: @unchecked Sendable {
    private let fileHandle: FileHandle
    private let socketDescriptor: Int32
    private let readTimeoutMilliseconds: Int32

    public init(host: String, port: UInt16, readTimeoutSeconds: Double = 30) throws {
        guard readTimeoutSeconds > 0, readTimeoutSeconds.isFinite else {
            throw FrameTransportError.socketReadTimeout
        }

        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else {
            throw FrameTransportError.socketCreationFailed(errno)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        let result = host.withCString { pointer in
            inet_pton(AF_INET, pointer, &address.sin_addr)
        }
        guard result == 1 else {
            Darwin.close(socket)
            throw FrameTransportError.socketConnectionFailed(EINVAL)
        }

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                Darwin.connect(socket, rebound, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else {
            let error = errno
            Darwin.close(socket)
            throw FrameTransportError.socketConnectionFailed(error)
        }

        fileHandle = FileHandle(fileDescriptor: socket, closeOnDealloc: true)
        socketDescriptor = socket
        readTimeoutMilliseconds = Int32(min(readTimeoutSeconds * 1_000, Double(Int32.max)))
    }

    deinit {
        try? fileHandle.close()
    }

    public func readMessage() throws -> FrameMessage {
        let headerData = try readExactly(FrameProtocolConstants.headerSize)
        guard headerData.prefix(4) == FrameProtocolConstants.magic else {
            throw FrameTransportError.invalidMagic
        }

        let version = headerData.readUInt16(at: 4)
        guard version == FrameProtocolConstants.version else {
            throw FrameTransportError.unsupportedVersion(version)
        }

        let messageTypeValue = headerData.readUInt16(
            at: FrameProtocolConstants.messageTypeOffset)
        guard let messageType = FrameMessageType(rawValue: messageTypeValue) else {
            throw FrameTransportError.invalidMessageType(messageTypeValue)
        }

        let headerSize = headerData.readUInt32(
            at: FrameProtocolConstants.headerSizeFieldOffset)
        guard headerSize == FrameProtocolConstants.headerSize else {
            throw FrameTransportError.invalidHeaderSize(headerSize)
        }

        let payloadSize = headerData.readUInt32(
            at: FrameProtocolConstants.payloadSizeOffset)
        guard payloadSize <= FrameProtocolConstants.maximumPayloadSize else {
            throw FrameTransportError.payloadTooLarge(payloadSize)
        }

        let header = FrameHeader(
            messageType: messageType,
            sequence: headerData.readUInt64(at: FrameProtocolConstants.sequenceOffset),
            timestampNanoseconds: headerData.readUInt64(
                at: FrameProtocolConstants.timestampOffset),
            width: headerData.readUInt32(at: FrameProtocolConstants.widthOffset),
            height: headerData.readUInt32(at: FrameProtocolConstants.heightOffset),
            strideBytes: headerData.readUInt32(at: FrameProtocolConstants.strideOffset),
            pixelFormat: headerData.readUInt32(at: FrameProtocolConstants.pixelFormatOffset),
            payloadSize: payloadSize)
        let payload = try readExactly(Int(payloadSize))

        switch messageType {
        case .hello:
            return .hello
        case .frame:
            return .frame(header, payload)
        case .error:
            return .error(header, try decodeText(payload))
        case .status:
            return .status(header, try decodeText(payload))
        }
    }

    private func decodeText(_ payload: Data) throws -> String {
        guard let message = String(data: payload, encoding: .utf8) else {
            throw FrameTransportError.invalidTextPayload
        }
        return message
    }

    private func readExactly(_ count: Int) throws -> Data {
        var result = Data()
        result.reserveCapacity(count)
        var buffer = [UInt8](
            repeating: 0,
            count: min(count, FrameProtocolConstants.readChunkSize))

        while result.count < count {
            let remaining = count - result.count
            var descriptor = pollfd(
                fd: socketDescriptor,
                events: Int16(POLLIN),
                revents: 0)
            let pollResult = Darwin.poll(
                &descriptor,
                1,
                readTimeoutMilliseconds)
            if pollResult == 0 {
                throw FrameTransportError.socketReadTimeout
            }
            if pollResult < 0 {
                if errno == EINTR {
                    continue
                }
                throw FrameTransportError.truncated
            }

            if descriptor.revents & Int16(POLLIN) == 0 {
                throw FrameTransportError.truncated
            }

            let bytesToRead = min(remaining, buffer.count)
            let bytesRead = buffer.withUnsafeMutableBytes { storage in
                Darwin.read(socketDescriptor, storage.baseAddress, bytesToRead)
            }
            if bytesRead < 0 {
                if errno == EINTR {
                    continue
                }
                throw FrameTransportError.truncated
            }
            guard bytesRead > 0 else {
                throw FrameTransportError.truncated
            }
            result.append(contentsOf: buffer.prefix(bytesRead))
        }

        return result
    }
}
