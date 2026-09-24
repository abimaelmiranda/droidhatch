#include "redroid_buffer.h"

#include "agent_resources.h"

#include <array>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

namespace droidhatch::agent {
namespace {

constexpr std::size_t kRgbaBytesPerPixel = 4;
constexpr std::uint32_t kPixelFormatRgba8888 = 1;
constexpr std::uint32_t kPixelFormatYv12 = 0x32315659u;

std::size_t alignTo(std::size_t value, std::size_t alignment) {
    return ((value + alignment - 1) / alignment) * alignment;
}

std::uint64_t sourceBufferBytes(const RedroidBufferHandle& handle) {
    if (handle.format == kPixelFormatRgba8888) {
        return static_cast<std::uint64_t>(handle.stride)
            * kRgbaBytesPerPixel * handle.height;
    }

    if (handle.format == kPixelFormatYv12) {
        const std::uint64_t yStride = handle.stride;
        const std::uint64_t chromaStride = alignTo(yStride / 2, 16);
        const std::uint64_t chromaHeight = (handle.height + 1) / 2;
        return yStride * handle.height + chromaStride * chromaHeight * 2;
    }

    return 0;
}

std::uint32_t readLittleEndian32(const std::uint8_t* data) {
    return static_cast<std::uint32_t>(data[0])
        | static_cast<std::uint32_t>(data[1]) << 8
        | static_cast<std::uint32_t>(data[2]) << 16
        | static_cast<std::uint32_t>(data[3]) << 24;
}

std::uint64_t readLittleEndian64(const std::uint8_t* data) {
    std::uint64_t value = 0;
    for (std::size_t index = 0; index < sizeof(std::uint64_t); ++index) {
        value |= static_cast<std::uint64_t>(data[index]) << (index * 8);
    }
    return value;
}

RedroidBufferHandle decodeBufferHandle(const std::array<std::uint8_t, 64>& data) {
    RedroidBufferHandle handle = {};
    handle.version = readLittleEndian32(data.data());
    handle.fdCount = readLittleEndian32(data.data() + 4);
    handle.intCount = readLittleEndian32(data.data() + 8);
    handle.descriptor = readLittleEndian32(data.data() + 12);
    handle.magic = readLittleEndian32(data.data() + 16);
    handle.reserved0 = readLittleEndian32(data.data() + 20);
    handle.bufferSize = readLittleEndian32(data.data() + 24);
    handle.reserved1 = readLittleEndian32(data.data() + 28);
    handle.baseAddress = readLittleEndian64(data.data() + 32);
    handle.usage = readLittleEndian32(data.data() + 40);
    handle.width = readLittleEndian32(data.data() + 44);
    handle.height = readLittleEndian32(data.data() + 48);
    handle.format = readLittleEndian32(data.data() + 52);
    handle.stride = readLittleEndian32(data.data() + 56);
    handle.reserved2 = readLittleEndian32(data.data() + 60);
    return handle;
}

bool receiveDescriptor(msghdr& message, int* descriptor) {
    if (descriptor == nullptr) {
        return false;
    }

    *descriptor = -1;
    for (cmsghdr* header = CMSG_FIRSTHDR(&message);
         header != nullptr;
         header = CMSG_NXTHDR(&message, header)) {
        if (header->cmsg_level != SOL_SOCKET || header->cmsg_type != SCM_RIGHTS) {
            continue;
        }

        if (header->cmsg_len < CMSG_LEN(sizeof(int))) {
            continue;
        }

        const std::size_t payloadBytes = header->cmsg_len - CMSG_LEN(0);
        const std::size_t descriptorCount = payloadBytes / sizeof(int);
        const auto* descriptors = reinterpret_cast<const int*>(CMSG_DATA(header));
        if (descriptorCount == 0) {
            continue;
        }

        agent::UniqueFd primaryDescriptor(descriptors[0]);
        for (std::size_t index = 1; index < descriptorCount; ++index) {
            agent::UniqueFd extraDescriptor(descriptors[index]);
        }
        *descriptor = primaryDescriptor.release();
        return true;
    }

    return false;
}

} // namespace

bool receiveRedroidFrame(
    int socketFd,
    bool acceptUnknownMarkers,
    RedroidBufferHandle* handle,
    int* descriptor) {
    if (handle == nullptr || descriptor == nullptr) {
        return false;
    }

    std::array<std::uint8_t, sizeof(RedroidBufferHandle)> data = {};
    std::size_t receivedBytes = 0;
    while (receivedBytes < data.size()) {
        const ssize_t received = recv(
            socketFd,
            data.data() + receivedBytes,
            data.size() - receivedBytes,
            0);
        if (received > 0) {
            receivedBytes += static_cast<std::size_t>(received);
            continue;
        }
        if (received < 0 && errno == EINTR) {
            continue;
        }

        std::fprintf(
            stderr,
            "droidhatch-frame-agent: HWC metadata recv failed: %s\n",
            received < 0 ? std::strerror(errno) : "socket closed");
        return false;
    }

    std::array<std::uint8_t, 1> marker = {};
    std::array<std::uint8_t, CMSG_SPACE(sizeof(int) * 4)> control = {};
    iovec vector = {marker.data(), marker.size()};
    msghdr message = {};
    message.msg_iov = &vector;
    message.msg_iovlen = 1;
    message.msg_control = control.data();
    message.msg_controllen = control.size();

    while (true) {
        const ssize_t received = recvmsg(socketFd, &message, 0);
        if (received < 0 && errno == EINTR) {
            message.msg_controllen = control.size();
            continue;
        }
        if (received != static_cast<ssize_t>(marker.size())) {
            if (received < 0) {
                std::fprintf(
                    stderr,
                    "droidhatch-frame-agent: HWC recvmsg failed: %s\n",
                    std::strerror(errno));
            } else {
                std::fprintf(
                    stderr,
                    "droidhatch-frame-agent: HWC sent marker of %zd bytes; expected %zu\n",
                    received,
                    marker.size());
            }
            return false;
        }
        break;
    }

    const bool knownMarker = marker[0] == 0xff || marker[0] == 0x7f;
    if (!knownMarker) {
        std::fprintf(
            stderr,
            "droidhatch-frame-agent: unexpected HWC marker=0x%02x%s\n",
            marker[0],
            acceptUnknownMarkers ? "; inspecting as diagnostic frame" : "");
    }

    if (!receiveDescriptor(message, descriptor)) {
        std::fprintf(
            stderr,
            "droidhatch-frame-agent: HWC frame did not include a buffer FD\n");
        return false;
    }

    if (!knownMarker && !acceptUnknownMarkers) {
        std::fprintf(
            stderr,
            "droidhatch-frame-agent: rejecting unknown HWC marker=0x%02x\n",
            marker[0]);
        agent::UniqueFd rejectedDescriptor(*descriptor);
        *descriptor = -1;
        return false;
    }

    *handle = decodeBufferHandle(data);
    return true;
}

bool copyRedroidPixels(
    int descriptor,
    const RedroidBufferHandle& handle,
    std::vector<std::uint8_t>* pixels,
    std::uint32_t* strideBytes) {
    agent::UniqueFd bufferDescriptor(descriptor);
    if (pixels == nullptr || strideBytes == nullptr) {
        return false;
    }

    if (handle.fdCount != 1 || handle.intCount != 12 || handle.width == 0
        || handle.height == 0 || handle.stride < handle.width
        || (handle.format != kPixelFormatRgba8888
            && handle.format != kPixelFormatYv12)) {
        std::fprintf(
            stderr,
            "droidhatch-frame-agent: unsupported HWC handle fds=%u ints=%u "
            "width=%u height=%u format=%u stride=%u\n",
            handle.fdCount,
            handle.intCount,
            handle.width,
            handle.height,
            handle.format,
            handle.stride);
        return false;
    }

    constexpr std::uint64_t maximumBufferBytes = 512ULL * 1024ULL * 1024ULL;
    const std::uint64_t sourceStrideBytes = handle.format == kPixelFormatYv12
        ? handle.stride
        : static_cast<std::uint64_t>(handle.stride) * kRgbaBytesPerPixel;
    const std::uint64_t sourceBytes = sourceBufferBytes(handle);
    const std::uint64_t destinationStrideBytes =
        static_cast<std::uint64_t>(handle.width) * kRgbaBytesPerPixel;
    const std::uint64_t destinationBytes = destinationStrideBytes * handle.height;
    if (sourceBytes > maximumBufferBytes || destinationBytes > maximumBufferBytes
        || sourceStrideBytes > UINT32_MAX || destinationBytes > SIZE_MAX) {
        return false;
    }

    struct stat status = {};
    if (fstat(bufferDescriptor.get(), &status) != 0
        || status.st_size < static_cast<off_t>(sourceBytes)) {
        std::fprintf(
            stderr,
            "droidhatch-frame-agent: HWC buffer is too small: fd=%d size=%lld "
            "required=%llu\n",
            bufferDescriptor.get(),
            static_cast<long long>(status.st_size),
            static_cast<unsigned long long>(sourceBytes));
        return false;
    }

    agent::MappedRegion mapped(
        mmap(
            nullptr,
            static_cast<std::size_t>(sourceBytes),
            PROT_READ,
            MAP_SHARED,
            bufferDescriptor.get(),
            0),
        static_cast<std::size_t>(sourceBytes));
    if (!mapped) {
        std::fprintf(stderr, "droidhatch-frame-agent: mmap failed: %s\n", std::strerror(errno));
        return false;
    }

    const auto* source = static_cast<const std::uint8_t*>(mapped.address());
    if (handle.format == kPixelFormatYv12) {
        pixels->resize(static_cast<std::size_t>(sourceBytes));
        std::memcpy(pixels->data(), source, static_cast<std::size_t>(sourceBytes));
    } else {
        const std::size_t destinationRowBytes =
            static_cast<std::size_t>(handle.width) * kRgbaBytesPerPixel;
        pixels->resize(static_cast<std::size_t>(destinationBytes));
        auto* destination = pixels->data();
        if (handle.stride == handle.width) {
            std::memcpy(destination, source, static_cast<std::size_t>(destinationBytes));
        } else {
            const std::size_t sourceRowBytes =
                static_cast<std::size_t>(handle.stride) * kRgbaBytesPerPixel;
            for (std::uint32_t row = 0; row < handle.height; ++row) {
                std::memcpy(
                    destination + static_cast<std::size_t>(row) * destinationRowBytes,
                    source + static_cast<std::size_t>(row) * sourceRowBytes,
                    destinationRowBytes);
            }
        }
    }

    *strideBytes = handle.format == kPixelFormatYv12
        ? handle.stride
        : handle.width * 4;
    return true;
}

} // namespace droidhatch::agent
