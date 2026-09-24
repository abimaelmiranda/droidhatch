#include "audio_server.h"

#include "agent_io.h"
#include "agent_resources.h"
#include "agent_socket.h"
#include "audio_protocol.h"

#include <cerrno>
#include <cstdio>
#include <poll.h>
#include <sys/socket.h>
#include <utility>

namespace droidhatch::audio {
namespace {

void sendCachedFormat(int client, const Message* formatMessage) {
    if (formatMessage == nullptr) {
        return;
    }
    agent::writeAll(client, formatMessage->wire.data(), formatMessage->wire.size());
}

} // namespace

void RunAudioServer(const agent::Options& options, std::stop_token stopToken) {
    agent::UniqueFd sourceListener(
        agent::createUnixAbstractListener(options.audioSourceSocket));
    agent::UniqueFd clientListener(
        agent::createUnixPathListener(options.audioSocket));
    if (!sourceListener || !clientListener) {
        agent::removeUnixSocketPath(options.audioSocket);
        std::fprintf(stderr, "droidhatch-frame-agent: cannot listen for audio\n");
        return;
    }

    agent::UniqueFd source;
    agent::UniqueFd client;
    Message cachedFormat = {};
    Message message = {};
    bool hasFormat = false;

    while (!stopToken.stop_requested()) {
        pollfd descriptors[3] = {
            {sourceListener.get(), POLLIN, 0},
            {clientListener.get(), POLLIN, 0},
            {source.get(), static_cast<short>(source ? POLLIN : 0), 0},
        };
        const int result = poll(descriptors, 3, 250);
        if (result < 0 && errno == EINTR) {
            continue;
        }
        if (result < 0) {
            break;
        }

        if ((descriptors[0].revents & POLLIN) != 0) {
            agent::UniqueFd nextSource(accept(sourceListener.get(), nullptr, nullptr));
            if (nextSource) {
                source = std::move(nextSource);
            }
        }

        if ((descriptors[1].revents & POLLIN) != 0) {
            agent::UniqueFd nextClient(accept(clientListener.get(), nullptr, nullptr));
            if (nextClient) {
                client = std::move(nextClient);
                const Metadata metadata = {};
                sendMessage(client.get(), MessageType::Hello, metadata, nullptr, 0);
                sendCachedFormat(client.get(), hasFormat ? &cachedFormat : nullptr);
            }
        }

        if (source && (descriptors[2].revents & POLLIN) != 0) {
            if (!readMessage(source.get(), &message)) {
                source.reset();
                continue;
            }

            if (message.type == MessageType::Format) {
                cachedFormat = message;
                hasFormat = true;
            }

            if (client
                && !agent::writeAll(client.get(), message.wire.data(), message.wire.size())) {
                client.reset();
            }

            if (options.audioDebug && message.type == MessageType::Audio) {
                std::fprintf(
                    stderr,
                    "droidhatch-frame-agent: audio #%llu frames=%u bytes=%zu\n",
                    static_cast<unsigned long long>(message.metadata.sequence),
                    message.metadata.frameCount,
                    message.payload.size());
            }
        }
    }

    agent::removeUnixSocketPath(options.audioSocket);
}

} // namespace droidhatch::audio
