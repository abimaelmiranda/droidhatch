import Foundation

final class DroidHatchContainerClient: @unchecked Sendable {
    let configuration: DroidHatchBackendConfiguration
    private let containerRunner: DroidHatchCommandRunner
    private let adbRunner: DroidHatchCommandRunner

    private var adbSerial: String {
        "\(configuration.host):\(configuration.adbPort)"
    }

    init(fileManager: FileManager = .default) throws {
        configuration = DroidHatchBackendConfiguration()
        let environment = ProcessInfo.processInfo.environment
        let containerCandidates = [
            environment["DROIDHATCH_CONTAINER_PATH"],
            "/usr/local/bin/container",
            "/opt/homebrew/bin/container"
        ].compactMap { $0 }.map(URL.init(fileURLWithPath:))
        guard let containerExecutable = containerCandidates.first(where: {
            fileManager.isExecutableFile(atPath: $0.path)
        }) else {
            throw DroidHatchContainerError.executableNotFound("container")
        }
        containerRunner = DroidHatchCommandRunner(executable: containerExecutable)

        let adbCandidates = [
            environment["DROIDHATCH_ADB_PATH"],
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb"
        ].compactMap { $0 }.map(URL.init(fileURLWithPath:))
        guard let adbExecutable = adbCandidates.first(where: {
            fileManager.isExecutableFile(atPath: $0.path)
        }) else {
            throw DroidHatchContainerError.executableNotFound("adb")
        }
        adbRunner = DroidHatchCommandRunner(executable: adbExecutable)
    }

    func ensureRunning() throws {
        let state: String
        do {
            state = try inspectState()
        } catch {
            try createBackend()
            state = try inspectState()
        }

        if state != DroidHatchContainerDefaults.runningState {
            try runContainer(["start", configuration.containerName])
        }
        try waitForAndroidBoot()
    }

    func install(apkURL: URL) throws {
        try ensureRunning()
        try runADB([
            "-s", adbSerial,
            "install",
            "-r",
            "-g",
            apkURL.path
        ])
    }

    func packageName(from apkURL: URL) throws -> String {
        try AndroidApkManifestReader().readPackageName(from: apkURL)
    }

    func installAndReturnPackageName(apkURL: URL) throws -> String {
        let packageName = try packageName(from: apkURL)
        try install(apkURL: apkURL)
        return packageName
    }

    func uninstall(packageName: String) throws {
        try ensureRunning()
        try runADB(["-s", adbSerial, "shell", "pm", "uninstall", packageName])
    }

    func open(packageName: String) throws {
        try ensureRunning()
        _ = try? runADB([
            "-s", adbSerial,
            "shell", "am", "broadcast",
            "-n", DroidHatchContainerDefaults.homeComponent,
            "-a", DroidHatchContainerDefaults.setActivePackageAction,
            "--es", DroidHatchContainerDefaults.packageNameExtra, packageName,
            "--es", DroidHatchContainerDefaults.sessionIdExtra,
            UUID().uuidString.replacingOccurrences(of: "-", with: "")
        ])
        let activityOutput = try runADB([
            "-s", adbSerial,
            "shell", "cmd", "package", "resolve-activity", "--brief", packageName
        ])
        guard let activity = activityOutput
            .split(whereSeparator: \.isNewline)
            .reversed()
            .map(String.init)
            .first(where: { $0.contains("/") }) else {
            throw DroidHatchContainerError.commandFailed(
                "Não foi possível encontrar a activity inicial de \\(packageName).")
        }
        try runADB([
            "-s", adbSerial,
            "shell", "am", "start", "-n", activity
        ])
    }

    func close() throws {
        let state = try inspectState()
        guard state == "running" else { return }
        _ = try? runADB([
            "-s", adbSerial,
            "shell", "am", "broadcast",
            "-n", DroidHatchContainerDefaults.homeComponent,
            "-a", DroidHatchContainerDefaults.clearActivePackageAction
        ])
        try runContainer(["stop", configuration.containerName])
    }

    private func createBackend() throws {
        let fileManager = FileManager.default
        let socketDirectory = configuration.hostAudioSocket.deletingLastPathComponent()
        try fileManager.createDirectory(at: socketDirectory, withIntermediateDirectories: true)

        var arguments = [
            "create",
            "--name", configuration.containerName,
            "--memory", DroidHatchContainerDefaults.memoryLimit,
            "--shm-size", DroidHatchContainerDefaults.sharedMemoryLimit,
            "--cap-add", "ALL",
            "--publish", "\(configuration.host):\(configuration.adbPort):\(DroidHatchContainerDefaults.containerAdbPort)",
            "--publish", "\(configuration.host):\(configuration.framePort):\(configuration.frameAgentPort)",
            "--publish", "\(configuration.host):\(configuration.inputPort):\(configuration.inputAgentPort)",
            "--publish-socket", "\(configuration.hostAudioSocket.path):\(configuration.guestAudioSocket)"
        ]

        if let kernelPath = configuration.kernelPath {
            arguments += ["--kernel", kernelPath]
        }
        arguments.append(configuration.image)
        arguments += DroidHatchContainerDefaults.androidBootArguments
        try runContainer(arguments)
    }

    private func inspectState() throws -> String {
        let output = try runContainer(["inspect", configuration.containerName])
        guard let data = output.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let status = root.first?["status"] as? [String: Any],
              let state = status["state"] as? String else {
            throw DroidHatchContainerError.commandFailed("container inspect retornou JSON inválido.")
        }
        return state.lowercased()
    }

    private func waitForAndroidBoot() throws {
        try DroidHatchAndroidReadiness.wait(serial: adbSerial, runADB: runADB)
    }

    @discardableResult
    private func runContainer(_ arguments: [String]) throws -> String {
        try containerRunner.run(arguments: arguments)
    }

    @discardableResult
    fileprivate func runADB(_ arguments: [String]) throws -> String {
        try adbRunner.run(arguments: arguments)
    }
}
