#pragma once

#include <stop_token>

#include "agent_options.h"

namespace droidhatch::audio {

void RunAudioServer(const agent::Options& options, std::stop_token stopToken);

} // namespace droidhatch::audio
