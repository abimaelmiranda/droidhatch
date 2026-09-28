import Foundation

final class DroidHatchAppInstaller: @unchecked Sendable {
    private let backend: DroidHatchContainerClient
    private let store: AppCatalogStore

    init(backend: DroidHatchContainerClient, store: AppCatalogStore) {
        self.backend = backend
        self.store = store
    }

    func install(
        apkURL: URL,
        progress: @escaping DroidHatchProgressHandler = { _ in }) throws -> DroidHatchInstallationResult {
        let packageName = try backend.installAndReturnPackageName(
            apkURL: apkURL,
            progress: progress)
        let existing = try store.findByPackageName(packageName)
        let alias: String
        if let existing {
            alias = existing.alias
        } else {
            alias = defaultAlias(for: packageName)
        }
        let icon: ApkIconAsset?
        do {
            icon = try DroidHatchApkIconExtractor().extract(from: apkURL)
        } catch {
            icon = nil
        }

        try store.save(
            alias: alias,
            packageName: packageName,
            containerName: backend.configuration.containerName,
            iconData: icon?.data,
            iconMime: icon?.mimeType)
        return DroidHatchInstallationResult(packageName: packageName, alias: alias)
    }

    private func defaultAlias(for packageName: String) -> String {
        guard let component = packageName.split(separator: ".").last.map(String.init) else {
            return packageName.replacingOccurrences(of: ".", with: "-")
        }
        let alias = component.lowercased().filter {
            $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_"
        }
        return alias.isEmpty
            ? packageName.replacingOccurrences(of: ".", with: "-")
            : alias
    }
}
