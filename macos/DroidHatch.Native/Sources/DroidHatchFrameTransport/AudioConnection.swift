import Darwin
import Foundation

public final class AudioConnection: @unchecked Sendable {
    private let socketDescriptor: Int32
    private let readTimeoutMilliseconds: Int32

    public init(
        unixSocketPath: String,
        readTimeoutSeconds: Double = 5) throws {
        guard readTimeoutSeconds > 0, readTimeoutSeconds.isFinite else {
            throw AudioTransportError.socketReadTimeout
        }

        let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else {
            throw AudioTransportError.socketCreationFailed(errno)
        }

        guard unixSocketPath.hasPrefix("/"),
              unixSocketPath.utf8.count < MemoryLayout<sockaddr_un>.size - MemoryLayout<sa_family_t>.size else {
            Darwin.close(socket)
            throw AudioTransportError.invalidEndpoint
        }

        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        unixSocketPath.withCString { pointer in
            withUnsafeMutableBytes(of: &address.sun_path) { storage in
                storage.copyBytes(
                    from: UnsafeRawBufferPointer(
                        start: pointer,
                        count: unixSocketPath.utf8.count + 1))
            }
        }

        let connectionResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                Darwin.connect(
                    socket,
                    rebound,
                    socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectionResult == 0 else {
            let error = errno
            Darwin.close(socket)
            throw AudioTransportError.socketConnectionFailed(error)
        }

        socketDescriptor = socket
        readTimeoutMilliseconds = Int32(min(readTimeoutSeconds * 1_000, Double(Int32.max)))
    }

    deinit {
        Darwin.close(socketDescriptor)
    }

    public func readMessage() throws -> AudioMessage {
        let header = try readExactly(AudioProtocolConstants.headerSize)
        guard header.prefix(4) == AudioProtocolConstants.magic else {
            throw AudioTransportError.invalidMagic
        }

        let version = header.audioReadUInt16(at: 4)
        guard version == AudioProtocolConstants.version else {
            throw AudioTransportError.unsupportedVersion(version)
        }

        let rawMessageType = header.audioReadUInt16(
            at: AudioProtocolConstants.messageTypeOffset)
        guard let messageType = AudioMessageType(rawValue: rawMessageType) else {
            throw AudioTransportError.invalidMessageType(rawMessageType)
        }

        let headerSize = header.audioReadUInt32(
            at: AudioProtocolConstants.headerSizeFieldOffset)
        guard headerSize == AudioProtocolConstants.headerSize else {
            throw AudioTransportError.invalidHeaderSize(headerSize)
        }

        let payloadSize = header.audioReadUInt32(
            at: AudioProtocolConstants.payloadSizeOffset)
        guard payloadSize <= AudioProtocolConstants.maximumPayloadSize else {
            throw AudioTransportError.payloadTooLarge(payloadSize)
        }

        let sequence = header.audioReadUInt64(at: AudioProtocolConstants.sequenceOffset)
        let timestampNanoseconds = header.audioReadUInt64(
            at: AudioProtocolConstants.timestampOffset)
        let sampleRate = header.audioReadUInt32(
            at: AudioProtocolConstants.sampleRateOffset)
        let channelCount = header.audioReadUInt16(
            at: AudioProtocolConstants.channelCountOffset)
        let rawSampleFormat = header.audioReadUInt16(
            at: AudioProtocolConstants.sampleFormatOffset)
        let frameCount = header.audioReadUInt32(
            at: AudioProtocolConstants.frameCountOffset)
        let payload = try readExactly(Int(payloadSize))

        switch messageType {
        case .hello:
            return .hello
        case .format:
            return .format(try descriptor(
                sampleRate: sampleRate,
                channelCount: channelCount,
                rawSampleFormat: rawSampleFormat))
        case .audio:
            let descriptor = try descriptor(
                sampleRate: sampleRate,
                channelCount: channelCount,
                rawSampleFormat: rawSampleFormat)
            let expectedBytes = Int(frameCount) * Int(channelCount) * MemoryLayout<Int16>.size
            guard payload.count == expectedBytes else {
                throw AudioTransportError.invalidAudioPayload
            }
            return .audio(AudioPacket(
                sequence: sequence,
                timestampNanoseconds: timestampNanoseconds,
                descriptor: descriptor,
                frameCount: frameCount,
                payload: payload))
        case .status:
            guard let text = String(data: payload, encoding: .utf8) else {
                throw AudioTransportError.invalidAudioPayload
            }
            return .status(text)
        case .error:
            guard let text = String(data: payload, encoding: .utf8) else {
                throw AudioTransportError.invalidAudioPayload
            }
            return .error(text)
        case .end:
            return .end
        }
    }

    private func descriptor(
        sampleRate: UInt32,
        channelCount: UInt16,
        rawSampleFormat: UInt16) throws -> AudioStreamDescriptor {
        guard let sampleFormat = AudioSampleFormat(rawValue: rawSampleFormat) else {
            throw AudioTransportError.invalidSampleFormat(rawSampleFormat)
        }
        return AudioStreamDescriptor(
            sampleRate: sampleRate,
            channelCount: channelCount,
            sampleFormat: sampleFormat)
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
                throw AudioTransportError.socketReadTimeout
            }
            if pollResult < 0 {
                if errno == EINTR {
                    continue
                }
                throw AudioTransportError.connectionClosed
            }
            guard descriptor.revents & Int16(POLLIN) != 0 else {
                throw AudioTransportError.connectionClosed
            }

            let remaining = count - result.count
            let readSize = min(remaining, buffer.count)
            let bytesRead = buffer.withUnsafeMutableBytes { storage in
                Darwin.read(socketDescriptor, storage.baseAddress, readSize)
            }
            if bytesRead < 0, errno == EINTR {
                continue
            }
            guard bytesRead > 0 else {
                throw AudioTransportError.connectionClosed
            }
            result.append(contentsOf: buffer.prefix(bytesRead))
        }

        return result
    }
}

private extension Data {
    func audioReadUInt16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func audioReadUInt32(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }

    func audioReadUInt64(at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(self[offset + index]) << (index * 8)
        }
        return value
    }
}
