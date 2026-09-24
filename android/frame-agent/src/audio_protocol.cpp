#include "audio_protocol.h"

#include <cstring>

#include "agent_io.h"
#include "wire_codec.h"

namespace droidhatch::audio {
namespace {

constexpr std::uint8_t kMagic[4] = {'D', 'H', 'A', 'D'};

} // namespace

bool sendMessage(
    int fileDescriptor,
    MessageType type,
    const Metadata& metadata,
    const std::uint8_t* payload,
    std::size_t payloadSize) {
    if (payloadSize > kMaximumPayloadSize) {
        return false;
    }

    std::uint8_t header[kHeaderSize] = {};
    std::memcpy(header, kMagic, sizeof(kMagic));
    wire::write16(header + 4, kProtocolVersion);
    wire::write16(header + 6, static_cast<std::uint16_t>(type));
    wire::write32(header + 8, kHeaderSize);
    wire::write32(header + 12, static_cast<std::uint32_t>(payloadSize));
    wire::write64(header + 16, metadata.sequence);
    wire::write64(header + 24, metadata.timestampNanoseconds);
    wire::write32(header + 32, metadata.sampleRate);
    wire::write16(header + 36, metadata.channelCount);
    wire::write16(header + 38, metadata.sampleFormat);
    wire::write32(header + 40, metadata.frameCount);

    if (!agent::writeAll(fileDescriptor, header, sizeof(header))) {
        return false;
    }
    return payloadSize == 0 || agent::writeAll(fileDescriptor, payload, payloadSize);
}

bool readMessage(int fileDescriptor, Message* message) {
    if (message == nullptr) {
        return false;
    }

    std::uint8_t header[kHeaderSize] = {};
    if (!agent::readAll(fileDescriptor, header, sizeof(header))) {
        return false;
    }
    if (std::memcmp(header, kMagic, sizeof(kMagic)) != 0
        || wire::read16(header + 4) != kProtocolVersion
        || wire::read32(header + 8) != kHeaderSize) {
        return false;
    }

    const auto payloadSize = wire::read32(header + 12);
    if (payloadSize > kMaximumPayloadSize) {
        return false;
    }

    message->type = static_cast<MessageType>(wire::read16(header + 6));
    message->metadata.sequence = wire::read64(header + 16);
    message->metadata.timestampNanoseconds = wire::read64(header + 24);
    message->metadata.sampleRate = wire::read32(header + 32);
    message->metadata.channelCount = wire::read16(header + 36);
    message->metadata.sampleFormat = wire::read16(header + 38);
    message->metadata.frameCount = wire::read32(header + 40);
    message->payload.resize(payloadSize);
    if (payloadSize > 0
        && !agent::readAll(fileDescriptor, message->payload.data(), payloadSize)) {
        return false;
    }

    message->wire.resize(kHeaderSize + payloadSize);
    std::memcpy(message->wire.data(), header, kHeaderSize);
    if (payloadSize > 0) {
        std::memcpy(message->wire.data() + kHeaderSize, message->payload.data(), payloadSize);
    }
    return true;
}

} // namespace droidhatch::audio
