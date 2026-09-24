import Darwin
import Foundation

public final class InputConnection: @unchecked Sendable {
    private let socketDescriptor: Int32
    private let writeLock = NSLock()
    private let readTimeoutMilliseconds: Int32
    private var supportsScrollCapability = false

    public var supportsScroll: Bool {
        supportsScrollCapability
    }

    public init(host: String, port: UInt16, readTimeoutSeconds: Double = 5) throws {
        guard readTimeoutSeconds > 0, readTimeoutSeconds.isFinite else {
            throw InputTransportError.socketReadTimeout
        }

        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else {
            throw InputTransportError.socketCreationFailed(errno)
        }

        // A backend restart invalidates the accepted TCP connection. On macOS,
        // writing to that stale descriptor raises SIGPIPE before send() can
        // return EPIPE, which used to terminate the entire viewer. Keep the
        // failure local to this transport so the viewer can reconnect.
        var noSigPipe: Int32 = 1
        guard setsockopt(
            socket,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            let error = errno
            Darwin.close(socket)
            throw InputTransportError.socketCreationFailed(error)
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
            throw InputTransportError.socketConnectionFailed(EINVAL)
        }

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                Darwin.connect(socket, rebound, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else {
            let error = errno
            Darwin.close(socket)
            throw InputTransportError.socketConnectionFailed(error)
        }

        socketDescriptor = socket
        readTimeoutMilliseconds = Int32(min(readTimeoutSeconds * 1_000, Double(Int32.max)))

        try send(messageType: .hello, payload: Data())
        supportsScrollCapability = try readCapabilities()
    }

    deinit {
        Darwin.close(socketDescriptor)
    }

    public func sendKey(usage: UInt16, action: InputKeyAction) throws {
        var payload = Data()
        payload.appendLittleEndian(usage)
        payload.append(action.rawValue)
        payload.append(0)
        try send(messageType: .key, payload: payload)
    }

    public func sendTouch(
        pointerId: UInt32,
        action: InputTouchAction,
        normalizedX: UInt32,
        normalizedY: UInt32) throws {
        var payload = Data()
        payload.appendLittleEndian(pointerId)
        payload.append(action.rawValue)
        payload.append(contentsOf: [0, 0, 0])
        payload.appendLittleEndian(normalizedX)
        payload.appendLittleEndian(normalizedY)
        try send(messageType: .touch, payload: payload)
    }

    public func sendSystemAction(_ action: InputSystemAction) throws {
        var payload = Data(repeating: 0, count: 4)
        payload[0] = action.rawValue
        try send(messageType: .systemAction, payload: payload)
    }

    public func sendScroll(
        deltaX: Int32,
        deltaY: Int32,
        phase: InputScrollPhase,
        momentumPhase: InputScrollPhase,
        flags: InputScrollFlags,
        sequence: UInt32) throws {
        var payload = Data()
        payload.appendLittleEndian(deltaX)
        payload.appendLittleEndian(deltaY)
        payload.append(phase.rawValue)
        payload.append(momentumPhase.rawValue)
        payload.append(flags.rawValue)
        payload.append(0)
        payload.appendLittleEndian(sequence)
        try send(messageType: .scroll, payload: payload)
    }

    private func readCapabilities() throws -> Bool {
        let header = try readExactly(InputProtocolConstants.headerSize)
        guard header.prefix(4) == InputProtocolConstants.magic else {
            throw InputTransportError.invalidMagic
        }

        let version = header.readUInt16(at: 4)
        guard version == InputProtocolConstants.version else {
            throw InputTransportError.unsupportedVersion(version)
        }

        let messageType = header.readUInt16(
            at: InputProtocolConstants.messageTypeOffset)
        guard messageType == InputMessageType.hello.rawValue else {
            throw InputTransportError.invalidMessageType(messageType)
        }

        let headerSize = header.readUInt32(
            at: InputProtocolConstants.headerSizeFieldOffset)
        guard headerSize == InputProtocolConstants.headerSize else {
            throw InputTransportError.invalidHeaderSize(headerSize)
        }

        let payloadSize = header.readUInt32(
            at: InputProtocolConstants.payloadSizeOffset)
        guard payloadSize <= InputProtocolConstants.maximumPayloadSize else {
            throw InputTransportError.payloadTooLarge(payloadSize)
        }

        let capabilitiesData = try readExactly(Int(payloadSize))
        guard let capabilities = String(data: capabilitiesData, encoding: .utf8) else {
            throw InputTransportError.capabilityRejected
        }
        guard capabilities.contains("uinput") else {
            throw InputTransportError.capabilityRejected
        }
        return capabilities.contains("scroll")
    }

    private func send(messageType: InputMessageType, payload: Data) throws {
        guard payload.count <= Int(InputProtocolConstants.maximumPayloadSize) else {
            throw InputTransportError.payloadTooLarge(UInt32(payload.count))
        }

        var header = Data()
        header.append(contentsOf: InputProtocolConstants.magic)
        header.appendLittleEndian(InputProtocolConstants.version)
        header.appendLittleEndian(messageType.rawValue)
        header.appendLittleEndian(UInt32(InputProtocolConstants.headerSize))
        header.appendLittleEndian(UInt32(payload.count))

        writeLock.lock()
        defer { writeLock.unlock() }
        try writeAll(header)
        try writeAll(payload)
    }

    private func writeAll(_ data: Data) throws {
        guard !data.isEmpty else {
            return
        }

        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                throw InputTransportError.writeFailed(EINVAL)
            }

            var offset = 0
            while offset < data.count {
                let written = Darwin.send(
                    socketDescriptor,
                    baseAddress.advanced(by: offset),
                    data.count - offset,
                    0)
                if written > 0 {
                    offset += written
                    continue
                }
                if written < 0, errno == EINTR {
                    continue
                }
                throw InputTransportError.writeFailed(errno)
            }
        }
    }

    private func readExactly(_ count: Int) throws -> Data {
        var result = Data()
        result.reserveCapacity(count)
        var buffer = [UInt8](repeating: 0, count: max(count, 1))

        while result.count < count {
            var descriptor = pollfd(
                fd: socketDescriptor,
                events: Int16(POLLIN),
                revents: 0)
            let pollResult = Darwin.poll(&descriptor, 1, readTimeoutMilliseconds)
            if pollResult == 0 {
                throw InputTransportError.socketReadTimeout
            }
            if pollResult < 0 {
                if errno == EINTR {
                    continue
                }
                throw InputTransportError.connectionClosed
            }
            if descriptor.revents & Int16(POLLIN) == 0 {
                throw InputTransportError.connectionClosed
            }

            let remaining = count - result.count
            let bufferCapacity = buffer.count
            let bytesRead = buffer.withUnsafeMutableBytes { storage in
                Darwin.read(socketDescriptor, storage.baseAddress, min(remaining, bufferCapacity))
            }
            if bytesRead < 0, errno == EINTR {
                continue
            }
            guard bytesRead > 0 else {
                throw InputTransportError.connectionClosed
            }
            result.append(contentsOf: buffer.prefix(bytesRead))
        }

        return result
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }

    mutating func appendLittleEndian(_ value: Int32) {
        appendLittleEndian(UInt32(bitPattern: value))
    }
}
