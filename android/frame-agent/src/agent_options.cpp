#include "agent_options.h"

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <limits>

namespace droidhatch::agent {
namespace {

bool parseUnsigned(const char* value, std::uint32_t* result) {
    if (value == nullptr || result == nullptr) {
        return false;
    }

    char* end = nullptr;
    errno = 0;
    const unsigned long parsed = std::strtoul(value, &end, 10);
    if (errno != 0 || end == value || *end != '\0'
        || parsed > std::numeric_limits<std::uint32_t>::max()) {
        return false;
    }

    *result = static_cast<std::uint32_t>(parsed);
    return true;
}

} // namespace

void printUsage(const char* executable) {
    std::fprintf(
        stderr,
        "Usage: %s [--diagnose-hwc] [--capture-hwc] [--synthetic] [--hwcomposer-socket PATH] "
        "[--frame-port PORT] [--input-port PORT] [--width PX] [--height PX] [--fps FPS] "
        "[--audio-socket PATH] "
        "[--audio-source-socket NAME] [--disable-input] "
        "[--disable-audio] [--input-debug] [--audio-debug] "
        "[--hwcomposer-wait-seconds SECONDS] [--accept-unknown-hwc-markers]\n",
        executable);
}

bool parseOptions(int argc, char** argv, Options* options) {
    if (options == nullptr) {
        return false;
    }

    for (int index = 1; index < argc; ++index) {
        const std::string argument = argv[index];
        if (argument == "--synthetic") {
            options->synthetic = true;
            continue;
        }

        if (argument == "--diagnose-hwc") {
            options->synthetic = false;
            options->captureHwcomposer = false;
            continue;
        }

        if (argument == "--capture-hwc") {
            options->synthetic = false;
            options->captureHwcomposer = true;
            continue;
        }

        if (argument == "--accept-unknown-hwc-markers") {
            options->acceptUnknownHwcomposerMarkers = true;
            continue;
        }

        if (argument == "--disable-input") {
            options->enableInput = false;
            continue;
        }

        if (argument == "--input-debug") {
            options->inputDebug = true;
            continue;
        }

        if (argument == "--disable-audio") {
            options->enableAudio = false;
            continue;
        }

        if (argument == "--audio-debug") {
            options->audioDebug = true;
            continue;
        }

        if (index + 1 >= argc) {
            return false;
        }

        const char* value = argv[++index];
        if (argument == "--hwcomposer-socket") {
            options->hwcomposerSocket = value;
            continue;
        }

        std::uint32_t parsed = 0;
        if (argument == "--frame-port") {
            if (!parseUnsigned(value, &parsed) || parsed > UINT16_MAX) {
                return false;
            }
            options->framePort = static_cast<std::uint16_t>(parsed);
            continue;
        }

        if (argument == "--input-port") {
            if (!parseUnsigned(value, &parsed) || parsed > UINT16_MAX) {
                return false;
            }
            options->inputPort = static_cast<std::uint16_t>(parsed);
            continue;
        }

        if (argument == "--audio-socket") {
            if (value[0] != '/') {
                return false;
            }
            options->audioSocket = value;
            continue;
        }

        if (argument == "--audio-source-socket") {
            options->audioSourceSocket = value;
            continue;
        }

        if (argument == "--width") {
            if (!parseUnsigned(value, &options->width) || options->width == 0) {
                return false;
            }
            continue;
        }

        if (argument == "--height") {
            if (!parseUnsigned(value, &options->height) || options->height == 0) {
                return false;
            }
            continue;
        }

        if (argument == "--fps") {
            if (!parseUnsigned(value, &options->fps) || options->fps == 0) {
                return false;
            }
            continue;
        }

        if (argument == "--hwcomposer-wait-seconds") {
            if (!parseUnsigned(value, &options->hwcomposerWaitSeconds)
                || options->hwcomposerWaitSeconds == 0) {
                return false;
            }
            continue;
        }

        return false;
    }

    return true;
}

} // namespace droidhatch::agent
