#pragma once

#include <cstddef>
#include <cstdint>

namespace droidhatch::wire {

inline std::uint16_t read16(const std::uint8_t* source) {
    return static_cast<std::uint16_t>(source[0])
        | static_cast<std::uint16_t>(source[1]) << 8;
}

inline std::uint32_t read32(const std::uint8_t* source) {
    return static_cast<std::uint32_t>(source[0])
        | static_cast<std::uint32_t>(source[1]) << 8
        | static_cast<std::uint32_t>(source[2]) << 16
        | static_cast<std::uint32_t>(source[3]) << 24;
}

inline std::uint64_t read64(const std::uint8_t* source) {
    std::uint64_t value = 0;
    for (std::size_t index = 0; index < sizeof(std::uint64_t); ++index) {
        value |= static_cast<std::uint64_t>(source[index]) << (index * 8);
    }
    return value;
}

inline void write16(std::uint8_t* destination, std::uint16_t value) {
    destination[0] = static_cast<std::uint8_t>(value);
    destination[1] = static_cast<std::uint8_t>(value >> 8);
}

inline void write32(std::uint8_t* destination, std::uint32_t value) {
    destination[0] = static_cast<std::uint8_t>(value);
    destination[1] = static_cast<std::uint8_t>(value >> 8);
    destination[2] = static_cast<std::uint8_t>(value >> 16);
    destination[3] = static_cast<std::uint8_t>(value >> 24);
}

inline void write64(std::uint8_t* destination, std::uint64_t value) {
    for (std::size_t index = 0; index < sizeof(std::uint64_t); ++index) {
        destination[index] = static_cast<std::uint8_t>(value >> (index * 8));
    }
}

} // namespace droidhatch::wire
