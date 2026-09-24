#pragma once

#include <stop_token>

#include "agent_options.h"
#include "uinput_devices.h"

namespace droidhatch::input {

void RunInputServer(
    const agent::Options& options,
    UInputDevices& devices,
    std::stop_token stopToken);

} // namespace droidhatch::input
