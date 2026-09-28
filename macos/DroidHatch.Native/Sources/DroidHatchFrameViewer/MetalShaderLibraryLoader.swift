import Foundation
import Metal

enum MetalShaderLibraryLoader {
    enum LoadingError: LocalizedError {
        case resourceNotFound(String)
        case sourceUnreadable(String, String)

        var errorDescription: String? {
            switch self {
            case let .resourceNotFound(name):
                return "Metal shader resource '\(name).metal' was not found in the app bundle."
            case let .sourceUnreadable(name, reason):
                return "Metal shader resource '\(name).metal' could not be read: \(reason)"
            }
        }
    }

    static func load(named name: String, device: MTLDevice) throws -> MTLLibrary {
        guard let resourceURL = Bundle.module.url(
            forResource: name,
            withExtension: "metal",
            subdirectory: "Shaders") else {
            throw LoadingError.resourceNotFound(name)
        }

        let source: String
        do {
            source = try String(contentsOf: resourceURL, encoding: .utf8)
        } catch {
            throw LoadingError.sourceUnreadable(name, error.localizedDescription)
        }

        return try device.makeLibrary(source: source, options: nil)
    }
}
