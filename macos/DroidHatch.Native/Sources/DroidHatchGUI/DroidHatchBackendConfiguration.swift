import Foundation

struct DroidHatchBackendConfiguration: Sendable {
    let containerName = DroidHatchContainerDefaults.containerName
    let image: String
    let host = DroidHatchContainerDefaults.host
    let adbPort = DroidHatchContainerDefaults.adbPort
    let framePort = DroidHatchContainerDefaults.framePort
    let inputPort = DroidHatchContainerDefaults.inputPort
    let frameAgentPort = DroidHatchContainerDefaults.frameAgentPort
    let inputAgentPort = DroidHatchContainerDefaults.inputAgentPort
    let guestAudioSocket = DroidHatchContainerDefaults.guestAudioSocket

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        if let configuredImage = environment[DroidHatchContainerDefaults.imageEnvironmentVariable],
           !configuredImage.isEmpty {
            image = configuredImage
        } else {
            image = DroidHatchContainerDefaults.image
        }
    }

    var hostAudioSocket: URL {
        DroidHatchUserPaths.root
            .appendingPathComponent(DroidHatchContainerDefaults.hostAudioSocketRelativePath)
    }

    var kernelPath: String? {
        let environment = ProcessInfo.processInfo.environment
        if let configured = environment["DROIDHATCH_KERNEL_PATH"], !configured.isEmpty {
            return configured
        }

        if let bundled = Bundle.main.url(
            forResource: "vmlinux-arm64",
            withExtension: nil,
            subdirectory: "kernel"),
           FileManager.default.isReadableFile(atPath: bundled.path) {
            return bundled.path
        }

        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while directory.path != "/" {
            if directory.lastPathComponent == "DroidHatch" {
                let candidate = directory.appendingPathComponent("image/kernel/vmlinux-arm64")
                if FileManager.default.isReadableFile(atPath: candidate.path) {
                    return candidate.path
                }
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }
}
