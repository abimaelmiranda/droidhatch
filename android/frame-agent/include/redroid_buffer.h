#pragma once

#include <array>
#include <cstdint>
#include <vector>

namespace droidhatch::agent {

struct RedroidBufferHandle {
    std::uint32_t version;
    std::uint32_t fdCount;
    std::uint32_t intCount;
    std::uint32_t descriptor;
    std::uint32_t magic;
    std::uint32_t reserved0;
    std::uint32_t bufferSize;
    std::uint32_t reserved1;
    std::uint64_t baseAddress;
    std::uint32_t usage;
    std::uint32_t width;
    std::uint32_t height;
    std::uint32_t format;
    std::uint32_t stride;
    std::uint32_t reserved2;
};

static_assert(sizeof(RedroidBufferHandle) == 64);

bool receiveRedroidFrame(
    int socketFd,
    bool acceptUnknownMarkers,
    RedroidBufferHandle* handle,
    int* descriptor);

bool copyRedroidPixels(
    int descriptor,
    const RedroidBufferHandle& handle,
    std::vector<std::uint8_t>* pixels,
    std::uint32_t* strideBytes);

} // namespace droidhatch::agent
