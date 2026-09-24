import Foundation

struct ProbeOptions {
    let host: String
    let port: UInt16
    let frameCount: Int?
    let durationSeconds: Double?
    let snapshotIntervalSeconds: Double?
    let readTimeoutSeconds: Double
    let continueOnTimeout: Bool
    let outputDirectory: URL
}
