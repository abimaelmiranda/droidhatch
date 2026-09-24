#include "input_server.h"

#include "agent_socket.h"
#include "agent_resources.h"
#include "input_protocol.h"
#include "wire_codec.h"

#include <array>
#include <cerrno>
#include <cstdio>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>
#include <utility>

namespace droidhatch::input {
namespace {

bool HandleMessage(int client, UInputDevices& devices, bool inputDebug) {
    std::array<std::uint8_t, kMaximumPayloadSize> payload = {};
    MessageHeader header = {};
    if (!readMessage(client, &header, payload.data(), payload.size())) {
        return false;
    }

    if (header.type == MessageType::Hello) {
        return sendCapabilities(client);
    }

    if (header.type == MessageType::Key) {
        if (header.payloadSize != 4) {
            return false;
        }
        const auto usage = wire::read16(payload.data());
        const auto action = static_cast<KeyAction>(payload[2]);
        if (inputDebug) {
            std::fprintf(
                stderr,
                "droidhatch-frame-agent: key usage=0x%04x action=%u\n",
                usage,
                static_cast<unsigned int>(action));
        }
        return devices.SendKey(usage, action);
    }

    if (header.type == MessageType::Touch) {
        if (header.payloadSize != 16) {
            return false;
        }
        const auto pointerId = wire::read32(payload.data());
        const auto action = static_cast<TouchAction>(payload[4]);
        const auto x = wire::read32(payload.data() + 8);
        const auto y = wire::read32(payload.data() + 12);
        if (inputDebug) {
            std::fprintf(
                stderr,
                "droidhatch-frame-agent: touch pointer=%u action=%u x=%u y=%u\n",
                pointerId,
                static_cast<unsigned int>(action),
                x,
                y);
        }
        return devices.SendTouch(pointerId, action, x, y);
    }

    if (header.type == MessageType::SystemAction) {
        if (header.payloadSize != 4) {
            return false;
        }
        const auto action = static_cast<SystemAction>(payload[0]);
        if (inputDebug) {
            std::fprintf(
                stderr,
                "droidhatch-frame-agent: system action=%u\n",
                static_cast<unsigned int>(action));
        }
        return devices.SendSystemAction(action);
    }

    if (header.type == MessageType::Scroll) {
        if (header.payloadSize != 16) {
            return false;
        }

        const auto* bytes = payload.data();
        const auto deltaX = static_cast<std::int32_t>(wire::read32(bytes));
        const auto deltaY = static_cast<std::int32_t>(wire::read32(bytes + 4));
        const auto phase = static_cast<ScrollPhase>(bytes[8]);
        const auto momentumPhase = static_cast<ScrollPhase>(bytes[9]);
        const auto flags = static_cast<ScrollFlags>(bytes[10]);
        const auto sequence = wire::read32(bytes + 12);

        if (inputDebug) {
            std::fprintf(
                stderr,
                "droidhatch-frame-agent: scroll #%u dx=%d dy=%d phase=%u momentum=%u flags=%u\n",
                sequence,
                deltaX,
                deltaY,
                static_cast<unsigned int>(phase),
                static_cast<unsigned int>(momentumPhase),
                static_cast<unsigned int>(flags));
        }

        return devices.SendScroll(deltaX, deltaY, flags);
    }

    return false;
}

} // namespace

void RunInputServer(
    const agent::Options& options,
    UInputDevices& devices,
    std::stop_token stopToken) {
    agent::UniqueFd listener(agent::createTcpListener(options.inputPort));
    if (!listener) {
        std::fprintf(
            stderr,
            "droidhatch-frame-agent: cannot listen for input on TCP port %u\n",
            options.inputPort);
        return;
    }

    agent::UniqueFd client;
    while (!stopToken.stop_requested()) {
        pollfd descriptors[2] = {
            {listener.get(), POLLIN, 0},
            {client.get(), static_cast<short>(client ? POLLIN : 0), 0},
        };
        const int result = poll(descriptors, 2, 250);
        if (result < 0 && errno == EINTR) {
            continue;
        }
        if (result < 0) {
            break;
        }

        if ((descriptors[0].revents & POLLIN) != 0) {
            agent::UniqueFd nextClient(accept(listener.get(), nullptr, nullptr));
            if (nextClient) {
                if (client) {
                    client.reset();
                    devices.ReleaseAll();
                    std::fprintf(
                        stderr,
                        "droidhatch-frame-agent: input client replaced\n");
                }

                client = std::move(nextClient);
                devices.ReleaseAll();
                std::fprintf(
                    stderr,
                    "droidhatch-frame-agent: input client connected\n");
            }
        }

        if (!client) {
            continue;
        }

        const short events = descriptors[1].revents;
        if ((events & (POLLIN | POLLERR | POLLHUP | POLLNVAL)) == 0) {
            continue;
        }

        if ((events & POLLIN) != 0
            && HandleMessage(client.get(), devices, options.inputDebug)) {
            continue;
        }

        client.reset();
        devices.ReleaseAll();
        std::fprintf(stderr, "droidhatch-frame-agent: input client disconnected\n");
    }

    if (client) {
        client.reset();
        devices.ReleaseAll();
    }
}

} // namespace droidhatch::input
