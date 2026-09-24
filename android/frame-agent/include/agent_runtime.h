#pragma once

#include <thread>

#include "agent_options.h"
#include "uinput_devices.h"

namespace droidhatch::agent {

class Runtime {
public:
    explicit Runtime(Options options);

    Runtime(const Runtime&) = delete;
    Runtime& operator=(const Runtime&) = delete;

    int Run();

private:
    bool StartServices();
    void StopServices();

    Options options_;
    input::UInputDevices inputDevices_;
    std::jthread inputThread_;
    std::jthread audioThread_;
};

} // namespace droidhatch::agent
