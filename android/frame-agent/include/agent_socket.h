#pragma once

#include <cstdint>
#include <string>

namespace droidhatch::agent {

int createTcpListener(std::uint16_t port);

int createUnixAbstractListener(const std::string& name);

int createUnixPathListener(const std::string& path);

void removeUnixSocketPath(const std::string& path);

int connectUnixSocket(const std::string& path);

int connectUnixSocketWithRetry(const std::string& path, std::uint32_t waitSeconds);

} // namespace droidhatch::agent
