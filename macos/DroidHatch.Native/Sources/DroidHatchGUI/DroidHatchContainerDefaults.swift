import Foundation

enum DroidHatchContainerDefaults {
    static let containerName = "droidhatch-backend"
    static let image = "ghcr.io/abimaelmiranda/droidhatch/redroid:stable"
    static let imageEnvironmentVariable = "DROIDHATCH_IMAGE"
    static let host = "127.0.0.1"

    static let adbPort = 16_092
    static let framePort = 16_090
    static let inputPort = 16_091
    static let frameAgentPort = 5_732
    static let inputAgentPort = 5_733
    static let guestAudioSocket = "/ipc/droidhatch-audio.sock"
    static let hostAudioSocketRelativePath = "run/backend-audio.sock"

    static let containerAdbPort = 5_555
    static let memoryLimit = "2g"
    static let sharedMemoryLimit = "1g"
    static let runningState = "running"

    static let androidWidth = 1_280
    static let androidHeight = 720
    static let androidFramesPerSecond = 30

    static let androidBootArguments = [
        "androidboot.hardware=redroid",
        "ro.secure=0",
        "ro.debuggable=1",
        "androidboot.use_memfd=true",
        "androidboot.use_redroid_stream=true",
        "androidboot.redroid_gpu_mode=guest",
        "androidboot.redroid_width=\(androidWidth)",
        "androidboot.redroid_height=\(androidHeight)",
        "androidboot.redroid_fps=\(androidFramesPerSecond)"
    ]

    static let homeComponent = "com.droidhatch.home/.SessionReceiver"
    static let setActivePackageAction = "com.droidhatch.home.SET_ACTIVE_PACKAGE"
    static let clearActivePackageAction = "com.droidhatch.home.CLEAR_ACTIVE_PACKAGE"
    static let packageNameExtra = "package_name"
    static let sessionIdExtra = "session_id"

    static let androidBootTimeout: TimeInterval = 60
    static let mediaRecoveryTimeout: TimeInterval = 20
    static let bootPollInterval: TimeInterval = 0.25
    static let mediaPollInterval: TimeInterval = 0.5

}
