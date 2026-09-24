#include "frame_protocol.h"

#include <cstring>

#include "agent_io.h"
#include "wire_codec.h"

namespace droidhatch {
namespace {

constexpr std::uint8_t kMagic[4] = {'D', 'H', 'F', 'R'};

bool sendMessage(
    int fileDescriptor,
    MessageType messageType,
    const FrameMetadata* metadata,
    const std::uint8_t* payload,
    std::size_t payloadBytes) {
    if (payloadBytes > UINT32_MAX) {
        return false;
    }

    std::uint8_t header[kHeaderSize] = {};
    std::memcpy(header, kMagic, sizeof(kMagic));
    wire::write16(header + 4, kProtocolVersion);
    wire::write16(header + 6, static_cast<std::uint16_t>(messageType));
    wire::write32(header + 8, kHeaderSize);
    wire::write32(header + 12, static_cast<std::uint32_t>(payloadBytes));

    if (metadata != nullptr) {
        wire::write64(header + 16, metadata->sequence);
        wire::write64(header + 24, metadata->timestampNs);
        wire::write32(header + 32, metadata->width);
        wire::write32(header + 36, metadata->height);
        wire::write32(header + 40, metadata->strideBytes);
        wire::write32(header + 44, metadata->pixelFormat);
    }

    if (!agent::writeAll(fileDescriptor, header, sizeof(header))) {
        return false;
    }

    return payloadBytes == 0 || agent::writeAll(fileDescriptor, payload, payloadBytes);
}

} // namespace

bool sendFrame(
    int fileDescriptor,
    const FrameMetadata& metadata,
    const std::uint8_t* pixels,
    std::size_t pixelBytes) {
    return sendMessage(
        fileDescriptor,
        MessageType::Frame,
        &metadata,
        pixels,
        pixelBytes);
}

bool sendHello(int fileDescriptor) {
    return sendMessage(fileDescriptor, MessageType::Hello, nullptr, nullptr, 0);
}

bool sendError(int fileDescriptor, const char* message) {
    if (message == nullptr) {
        return false;
    }

    const auto* payload = reinterpret_cast<const std::uint8_t*>(message);
    return sendMessage(
        fileDescriptor,
        MessageType::Error,
        nullptr,
        payload,
        std::strlen(message));
}

bool sendStatus(int fileDescriptor, const char* message) {
    if (message == nullptr) {
        return false;
    }

    const auto* payload = reinterpret_cast<const std::uint8_t*>(message);
    return sendMessage(
        fileDescriptor,
        MessageType::Status,
        nullptr,
        payload,
        std::strlen(message));
}

} // namespace droidhatch
