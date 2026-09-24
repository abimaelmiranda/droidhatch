#include "agent_runtime.h"

#include "audio_server.h"
#include "hwcomposer_capture.h"
#include "hwcomposer_diagnostics.h"
#include "input_server.h"
#include "synthetic_frame.h"

#include <cstdio>
#include <utility>

namespace droidhatch::agent {

Runtime::Runtime(Options options) : options_(std::move(options)) {}

int Runtime::Run() {
    if (!StartServices()) {
        return 3;
    }

    if (options_.synthetic) {
        runSynthetic(options_);
    } else if (options_.captureHwcomposer) {
        runHwcomposerCapture(options_);
    } else {
        diagnoseHwcomposer(options_);
    }

    StopServices();
    return 0;
}

bool Runtime::StartServices() {
    if (options_.enableInput
        && (options_.synthetic || options_.captureHwcomposer)) {
        if (!inputDevices_.Initialize()) {
            std::fprintf(
                stderr,
                "droidhatch-frame-agent: uinput unavailable: %s\n",
                inputDevices_.FailureReason().c_str());
            return false;
        }

        inputThread_ = std::jthread(
            [this](std::stop_token stopToken) {
                input::RunInputServer(options_, inputDevices_, stopToken);
            });
    }

    if (options_.enableAudio
        && (options_.synthetic || options_.captureHwcomposer)) {
        audioThread_ = std::jthread(
            [this](std::stop_token stopToken) {
                audio::RunAudioServer(options_, stopToken);
            });
    }

    return true;
}

void Runtime::StopServices() {
    if (inputThread_.joinable()) {
        inputThread_.request_stop();
    }
    if (audioThread_.joinable()) {
        audioThread_.request_stop();
    }

    inputThread_ = std::jthread();
    audioThread_ = std::jthread();
    inputDevices_.ReleaseAll();
}

} // namespace droidhatch::agent
