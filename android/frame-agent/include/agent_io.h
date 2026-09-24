#pragma once

#include <cstddef>

namespace droidhatch::agent {

bool readAll(int fileDescriptor, void* destination, std::size_t size);

bool writeAll(int fileDescriptor, const void* source, std::size_t size);

} // namespace droidhatch::agent
