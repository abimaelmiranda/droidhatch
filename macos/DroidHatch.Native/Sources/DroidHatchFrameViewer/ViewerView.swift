import SwiftUI

struct ViewerWindow: View {
    @StateObject private var model: ViewerModel

    init(options: ViewerOptions) {
        _model = StateObject(wrappedValue: ViewerModel(options: options))
    }

    var body: some View {
        ZStack {
            Color.black

            if model.usesMetal {
                MetalFrameViewRepresentable(surface: model.metalSurface)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            } else if let image = model.image {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }

            if !model.hasFrame {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("DroidHatch is starting")
                        .foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(model.bootLog.enumerated()), id: \.offset) { _, message in
                            Text(message)
                                .font(.caption.monospaced())
                                .foregroundStyle(message.hasPrefix("[error]") ? .red : .white)
                        }
                    }
                    .frame(maxWidth: 560, alignment: .leading)
                    if let errorDescription = model.errorDescription {
                        Text(errorDescription)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
            }
        }
        .overlay {
            InputCaptureViewRepresentable(
                frameSize: model.frameSize,
                sendKey: { usage, action in
                    model.sendKey(usage: usage, action: action)
                },
                sendTouch: { action, x, y in
                    model.sendTouch(action: action, normalizedX: x, normalizedY: y)
                },
                sendScroll: { event in
                    model.sendScroll(event)
                },
                sendSystemAction: { action in
                    model.sendSystemAction(action)
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .topTrailing) {
            if model.diagnosticsVisible {
                DiagnosticsOverlay(
                    videoDescription: model.frameDescription,
                    videoDiagnostics: model.videoDiagnostics,
                    inputDescription: model.inputDescription,
                    audioDescription: model.audioDescription,
                    audioDiagnostics: model.audioDiagnostics)
            }
        }
        .task {
            model.start()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: DroidHatchViewerNotifications.playPauseShortcut)) { _ in
                    model.sendSystemAction(.playPause)
                }
        .onReceive(
            NotificationCenter.default.publisher(
                for: DroidHatchViewerNotifications.toggleDiagnostics)) { _ in
                    model.toggleDiagnostics()
                }
        .onReceive(
            NotificationCenter.default.publisher(
                for: DroidHatchViewerNotifications.setUpscalingMode)) { notification in
                    guard let rawMode = notification.object as? String,
                          let mode = UpscalingMode(rawValue: rawMode) else { return }
                    model.setUpscalingMode(mode)
                }
        .onReceive(
            NotificationCenter.default.publisher(
                for: DroidHatchViewerNotifications.showUpscalingSettings)) { _ in
                    model.isScalingSettingsPresented = true
                }
        .sheet(isPresented: $model.isScalingSettingsPresented) {
            VideoUpscalingSettingsView(model: model)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: DroidHatchViewerNotifications.didShow)) { _ in
                    model.start()
                }
        .onReceive(
            NotificationCenter.default.publisher(
                for: DroidHatchViewerNotifications.didClose)) { _ in
                    model.stop()
                }
        .onDisappear {
            model.stop()
        }
    }
}
