#include "synthetic_frame.h"

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <sys/socket.h>
#include <thread>
#include <unistd.h>
#include <vector>

#include "agent_socket.h"
#include "agent_resources.h"
#include "frame_protocol.h"

namespace droidhatch::agent {
namespace {

std::vector<std::uint8_t> createSyntheticFrame(
    std::uint32_t width,
    std::uint32_t height,
    std::uint64_t sequence) {
    const std::size_t pixelBytes =
        static_cast<std::size_t>(width) * static_cast<std::size_t>(height) * 4;
    std::vector<std::uint8_t> pixels(pixelBytes);
    for (std::uint32_t y = 0; y < height; ++y) {
        for (std::uint32_t x = 0; x < width; ++x) {
            const std::size_t offset =
                (static_cast<std::size_t>(y) * width + x) * 4;
            pixels[offset] = static_cast<std::uint8_t>((x + sequence) % 256);
            pixels[offset + 1] = static_cast<std::uint8_t>((y * 4 + sequence) % 256);
            pixels[offset + 2] = static_cast<std::uint8_t>(sequence % 256);
            pixels[offset + 3] = 255;
        }
    }
    return pixels;
}

} // namespace

void runSynthetic(const Options& options) {
    agent::UniqueFd listener(createTcpListener(options.framePort));
    if (!listener) {
        std::fprintf(
            stderr,
            "droidhatch-frame-agent: cannot listen on TCP port %u\n",
            options.framePort);
        return;
    }

    std::fprintf(stderr, "droidhatch-frame-agent: waiting on TCP port %u\n", options.framePort);
    agent::UniqueFd client(accept(listener.get(), nullptr, nullptr));
    if (!client) {
        return;
    }

    if (!droidhatch::sendHello(client.get())) {
        return;
    }

    const auto interval = std::chrono::milliseconds(1000 / options.fps);
    for (std::uint64_t sequence = 0; ; ++sequence) {
        const auto pixels = createSyntheticFrame(options.width, options.height, sequence);
        const droidhatch::FrameMetadata metadata = {
            sequence,
            static_cast<std::uint64_t>(
                std::chrono::duration_cast<std::chrono::nanoseconds>(
                    std::chrono::steady_clock::now().time_since_epoch()).count()),
            options.width,
            options.height,
            options.width * 4,
            droidhatch::kPixelFormatRgba8888,
        };

        if (!droidhatch::sendFrame(client.get(), metadata, pixels.data(), pixels.size())) {
            break;
        }
        std::this_thread::sleep_for(interval);
    }

}

} // namespace droidhatch::agent
