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
        guard let apkType = UTType(filenameExtension: "apk") else {
            status = "Não foi possível reconhecer arquivos APK."
            return
        }
        panel.allowedContentTypes = [apkType]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let backend else {
            status = "Backend indisponível."
            return
        }

        guard let operationID = beginOperation(status: "Instalando APK…") else { return }
        let installer = DroidHatchAppInstaller(backend: backend, store: store)
        let progress = statusUpdater(for: operationID)
        Task.detached { [weak self, installer] in
            do {
                let result = try installer.install(apkURL: url, progress: progress)
                await MainActor.run {
                    guard let self,
                          self.activeOperationID == operationID else { return }
                    self.finishOperation(
                        operationID,
                        status: "\(result.packageName) instalado como \(result.alias)")
                    self.reload()
                }
            } catch {
                await MainActor.run {
                    self?.finishOperation(operationID, status: error.localizedDescription)
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

        guard let operationID = beginOperation(status: "Removendo \(selectedApp.alias)…") else { return }
        viewerController.close()
        let progress = statusUpdater(for: operationID)
        Task.detached { [weak self, backend, selectedApp] in
            do {
                try backend.uninstall(packageName: selectedApp.packageName, progress: progress)
                await MainActor.run {
                    do {
                        guard let self,
                              self.activeOperationID == operationID else { return }
                        try self.store.remove(alias: selectedApp.alias)
                        self.finishOperation(operationID, status: "Aplicativo removido")
                        self.selectedAlias = nil
                        self.reload()
                    } catch {
                        self?.finishOperation(operationID, status: error.localizedDescription)
                    }
                }
            } catch {
                await MainActor.run {
                    self?.finishOperation(operationID, status: error.localizedDescription)
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

        guard let operationID = beginOperation(status: "Abrindo \(selectedApp.alias)…") else { return }
        let progress = statusUpdater(for: operationID)
        Task.detached { [weak self, backend, selectedApp] in
            do {
                try backend.open(packageName: selectedApp.packageName, progress: progress)
                await MainActor.run {
                    guard let self,
                          self.activeOperationID == operationID else { return }
                    self.viewerController.show(
                        configuration: DroidHatchViewerConfiguration(
                            host: backend.configuration.host,
                            framePort: UInt16(backend.configuration.framePort),
                            inputPort: UInt16(backend.configuration.inputPort),
                            audioSocketPath: backend.configuration.hostAudioSocket.path))
                    self.finishOperation(operationID, status: "\(selectedApp.alias) aberto")
                }
            } catch {
                await MainActor.run {
                    self?.finishOperation(operationID, status: error.localizedDescription)
                }
            }
        }
    }

    private func handleViewerClosed() {
        guard let backend else {
            status = "Sessão encerrada"
            return
        }

        guard let operationID = beginOperation(status: "Encerrando sessão…") else { return }
        Task.detached { [weak self, backend] in
            do {
                try backend.close()
                await MainActor.run {
                    self?.finishOperation(operationID, status: "Sessão encerrada")
                }
            } catch {
                await MainActor.run {
                    self?.finishOperation(operationID, status: error.localizedDescription)
                }
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
        guard let operationID = beginOperation(status: "Verificando o backend…") else { return }
        let progress = statusUpdater(for: operationID)
        Task.detached { [weak self, backend] in
            do {
                try backend.ensureRunning(progress: progress)
                await MainActor.run {
                    self?.finishOperation(operationID, status: "Backend pronto")
                }
            } catch {
                await MainActor.run {
                    self?.finishOperation(operationID, status: error.localizedDescription)
                }
            }
        }
    }

    private func beginOperation(status: String) -> UUID? {
        guard activeOperationID == nil else { return nil }
        let operationID = UUID()
        activeOperationID = operationID
        isBusy = true
        self.status = status
        return operationID
    }

    private func finishOperation(_ operationID: UUID, status: String) {
        guard activeOperationID == operationID else { return }
        activeOperationID = nil
        isBusy = false
        self.status = status
    }

    private func statusUpdater(for operationID: UUID) -> DroidHatchProgressHandler {
        { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self,
                      self.activeOperationID == operationID else { return }
                self.status = message
            }
        }
    }

}
