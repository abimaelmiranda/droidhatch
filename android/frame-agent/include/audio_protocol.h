#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace droidhatch::audio {

constexpr std::uint16_t kProtocolVersion = 1;
constexpr std::uint32_t kHeaderSize = 48;
constexpr std::uint32_t kMaximumPayloadSize = 1024 * 1024;
constexpr std::uint16_t kPcmSigned16LittleEndian = 1;

enum class MessageType : std::uint16_t {
    Hello = 1,
    Format = 2,
    Audio = 3,
    Status = 4,
    Error = 5,
    End = 6,
};

struct Metadata {
    std::uint64_t sequence = 0;
    std::uint64_t timestampNanoseconds = 0;
    std::uint32_t sampleRate = 0;
    std::uint16_t channelCount = 0;
    std::uint16_t sampleFormat = 0;
    std::uint32_t frameCount = 0;
};

struct Message {
    MessageType type;
    Metadata metadata;
    std::vector<std::uint8_t> payload;
    std::vector<std::uint8_t> wire;
};

bool sendMessage(
    int fileDescriptor,
    MessageType type,
    const Metadata& metadata,
    const std::uint8_t* payload,
    std::size_t payloadSize);

bool readMessage(int fileDescriptor, Message* message);

} // namespace droidhatch::audio
