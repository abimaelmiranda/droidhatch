#pragma once

#include <cstdint>
#include <optional>

namespace droidhatch::input {

std::optional<unsigned short> LinuxKeyCodeForHidUsage(std::uint16_t usage);

} // namespace droidhatch::input
