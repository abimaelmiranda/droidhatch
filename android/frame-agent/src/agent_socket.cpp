#include "agent_socket.h"

#include "agent_resources.h"

#include <algorithm>
#include <array>
#include <cerrno>
#include <chrono>
#include <cstddef>
#include <cstring>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <sys/inotify.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <thread>
#include <unistd.h>

namespace droidhatch::agent {

int createTcpListener(std::uint16_t port) {
    UniqueFd socketFd(socket(AF_INET, SOCK_STREAM, 0));
    if (!socketFd) {
        return -1;
    }

    int reuseAddress = 1;
    if (setsockopt(
            socketFd.get(),
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuseAddress,
            sizeof(reuseAddress)) < 0) {
        return -1;
    }

    sockaddr_in address = {};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    address.sin_port = htons(port);
    if (bind(socketFd.get(), reinterpret_cast<sockaddr*>(&address), sizeof(address)) < 0
        || listen(socketFd.get(), 1) < 0) {
        return -1;
    }

    return socketFd.release();
}

int createUnixAbstractListener(const std::string& name) {
    UniqueFd socketFd(socket(AF_UNIX, SOCK_STREAM, 0));
    if (!socketFd || name.empty() || name.front() != '@') {
        return -1;
    }

    sockaddr_un address = {};
    address.sun_family = AF_UNIX;
    const std::string abstractName = name.substr(1);
    if (abstractName.size() + 1 >= sizeof(address.sun_path)) {
        return -1;
    }
    std::memcpy(address.sun_path + 1, abstractName.data(), abstractName.size());

    const auto addressSize = static_cast<socklen_t>(
        offsetof(sockaddr_un, sun_path) + 1 + abstractName.size());
    if (bind(
            socketFd.get(),
            reinterpret_cast<sockaddr*>(&address),
            addressSize) < 0
        || listen(socketFd.get(), 1) < 0) {
        return -1;
    }

    return socketFd.release();
}

int createUnixPathListener(const std::string& path) {
    if (path.empty() || path.front() != '/' || path.size() >= sizeof(sockaddr_un::sun_path)) {
        return -1;
    }

    UniqueFd socketFd(socket(AF_UNIX, SOCK_STREAM, 0));
    if (!socketFd) {
        return -1;
    }

    unlink(path.c_str());

    sockaddr_un address = {};
    address.sun_family = AF_UNIX;
    std::memcpy(address.sun_path, path.c_str(), path.size() + 1);
    const auto addressSize = static_cast<socklen_t>(
        offsetof(sockaddr_un, sun_path) + path.size() + 1);
    if (bind(
            socketFd.get(),
            reinterpret_cast<sockaddr*>(&address),
            addressSize) < 0
        || listen(socketFd.get(), 1) < 0) {
        unlink(path.c_str());
        return -1;
    }

    return socketFd.release();
}

void removeUnixSocketPath(const std::string& path) {
    if (!path.empty() && path.front() == '/') {
        unlink(path.c_str());
    }
}

int connectUnixSocket(const std::string& path) {
    if (path.empty()) {
        return -1;
    }

    UniqueFd socketFd(socket(AF_UNIX, SOCK_STREAM, 0));
    if (!socketFd) {
        return -1;
    }

    sockaddr_un address = {};
    address.sun_family = AF_UNIX;
    if (path.front() == '@') {
        const std::string abstractName = path.substr(1);
        if (abstractName.size() + 1 >= sizeof(address.sun_path)) {
            return -1;
        }
        std::memcpy(address.sun_path + 1, abstractName.data(), abstractName.size());
        const auto addressSize = static_cast<socklen_t>(
            offsetof(sockaddr_un, sun_path) + 1 + abstractName.size());
        if (connect(
                socketFd.get(),
                reinterpret_cast<sockaddr*>(&address),
                addressSize) < 0) {
            return -1;
        }
        return socketFd.release();
    }

    if (path.size() >= sizeof(address.sun_path)) {
        return -1;
    }

    std::memcpy(address.sun_path, path.c_str(), path.size() + 1);
    if (connect(
            socketFd.get(),
            reinterpret_cast<sockaddr*>(&address),
            sizeof(address)) < 0) {
        return -1;
    }

    return socketFd.release();
}

int connectUnixSocketWithRetry(
    const std::string& path,
    std::uint32_t waitSeconds) {
#if defined(__ANDROID__)
    const std::size_t separator = path.rfind('/');
    const std::string parentPath = separator == std::string::npos
        ? "."
        : path.substr(0, separator == 0 ? 1 : separator);
    const std::string socketName = separator == std::string::npos
        ? path
        : path.substr(separator + 1);
    UniqueFd notificationFd(inotify_init1(IN_CLOEXEC));
    if (notificationFd) {
        const int watchDescriptor = inotify_add_watch(
            notificationFd.get(),
            parentPath.c_str(),
            IN_CREATE | IN_MOVED_TO | IN_DELETE | IN_MOVED_FROM);
        if (watchDescriptor < 0) {
            notificationFd.reset();
        }
    }

    const auto deadline = std::chrono::steady_clock::now()
        + std::chrono::seconds(waitSeconds);
    while (std::chrono::steady_clock::now() < deadline) {
        const int socketFd = connectUnixSocket(path);
        if (socketFd >= 0) {
            return socketFd;
        }

        if (!notificationFd) {
            std::this_thread::sleep_for(std::chrono::milliseconds(250));
            continue;
        }

        const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(
            deadline - std::chrono::steady_clock::now()).count();
        const int timeout = static_cast<int>(std::min<long long>(remaining, 1000));
        pollfd descriptor = {notificationFd.get(), POLLIN, 0};
        const int pollResult = poll(&descriptor, 1, timeout);
        if (pollResult < 0 && errno != EINTR) {
            return -1;
        }
        if (pollResult <= 0 || (descriptor.revents & POLLIN) == 0) {
            continue;
        }

        std::array<std::uint8_t, 4096> events = {};
        const ssize_t bytesRead = read(notificationFd.get(), events.data(), events.size());
        if (bytesRead <= 0) {
            return -1;
        }

        std::size_t offset = 0;
        while (offset + sizeof(inotify_event) <= static_cast<std::size_t>(bytesRead)) {
            const auto* event = reinterpret_cast<const inotify_event*>(events.data() + offset);
            if (event->len > 0 && socketName == event->name) {
                break;
            }
            offset += sizeof(inotify_event) + event->len;
        }
    }

    return -1;
#else
    const auto deadline = std::chrono::steady_clock::now()
        + std::chrono::seconds(waitSeconds);
    while (std::chrono::steady_clock::now() < deadline) {
        const int socketFd = connectUnixSocket(path);
        if (socketFd >= 0) {
            return socketFd;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(250));
    }
    return -1;
#endif
}

} // namespace droidhatch::agent
