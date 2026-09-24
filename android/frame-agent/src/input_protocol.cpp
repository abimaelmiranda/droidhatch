#include "input_protocol.h"

#include <cstring>

#include "agent_io.h"
#include "wire_codec.h"

namespace droidhatch::input {
namespace {

constexpr std::uint8_t kMagic[4] = {'D', 'H', 'I', 'N'};

bool sendMessage(
    int fileDescriptor,
    MessageType type,
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

    if (!agent::writeAll(fileDescriptor, header, sizeof(header))) {
        return false;
    }

    return payloadSize == 0 || agent::writeAll(fileDescriptor, payload, payloadSize);
}

} // namespace

bool readMessage(
    int fileDescriptor,
    MessageHeader* header,
    std::uint8_t* payload,
    std::size_t payloadCapacity) {
    if (header == nullptr || payload == nullptr) {
        return false;
    }

    std::uint8_t rawHeader[kHeaderSize] = {};
    if (!agent::readAll(fileDescriptor, rawHeader, sizeof(rawHeader))) {
        return false;
    }

    if (std::memcmp(rawHeader, kMagic, sizeof(kMagic)) != 0
        || wire::read16(rawHeader + 4) != kProtocolVersion
        || wire::read32(rawHeader + 8) != kHeaderSize) {
        return false;
    }

    const std::uint32_t payloadSize = wire::read32(rawHeader + 12);
    if (payloadSize > kMaximumPayloadSize || payloadSize > payloadCapacity) {
        return false;
    }

    header->type = static_cast<MessageType>(wire::read16(rawHeader + 6));
    header->payloadSize = payloadSize;
    return payloadSize == 0 || agent::readAll(fileDescriptor, payload, payloadSize);
}

bool sendHello(int fileDescriptor) {
    return sendMessage(fileDescriptor, MessageType::Hello, nullptr, 0);
}

bool sendCapabilities(int fileDescriptor) {
    constexpr char capabilities[] = "uinput keyboard touchscreen scroll";
    return sendMessage(
        fileDescriptor,
        MessageType::Hello,
        reinterpret_cast<const std::uint8_t*>(capabilities),
        sizeof(capabilities) - 1);
}

} // namespace droidhatch::input
