struct ViewerOptions: Sendable {
    let host: String
    let port: UInt16
    let inputHost: String
    let inputPort: UInt16
    let audioSocketPath: String?
    let hidesNavigationBar: Bool
    let prefersMetal: Bool
}
