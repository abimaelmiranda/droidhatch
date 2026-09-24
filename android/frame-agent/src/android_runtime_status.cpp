#include "android_runtime_status.h"

#include "frame_protocol.h"

#include <cstring>
#include <sys/stat.h>
#include <unistd.h>

#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif

namespace droidhatch::agent {
namespace {

bool androidPropertyEquals(const char* name, const char* expected) {
#if defined(__ANDROID__)
    char value[PROP_VALUE_MAX] = {};
    const int length = __system_property_get(name, value);
    return length > 0 && std::strcmp(value, expected) == 0;
#else
    (void)name;
    (void)expected;
    return false;
#endif
}

bool androidRuntimeReady() {
    return androidPropertyEquals("sys.boot_completed", "1");
}

bool lmkdReady() {
    return access("/proc/pressure/memory", R_OK) == 0
        && access("/dev/socket/lmkd", F_OK) == 0;
}

} // namespace

void sendRuntimeStatus(int client) {
    if (androidRuntimeReady()) {
        droidhatch::sendStatus(client, "[ok] Android boot completed");
    } else {
        droidhatch::sendStatus(client, "[wait] Android boot is still starting");
    }

    if (lmkdReady()) {
        droidhatch::sendStatus(client, "[ok] PSI and lmkd are ready");
    } else {
        droidhatch::sendStatus(client, "[wait] PSI or lmkd is not ready");
    }
}

} // namespace droidhatch::agent
