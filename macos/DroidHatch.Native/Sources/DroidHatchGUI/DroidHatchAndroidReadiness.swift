import Foundation

struct DroidHatchAndroidReadiness {
    static func wait(
        serial: String,
        runADB: ([String]) throws -> String,
        progress: @escaping DroidHatchProgressHandler = { _ in }) throws {
        progress("Aguardando o Android concluir o boot…")
        let deadline = Date().addingTimeInterval(
            DroidHatchContainerDefaults.androidBootTimeout)
        _ = try? runADB(["connect", serial])

        progress("Aguardando os serviços de mídia…")
        while Date() < deadline {
            if let output = try? runADB(["-s", serial, "shell", "getprop", "sys.boot_completed"]),
               output.trimmingCharacters(in: .whitespacesAndNewlines) == "1" {
                break
            }
            Thread.sleep(forTimeInterval: DroidHatchContainerDefaults.bootPollInterval)
        }

        while Date() < deadline {
            if mediaServicesReady(serial: serial, runADB: runADB) {
                return
            }
            Thread.sleep(forTimeInterval: DroidHatchContainerDefaults.mediaPollInterval)
        }

        progress("Revalidando os serviços de mídia…")
        // mediaserver can race servicemanager during the first guest boot.
        // Restarting only that service lets init re-register the media Binder
        // services without resetting the Android session or user data.
        _ = try? runADB([
            "-s", serial,
            "shell", "sh", "-c", "kill -9 $(pidof mediaserver)"
        ])

        let recoveryDeadline = Date().addingTimeInterval(
            DroidHatchContainerDefaults.mediaRecoveryTimeout)
        while Date() < recoveryDeadline {
            if mediaServicesReady(serial: serial, runADB: runADB) {
                return
            }
            Thread.sleep(forTimeInterval: DroidHatchContainerDefaults.mediaPollInterval)
        }

        throw DroidHatchContainerError.bootTimeout
    }

    private static func mediaServicesReady(
        serial: String,
        runADB: ([String]) throws -> String) -> Bool {
        guard let output = try? runADB(["-s", serial, "shell", "service", "list"]) else {
            return false
        }

        return output.contains("media.player: [android.media.IMediaPlayerService]")
            && output.contains("media.resource_manager: [android.media.IResourceManagerService]")
    }
}
