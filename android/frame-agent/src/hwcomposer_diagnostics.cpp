#include "hwcomposer_diagnostics.h"

#include <array>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

#include "agent_resources.h"
#include "agent_socket.h"

namespace droidhatch::agent {
namespace {

void printHex(const std::uint8_t* data, std::size_t size) {
    const std::size_t bytesToPrint = std::min<std::size_t>(size, 128);
    for (std::size_t index = 0; index < bytesToPrint; ++index) {
        std::fprintf(stderr, "%02x", data[index]);
        if ((index + 1) % 16 == 0) {
            std::fputc('\n', stderr);
        } else {
            std::fputc(' ', stderr);
        }
    }
    if (bytesToPrint % 16 != 0) {
        std::fputc('\n', stderr);
    }
}

} // namespace

void diagnoseHwcomposer(const Options& options) {
    UniqueFd socketFd(connectUnixSocket(options.hwcomposerSocket));
    if (!socketFd) {
        std::fprintf(
            stderr,
            "droidhatch-frame-agent: connect(%s) failed: %s\n",
            options.hwcomposerSocket.c_str(),
            std::strerror(errno));
        return;
    }

    std::fprintf(
        stderr,
        "droidhatch-frame-agent: connected to %s\n",
        options.hwcomposerSocket.c_str());

    std::array<std::uint8_t, 8192> data = {};
    std::array<std::uint8_t, CMSG_SPACE(sizeof(int) * 8)> control = {};
    iovec vector = {data.data(), data.size()};
    msghdr message = {};
    message.msg_iov = &vector;
    message.msg_iovlen = 1;
    message.msg_control = control.data();
    message.msg_controllen = control.size();

    while (true) {
        const ssize_t received = recvmsg(socketFd.get(), &message, 0);
        if (received == 0) {
            std::fprintf(stderr, "droidhatch-frame-agent: HWC closed the socket\n");
            break;
        }
        if (received < 0) {
            if (errno == EINTR) {
                continue;
            }
            std::fprintf(
                stderr,
                "droidhatch-frame-agent: recvmsg failed: %s\n",
                std::strerror(errno));
            break;
        }

        std::fprintf(
            stderr,
            "droidhatch-frame-agent: received %zd bytes flags=0x%x\n",
            received,
            message.msg_flags);
        printHex(data.data(), static_cast<std::size_t>(received));

        for (cmsghdr* header = CMSG_FIRSTHDR(&message);
             header != nullptr;
             header = CMSG_NXTHDR(&message, header)) {
            if (header->cmsg_level != SOL_SOCKET || header->cmsg_type != SCM_RIGHTS) {
                continue;
            }

            const std::size_t payloadBytes = header->cmsg_len - CMSG_LEN(0);
            const std::size_t fdCount = payloadBytes / sizeof(int);
            const auto* descriptors = reinterpret_cast<const int*>(CMSG_DATA(header));
            std::fprintf(stderr, "droidhatch-frame-agent: received %zu fd(s)\n", fdCount);
            for (std::size_t index = 0; index < fdCount; ++index) {
                struct stat status = {};
                if (fstat(descriptors[index], &status) == 0) {
                    std::fprintf(
                        stderr,
                        "  fd=%d mode=0%o size=%lld\n",
                        descriptors[index],
                        status.st_mode,
                        static_cast<long long>(status.st_size));
                }
                UniqueFd descriptor(descriptors[index]);
            }
        }

        message.msg_controllen = control.size();
    }

}

} // namespace droidhatch::agent
