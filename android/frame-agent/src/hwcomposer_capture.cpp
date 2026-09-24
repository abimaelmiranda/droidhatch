#include "hwcomposer_capture.h"

#include <chrono>
#include <cerrno>
#include <cstdio>
#include <poll.h>
#include <sys/socket.h>
#include <thread>
#include <unistd.h>
#include <vector>

#include "agent_socket.h"
#include "agent_io.h"
#include "agent_resources.h"
#include "android_runtime_status.h"
#include "frame_protocol.h"
#include "redroid_buffer.h"

namespace droidhatch::agent {
namespace {

bool waitForHwcomposerOrClient(int client, int hwcomposer) {
    pollfd descriptors[2] = {
        {client, POLLIN | POLLHUP | POLLERR | POLLNVAL, 0},
        {hwcomposer, POLLIN | POLLHUP | POLLERR | POLLNVAL, 0},
    };

    while (true) {
        const int result = poll(descriptors, 2, -1);
        if (result > 0) {
            if (descriptors[0].revents & (POLLHUP | POLLERR | POLLNVAL)) {
                std::fprintf(stderr, "droidhatch-frame-agent: frame client disconnected\n");
                return false;
            }

            if (descriptors[1].revents != 0) {
                return true;
            }
            continue;
        }

        if (result < 0 && errno == EINTR) {
            continue;
        }

        return false;
    }
}

} // namespace

void runHwcomposerCapture(const Options& options) {
    UniqueFd listener(createTcpListener(options.framePort));
    if (!listener) {
        std::fprintf(
            stderr,
            "droidhatch-frame-agent: cannot listen on TCP port %u\n",
            options.framePort);
        return;
    }

    std::uint64_t sequence = 0;
    while (true) {
        std::fprintf(
            stderr,
            "droidhatch-frame-agent: waiting for frame client on TCP port %u\n",
            options.framePort);
        UniqueFd client(accept(listener.get(), nullptr, nullptr));
        if (!client) {
            if (errno == EINTR) {
                continue;
            }
            break;
        }

        std::fprintf(stderr, "droidhatch-frame-agent: frame client connected\n");
        if (!droidhatch::sendHello(client.get())) {
            continue;
        }

        droidhatch::sendStatus(client.get(), "[ok] Frame agent connected");
        sendRuntimeStatus(client.get());
        droidhatch::sendStatus(client.get(), "[wait] Connecting to hwcomposer");

        // Keep the destination storage alive for the whole client session.
        // copyRedroidPixels() resizes this vector, but resize() reuses its
        // capacity when the frame dimensions remain unchanged.
        std::vector<std::uint8_t> pixelBuffer;
        UniqueFd hwcomposer;
        while (true) {
            if (!hwcomposer) {
                std::fprintf(
                    stderr,
                    "droidhatch-frame-agent: waiting up to %u seconds for %s\n",
                    options.hwcomposerWaitSeconds,
                    options.hwcomposerSocket.c_str());
                hwcomposer.reset(connectUnixSocketWithRetry(
                    options.hwcomposerSocket,
                    options.hwcomposerWaitSeconds));
                if (!hwcomposer) {
                    droidhatch::sendError(client.get(), "Unable to connect to hwcomposer.");
                    break;
                }

                std::fprintf(
                    stderr,
                    "droidhatch-frame-agent: connected to %s\n",
                    options.hwcomposerSocket.c_str());
                droidhatch::sendStatus(client.get(), "[ok] HWC handshake completed");
            }

            if (!waitForHwcomposerOrClient(client.get(), hwcomposer.get())) {
                break;
            }

            RedroidBufferHandle handle = {};
            int descriptor = -1;
            if (!receiveRedroidFrame(
                    hwcomposer.get(),
                    options.acceptUnknownHwcomposerMarkers,
                    &handle,
                    &descriptor)) {
                std::fprintf(stderr, "droidhatch-frame-agent: HWC session ended; reconnecting\n");
                hwcomposer.reset();
                std::this_thread::sleep_for(std::chrono::milliseconds(250));
                continue;
            }

            std::uint32_t strideBytes = 0;
            if (!copyRedroidPixels(descriptor, handle, &pixelBuffer, &strideBytes)) {
                std::fprintf(stderr, "droidhatch-frame-agent: invalid HWC buffer; reconnecting\n");
                hwcomposer.reset();
                std::this_thread::sleep_for(std::chrono::milliseconds(250));
                continue;
            }

            if (!droidhatch::agent::writeAll(hwcomposer.get(), "ok", 2)) {
                std::fprintf(
                    stderr,
                    "droidhatch-frame-agent: HWC acknowledgement failed; reconnecting\n");
                hwcomposer.reset();
                std::this_thread::sleep_for(std::chrono::milliseconds(250));
                continue;
            }

            const droidhatch::FrameMetadata metadata = {
                sequence,
                static_cast<std::uint64_t>(
                    std::chrono::duration_cast<std::chrono::nanoseconds>(
                        std::chrono::steady_clock::now().time_since_epoch()).count()),
                handle.width,
                handle.height,
                strideBytes,
                handle.format,
            };
            if (!droidhatch::sendFrame(
                    client.get(),
                    metadata,
                    pixelBuffer.data(),
                    pixelBuffer.size())) {
                std::fprintf(stderr, "droidhatch-frame-agent: frame client write failed\n");
                break;
            }

            if (sequence == 0) {
                droidhatch::sendStatus(client.get(), "[ok] First frame received");
                droidhatch::sendStatus(client.get(), "[ok] Streaming");
            }

            sequence += 1;
        }

    }
}

} // namespace droidhatch::agent
