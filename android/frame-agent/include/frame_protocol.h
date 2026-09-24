#pragma once

#include <cstddef>
#include <cstdint>

namespace droidhatch {

constexpr std::uint16_t kProtocolVersion = 1;
constexpr std::uint32_t kHeaderSize = 48;
constexpr std::uint32_t kPixelFormatRgba8888 = 1;

enum class MessageType : std::uint16_t {
    Hello = 1,
    Frame = 2,
    Error = 3,
    Status = 4,
};

struct FrameMetadata {
    std::uint64_t sequence;
    std::uint64_t timestampNs;
    std::uint32_t width;
    std::uint32_t height;
    std::uint32_t strideBytes;
    std::uint32_t pixelFormat;
};

bool sendFrame(
    int fileDescriptor,
    const FrameMetadata& metadata,
    const std::uint8_t* pixels,
    std::size_t pixelBytes);

bool sendHello(int fileDescriptor);

bool sendError(int fileDescriptor, const char* message);

bool sendStatus(int fileDescriptor, const char* message);

} // namespace droidhatch
