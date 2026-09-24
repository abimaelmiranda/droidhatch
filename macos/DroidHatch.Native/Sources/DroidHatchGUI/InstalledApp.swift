import Foundation

struct InstalledApp: Identifiable, Hashable {
    let alias: String
    let packageName: String
    let containerName: String
    let installedAt: String
    let iconData: Data?
    let iconMime: String?

    var id: String { alias }
}
