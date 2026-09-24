#include "agent_io.h"

#include <cerrno>
#include <cstdio>
#include <cstdint>
#include <sys/socket.h>

namespace droidhatch::agent {

bool readAll(int fileDescriptor, void* destination, std::size_t size) {
    auto* bytes = static_cast<std::uint8_t*>(destination);
    std::size_t received = 0;
    while (received < size) {
        const ssize_t result = recv(
            fileDescriptor,
            bytes + received,
            size - received,
            0);
        if (result > 0) {
            received += static_cast<std::size_t>(result);
            continue;
        }
        if (result < 0 && errno == EINTR) {
            continue;
        }
        return false;
    }
    return true;
}

bool writeAll(int fileDescriptor, const void* source, std::size_t size) {
    const auto* bytes = static_cast<const std::uint8_t*>(source);
    std::size_t written = 0;
    while (written < size) {
        const ssize_t result = send(
            fileDescriptor,
            bytes + written,
            size - written,
            MSG_NOSIGNAL);
        if (result > 0) {
            written += static_cast<std::size_t>(result);
            continue;
        }
        if (result < 0 && errno == EINTR) {
            continue;
        }

        std::fprintf(
            stderr,
            "droidhatch-frame-agent: socket write failed after %zu/%zu bytes\n",
            written,
            size);
        return false;
    }
    return true;
}

} // namespace droidhatch::agent
