#pragma once

#include <cstddef>
#include <cstdint>

namespace droidhatch::input {

constexpr std::uint16_t kProtocolVersion = 1;
constexpr std::uint32_t kHeaderSize = 16;
constexpr std::uint32_t kMaximumPayloadSize = 1024;
constexpr std::uint32_t kNormalizedCoordinateMaximum = 1'000'000;

enum class MessageType : std::uint16_t {
    Hello = 1,
    Key = 2,
    Touch = 3,
    SystemAction = 4,
    Scroll = 5,
};

enum class KeyAction : std::uint8_t {
    Down = 1,
    Up = 2,
};

enum class TouchAction : std::uint8_t {
    Down = 1,
    Move = 2,
    Up = 3,
};

enum class SystemAction : std::uint8_t {
    Home = 1,
    Back = 2,
    VolumeUp = 4,
    VolumeDown = 5,
    PlayPause = 6,
};

enum class ScrollPhase : std::uint8_t {
    None = 0,
    Began = 1,
    Changed = 2,
    Ended = 4,
    Cancelled = 8,
};

enum class ScrollFlags : std::uint8_t {
    None = 0,
    Precise = 1,
    Momentum = 2,
    DirectionInverted = 4,
};

constexpr std::uint32_t kScrollFixedPointScale = 1'024;
constexpr std::uint32_t kHighResolutionScrollUnitsPerDetent = 120;
constexpr std::uint32_t kPreciseScrollPointsPerDetent = 32;

struct ScrollMessage {
    std::int32_t deltaX;
    std::int32_t deltaY;
    ScrollPhase phase;
    ScrollPhase momentumPhase;
    ScrollFlags flags;
    std::uint32_t sequence;
};

struct MessageHeader {
    MessageType type;
    std::uint32_t payloadSize;
};

bool readMessage(
    int fileDescriptor,
    MessageHeader* header,
    std::uint8_t* payload,
    std::size_t payloadCapacity);

bool sendHello(int fileDescriptor);

bool sendCapabilities(int fileDescriptor);

} // namespace droidhatch::input
