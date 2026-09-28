import AppKit
import DroidHatchViewer
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LauncherModel: ObservableObject {
    @Published private(set) var apps: [InstalledApp] = []
    @Published var selectedAlias: String?
    @Published private(set) var isBusy = false
    @Published private(set) var status = "Pronto"

    private let store = AppCatalogStore()
    private var backend: DroidHatchContainerClient?
    private let viewerController = DroidHatchViewerController()
    private var terminationObserver: NSObjectProtocol?
    private var pictureInPictureObserver: NSObjectProtocol?
    private var activeOperationID: UUID?

    init() {
        do {
            backend = try DroidHatchContainerClient()
            status = "Verificando backend…"
        } catch {
            status = error.localizedDescription
        }
        viewerController.onClose = { [weak self] in
            self?.handleViewerClosed()
        }
        viewerController.setPictureInPictureEnabled(
            UserDefaults.standard.bool(
                forKey: ViewerPictureInPicturePreference.defaultsKey))
        pictureInPictureObserver = NotificationCenter.default.addObserver(
            forName: ViewerPictureInPicturePreference.didChange,
            object: nil,
            queue: .main) { [weak self] notification in
                guard let isEnabled = notification.object as? Bool else { return }
                Task { @MainActor in
                    self?.viewerController.setPictureInPictureEnabled(isEnabled)
                }
            }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.shutdown()
                }
            }
        reload()
        prepareBackend()
    }

    var selectedApp: InstalledApp? {
        apps.first { $0.alias == selectedAlias }
    }

    func reload() {
        do {
            apps = try store.loadApps()
            if selectedAlias == nil {
                selectedAlias = apps.first?.alias
            }
            if apps.isEmpty && !isBusy {
                status = "Nenhum aplicativo instalado"
            }
        } catch {
            status = error.localizedDescription
        }
    }

    func install() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "apk")!]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let backend else {
            status = "Backend indisponível."
            return
        }

        isBusy = true
        status = "Instalando APK…"
        let installer = DroidHatchAppInstaller(backend: backend, store: store)
        Task.detached { [weak self, installer] in
            do {
                let result = try installer.install(apkURL: url)
                await MainActor.run {
                    guard let self else { return }
                    self.isBusy = false
                    self.status = "\(result.packageName) instalado como \(result.alias)"
                    self.reload()
                }
            } catch {
                await MainActor.run {
                    self?.isBusy = false
                    self?.status = error.localizedDescription
                }
            }
        }
    }

    func removeSelected() {
        guard let selectedApp else { return }
        guard let backend else {
            status = "Backend indisponível."
            return
        }

        viewerController.close()
        isBusy = true
        status = "Removendo \(selectedApp.alias)…"
        Task.detached { [weak self, backend, selectedApp] in
            do {
                try backend.uninstall(packageName: selectedApp.packageName)
                await MainActor.run {
                    do {
                        guard let self else { return }
                        try self.store.remove(alias: selectedApp.alias)
                        self.isBusy = false
                        self.status = "Aplicativo removido"
                        self.selectedAlias = nil
                        self.reload()
                    } catch {
                        self?.isBusy = false
                        self?.status = error.localizedDescription
                    }
                }
            } catch {
                await MainActor.run {
                    self?.isBusy = false
                    self?.status = error.localizedDescription
                }
            }
        }
    }

    func openSelected() {
        guard let selectedApp else { return }
        guard let backend else {
            status = "Backend indisponível."
            return
        }

        isBusy = true
        status = "Abrindo \(selectedApp.alias)…"
        Task.detached { [weak self, backend, selectedApp] in
            do {
                try backend.open(packageName: selectedApp.packageName)
                await MainActor.run {
                    guard let self else { return }
                    self.viewerController.show(
                        configuration: DroidHatchViewerConfiguration(
                            host: backend.configuration.host,
                            framePort: UInt16(backend.configuration.framePort),
                            inputPort: UInt16(backend.configuration.inputPort),
                            audioSocketPath: backend.configuration.hostAudioSocket.path))
                    self.isBusy = false
                    self.status = "\(selectedApp.alias) aberto"
                }
            } catch {
                await MainActor.run {
                    self?.isBusy = false
                    self?.status = error.localizedDescription
                }
            }
        }
    }

    private func handleViewerClosed() {
        guard let backend else {
            status = "Sessão encerrada"
            return
        }

        isBusy = true
        status = "Encerrando sessão…"
        Task.detached { [weak self, backend] in
            try? backend.close()
            await MainActor.run {
                self?.isBusy = false
                self?.status = "Sessão encerrada"
            }
        }
    }

    private func shutdown() {
        viewerController.close()
        guard let backend else { return }
        Task.detached {
            try? backend.close()
        }
    }

    private func prepareBackend() {
        guard let backend else { return }
        Task.detached { [weak self, backend] in
            do {
                try backend.ensureRunning()
                await MainActor.run {
                    guard let self, !self.isBusy else { return }
                    self.status = "Backend pronto"
                }
            } catch {
                await MainActor.run {
                    self?.status = error.localizedDescription
                }
            }
        }
    }

}
