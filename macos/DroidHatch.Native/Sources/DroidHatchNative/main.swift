import Foundation

let protocolVersion = "1"

func writeResponse(_ response: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: response),
          var line = String(data: data, encoding: .utf8) else {
        return
    }

    line.append("\n")
    FileHandle.standardOutput.write(Data(line.utf8))
}

func response(id: String, result: Any) -> [String: Any] {
    ["protocolVersion": protocolVersion, "id": id, "result": result]
}

func error(id: String, code: String, message: String) -> [String: Any] {
    ["protocolVersion": protocolVersion, "id": id,
     "error": ["code": code, "message": message]]
}

func containerVersion() -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/local/bin/container")
    process.arguments = ["--version"]
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return "indisponível"
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
        return "indisponível"
    }
}

while let line = readLine() {
    guard let data = line.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let id = object["id"] as? String,
          let method = object["method"] as? String else {
        writeResponse(error(id: "unknown", code: "invalid_request", message: "JSON RPC inválido"))
        continue
    }

    guard object["protocolVersion"] as? String == protocolVersion else {
        writeResponse(error(id: id, code: "unsupported_protocol", message: "Versão não suportada"))
        continue
    }

    switch method {
    case "hello", "ping":
        writeResponse(response(id: id, result: [
            "name": "DroidHatch.Native",
            "version": "0.1.0",
            "protocolVersion": protocolVersion
        ]))
    case "getCapabilities":
        writeResponse(response(id: id, result: [
            "name": "DroidHatch.Native",
            "version": "0.1.0",
            "protocolVersion": protocolVersion,
            "architecture": "arm64",
            "macOsVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "containerCli": containerVersion()
        ]))
    default:
        writeResponse(error(id: id, code: "unknown_method", message: "Método não suportado: \(method)"))
    }
}
