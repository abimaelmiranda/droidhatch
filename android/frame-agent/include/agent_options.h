#pragma once

#include <cstdint>
#include <string>

namespace droidhatch::agent {

struct Options {
    std::string hwcomposerSocket = "/ipc/hwcomposer.sock";
    std::uint16_t framePort = 5732;
    std::uint32_t width = 64;
    std::uint32_t height = 32;
    std::uint32_t fps = 10;
    std::uint16_t inputPort = 5733;
    std::string audioSocket = "/ipc/droidhatch-audio.sock";
    std::string audioSourceSocket = "@droidhatch-audio-source";
    std::uint32_t hwcomposerWaitSeconds = 120;
    bool synthetic = false;
    bool captureHwcomposer = false;
    bool acceptUnknownHwcomposerMarkers = false;
    bool enableInput = true;
    bool inputDebug = false;
    bool enableAudio = true;
    bool audioDebug = false;
};

void printUsage(const char* executable);

bool parseOptions(int argc, char** argv, Options* options);

} // namespace droidhatch::agent
