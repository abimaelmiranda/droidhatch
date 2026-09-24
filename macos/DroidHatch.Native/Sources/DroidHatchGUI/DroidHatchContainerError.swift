import Foundation

enum DroidHatchContainerError: LocalizedError {
    case commandFailed(String)
    case executableNotFound(String)
    case bootTimeout

    var errorDescription: String? {
        switch self {
        case let .commandFailed(message): return message
        case let .executableNotFound(name): return "Executável não encontrado: \(name)."
        case .bootTimeout: return "O Android não concluiu o boot dentro do tempo esperado."
        }
    }
}
