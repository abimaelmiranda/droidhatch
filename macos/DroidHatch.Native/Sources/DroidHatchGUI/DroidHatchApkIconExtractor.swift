import Foundation

struct DroidHatchApkIconExtractor {
    func extract(from apkURL: URL) throws -> ApkIconAsset? {
        guard let aapt2 = locateAapt2() else {
            return nil
        }

        let output = try run(aapt2, arguments: ["dump", "badging", apkURL.path])
        guard let iconPath = iconPath(from: output) else {
            return nil
        }

        let data = try runData("/usr/bin/unzip", arguments: ["-p", apkURL.path, iconPath])
        guard !data.isEmpty else { return nil }
        return ApkIconAsset(data: data, mimeType: mimeType(for: data, path: iconPath))
    }

    private func locateAapt2() -> String? {
        let candidates = [
            ProcessInfo.processInfo.environment["DROIDHATCH_AAPT2_PATH"],
            Bundle.main.resourceURL?.appendingPathComponent("tools/aapt2").path,
            "/opt/homebrew/share/android-commandlinetools/build-tools/37.0.0/aapt2",
            "/opt/homebrew/share/android-commandlinetools/build-tools/36.1.0/aapt2",
            "/opt/homebrew/bin/aapt2"
        ].compactMap { $0 }

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func run(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: data, encoding: .utf8)
            let message: String
            if let detail, !detail.isEmpty {
                message = detail
            } else {
                message = "aapt2 falhou"
            }
            throw NSError(
                domain: "DroidHatchGUI.ApkIcon",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message])
        }
        guard let output = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "DroidHatchGUI.ApkIcon",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "aapt2 retornou saída inválida"])
        }
        return output
    }

    private func runData(_ executable: String, arguments: [String]) throws -> Data {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "DroidHatchGUI.ApkIcon",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Não foi possível extrair o ícone do APK"])
        }
        return data
    }

    private func iconPath(from badging: String) -> String? {
        guard let line = badging.split(separator: "\n").first(where: { $0.hasPrefix("application:") }) else {
            return nil
        }
        let pattern = #"\bicon='([^']+)'"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: String(line),
                range: NSRange(location: 0, length: String(line).utf16.count)),
              let range = Range(match.range(at: 1), in: String(line)) else {
            return nil
        }
        return String(String(line)[range])
    }

    private func mimeType(for data: Data, path: String) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.count >= 12,
           String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
           String(bytes: bytes[8..<12], encoding: .ascii) == "WEBP" {
            return "image/webp"
        }
        if path.hasSuffix(".xml") { return "application/xml" }
        return "application/octet-stream"
    }
}
