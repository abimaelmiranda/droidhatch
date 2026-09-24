#include "agent_options.h"
#include "agent_runtime.h"

#include <utility>

int main(int argc, char** argv) {
    droidhatch::agent::Options options;
    if (!droidhatch::agent::parseOptions(argc, argv, &options)) {
        droidhatch::agent::printUsage(argv[0]);
        return 2;
    }

    droidhatch::agent::Runtime runtime(std::move(options));
    return runtime.Run();
}
