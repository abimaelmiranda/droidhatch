public struct DroidHatchViewerConfiguration: Sendable {
    let host: String
    let framePort: UInt16
    let inputPort: UInt16
    let audioSocketPath: String

    public init(
        host: String,
        framePort: UInt16,
        inputPort: UInt16,
        audioSocketPath: String) {
        self.host = host
        self.framePort = framePort
        self.inputPort = inputPort
        self.audioSocketPath = audioSocketPath
    }
}
