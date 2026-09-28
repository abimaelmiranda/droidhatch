import CoreGraphics
import DroidHatchFrameTransport
import Foundation
import SwiftUI

@MainActor
final class ViewerModel: ObservableObject {
    @Published private(set) var image: CGImage?
    @Published private(set) var hasFrame = false
    @Published private(set) var frameDescription = "Waiting for frames..."
    @Published private(set) var errorDescription: String?
    @Published private(set) var bootLog: [String] = []
    @Published private(set) var frameSize: CGSize?
    @Published private(set) var videoDiagnostics = "FPS=-- resolution=--"
    @Published private(set) var inputDescription = "Input is connecting..."
    @Published private(set) var audioDescription = "Audio is connecting..."
    @Published private(set) var audioDiagnostics = "Audio metrics are pending..."
    @Published private(set) var diagnosticsVisible = false
    @Published var isScalingSettingsPresented = false
    @Published private(set) var upscalingOutputScale = Fsr1RenderDefaults.defaultOutputScale
    @Published private(set) var upscalingSharpness = Fsr1RenderDefaults.defaultSharpness

    private let options: ViewerOptions
    let metalSurface: MetalFrameSurface
    let usesMetal: Bool
    private var receiveTask: Task<Void, Never>?
    private var inputTask: Task<Void, Never>?
    private var audioTask: Task<Void, Never>?
    private var audioMetricsTask: Task<Void, Never>?
    private var inputConnection: InputConnection?
    private let audioPlayback = AudioPlaybackController()
    private var videoMetricsWindowStart = DispatchTime.now().uptimeNanoseconds
    private var videoFramesInMetricsWindow = 0

    private var rendererName: String {
        guard options.prefersMetal else { return "software (Metal disabled)" }
        return usesMetal ? metalSurface.rendererDescription : metalSurface.unavailableRendererDescription
    }

    init(options: ViewerOptions) {
        self.options = options
        let surface = MetalFrameSurface()
        self.metalSurface = surface
        surface.setFsr1Settings(
            outputScale: Fsr1RenderDefaults.defaultOutputScale,
            sharpness: Fsr1RenderDefaults.defaultSharpness)
        self.usesMetal = options.prefersMetal && surface.isAvailable
        self.videoDiagnostics = "FPS=-- resolution=-- render=\(self.rendererName)"
    }

    func start() {
        guard receiveTask == nil else {
            return
        }

        receiveTask = Task.detached(priority: .userInitiated) { [options] in
            var retryDelayNanoseconds = ViewerRuntimeDefaults.initialRetryDelayNanoseconds

            while !Task.isCancelled {
                do {
                    await MainActor.run {
                        self.frameDescription = "Connecting to \(options.host):\(options.port)..."
                    }

                    let connection = try FrameConnection(
                        host: options.host,
                        port: options.port,
                        readTimeoutSeconds: ViewerRuntimeDefaults.frameReadTimeoutSeconds)
                    retryDelayNanoseconds = ViewerRuntimeDefaults.initialRetryDelayNanoseconds

                    await MainActor.run {
                        self.bootLog.append("[ok] Connected to frame agent")
                        self.errorDescription = nil
                        self.frameDescription = "Connected; waiting for frames..."
                        self.resetVideoMetrics()
                    }

                    while !Task.isCancelled {
                        let message: FrameMessage
                        do {
                            message = try connection.readMessage()
                        } catch FrameTransportError.socketReadTimeout {
                            await MainActor.run {
                                self.frameDescription = "Connected; waiting for frames..."
                            }
                            continue
                        }

                        guard case let .frame(header, pixels) = message else {
                            switch message {
                            case let .error(_, message):
                                throw NSError(
                                    domain: "DroidHatchFrameViewer",
                                    code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: message])
                            case let .status(_, message):
                                await MainActor.run {
                                    self.bootLog.append(message)
                                }
                            case .hello:
                                break
                            case .frame:
                                break
                            }
                            continue
                        }

                        await MainActor.run {
                            self.accept(header: header, pixels: pixels)
                        }
                    }
                } catch is CancellationError {
                    return
                } catch {
                    await MainActor.run {
                        self.errorDescription = error.localizedDescription
                        self.frameDescription = "Reconnecting..."
                        self.bootLog.append("[error] \(error.localizedDescription)")
                    }

                    do {
                        try await Task.sleep(nanoseconds: retryDelayNanoseconds)
                    } catch is CancellationError {
                        return
                    } catch {
                        return
                    }

                    retryDelayNanoseconds = min(
                        retryDelayNanoseconds * ViewerRuntimeDefaults.retryMultiplier,
                        ViewerRuntimeDefaults.maximumRetryDelayNanoseconds)
                }
            }
        }

        inputTask = Task.detached(priority: .userInitiated) { [options] in
            var retryDelayNanoseconds = ViewerRuntimeDefaults.initialRetryDelayNanoseconds

            while !Task.isCancelled {
                let isConnected = await MainActor.run {
                    self.inputConnection != nil
                }
                if isConnected {
                    do {
                        try await Task.sleep(
                            nanoseconds: ViewerRuntimeDefaults.inputConnectionPollIntervalNanoseconds)
                    } catch is CancellationError {
                        return
                    } catch {
                        return
                    }
                    continue
                }

                do {
                    let connection = try InputConnection(
                        host: options.inputHost,
                        port: options.inputPort)
                    retryDelayNanoseconds = ViewerRuntimeDefaults.initialRetryDelayNanoseconds
                    await MainActor.run {
                        self.inputConnection = connection
                        self.inputDescription = "Input connected"
                        self.bootLog.append("[ok] Connected to input agent")
                    }
                } catch is CancellationError {
                    return
                } catch {
                    await MainActor.run {
                        self.inputDescription = "Input unavailable; retrying..."
                    }
                    do {
                        try await Task.sleep(nanoseconds: retryDelayNanoseconds)
                    } catch is CancellationError {
                        return
                    } catch {
                        return
                    }
                    retryDelayNanoseconds = min(
                        retryDelayNanoseconds * ViewerRuntimeDefaults.retryMultiplier,
                        ViewerRuntimeDefaults.maximumRetryDelayNanoseconds)
                }
            }
        }

        do {
            try audioPlayback.start()
            audioMetricsTask = Task.detached(priority: .utility) { [audioPlayback] in
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(
                            nanoseconds: ViewerRuntimeDefaults.audioMetricsIntervalNanoseconds)
                    } catch is CancellationError {
                        return
                    } catch {
                        return
                    }

                    let metrics = audioPlayback.metrics()
                    let diagnostics = "packets=\(metrics.packetCount) "
                        + "gaps=\(metrics.sequenceGapPackets) "
                        + "outOfOrder=\(metrics.outOfOrderPackets) "
                        + "packetFrames=\(metrics.totalPacketFrames) "
                        + "buffer=\(metrics.ringBuffer.occupiedFrames)/\(metrics.ringBuffer.capacityFrames) "
                        + "min=\(metrics.ringBuffer.minimumOccupiedFrames) "
                        + "max=\(metrics.ringBuffer.maximumOccupiedFrames) "
                        + "underrun=\(metrics.ringBuffer.underrunFrames) "
                        + "underrunEvents=\(metrics.ringBuffer.underrunEvents) "
                        + "overflow=\(metrics.ringBuffer.overflowFrames) "
                        + "active=\(metrics.ringBuffer.playbackStarted) "
                        + "sourceMs=\(Self.formatInterval(metrics.sourcePacketIntervalNanoseconds.averageNanoseconds)) "
                        + "arrivalMs=\(Self.formatInterval(metrics.arrivalPacketIntervalNanoseconds.averageNanoseconds)) "
                        + "renders=\(metrics.renderCallbackCount)"
                    await MainActor.run {
                        self.audioDiagnostics = diagnostics
                    }
                }
            }
            audioTask = Task.detached(priority: .userInitiated) { [options, audioPlayback] in
                var retryDelayNanoseconds = ViewerRuntimeDefaults.initialRetryDelayNanoseconds

                while !Task.isCancelled {
                    do {
                        guard let audioSocketPath = options.audioSocketPath else {
                            throw AudioTransportError.invalidEndpoint
                        }
                        let connection = try AudioConnection(
                            unixSocketPath: audioSocketPath)
                        retryDelayNanoseconds = ViewerRuntimeDefaults.initialRetryDelayNanoseconds
                        await MainActor.run {
                            self.audioDescription = "Audio connected"
                            self.bootLog.append("[ok] Connected to audio agent")
                        }

                        while !Task.isCancelled {
                            do {
                                let message = try connection.readMessage()
                                switch message {
                                case .hello:
                                    break
                                case let .format(descriptor):
                                    guard descriptor.sampleRate == UInt32(AudioPlaybackController.supportedSampleRate),
                                          descriptor.channelCount == AudioPlaybackController.supportedChannelCount,
                                          descriptor.sampleFormat == .pcmSigned16LittleEndian else {
                                        throw AudioTransportError.invalidSampleFormat(
                                            descriptor.sampleFormat.rawValue)
                                    }
                                case let .audio(packet):
                                    audioPlayback.accept(packet)
                                case let .status(message):
                                    await MainActor.run {
                                        self.bootLog.append(message)
                                    }
                                case let .error(message):
                                    throw NSError(
                                        domain: "DroidHatchAudio",
                                        code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: message])
                                case .end:
                                    throw AudioTransportError.connectionClosed
                                }
                            } catch AudioTransportError.socketReadTimeout {
                                continue
                            }
                        }
                    } catch is CancellationError {
                        return
                    } catch {
                        await MainActor.run {
                            self.audioDescription = "Audio unavailable; retrying..."
                            self.bootLog.append("[audio-error] \(error.localizedDescription)")
                        }

                        do {
                            try await Task.sleep(nanoseconds: retryDelayNanoseconds)
                        } catch is CancellationError {
                            return
                        } catch {
                            return
                        }
                        retryDelayNanoseconds = min(
                        retryDelayNanoseconds * ViewerRuntimeDefaults.retryMultiplier,
                        ViewerRuntimeDefaults.maximumRetryDelayNanoseconds)
                    }
                }
            }
        } catch {
            audioDescription = "Audio unavailable"
            bootLog.append("[error] \(error.localizedDescription)")
        }
    }

    private nonisolated static func formatInterval(_ nanoseconds: UInt64?) -> String {
        guard let nanoseconds else {
            return "-"
        }
        return String(
            format: "%.2f",
            Double(nanoseconds) / ViewerRuntimeDefaults.nanosecondsPerMillisecond)
    }

    private func resetVideoMetrics() {
        videoMetricsWindowStart = DispatchTime.now().uptimeNanoseconds
        videoFramesInMetricsWindow = 0
        hasFrame = false
        image = nil
        metalSurface.clear()
        videoDiagnostics = "FPS=-- resolution=-- render=\(rendererName)"
    }

    private func updateVideoMetrics(width: UInt32, height: UInt32) {
        videoFramesInMetricsWindow += 1
        let currentTime = DispatchTime.now().uptimeNanoseconds
        let elapsedNanoseconds = currentTime - videoMetricsWindowStart
        guard elapsedNanoseconds >= ViewerRuntimeDefaults.videoMetricsWindowNanoseconds else {
            return
        }

        let framesPerSecond = Double(videoFramesInMetricsWindow)
            * ViewerRuntimeDefaults.nanosecondsPerSecond
            / Double(elapsedNanoseconds)
        videoDiagnostics = String(
            format: "FPS=%.1f resolution=%ux%u render=%@",
            framesPerSecond,
            width,
            height,
            diagnosticRendererDescription)
        videoMetricsWindowStart = currentTime
        videoFramesInMetricsWindow = 0
    }

    private var diagnosticRendererDescription: String {
        guard metalSurface.resolvedUpscalingMode == .fsr1 else { return rendererName }
        return String(
            format: "%@ scale=%.2fx sharp=%.0f%%",
            rendererName,
            upscalingOutputScale,
            upscalingSharpness * 100)
    }

    func stop() {
        receiveTask?.cancel()
        receiveTask = nil
        inputTask?.cancel()
        inputTask = nil
        audioTask?.cancel()
        audioTask = nil
        audioMetricsTask?.cancel()
        audioMetricsTask = nil
        inputConnection = nil
        audioPlayback.stop()
    }

    func toggleDiagnostics() {
        diagnosticsVisible.toggle()
    }

    func setUpscalingMode(_ mode: UpscalingMode) {
        metalSurface.setUpscalingMode(mode)
        videoDiagnostics = "FPS=-- resolution=-- render=\(rendererName)"
    }

    func setUpscalingOutputScale(_ value: Double) {
        upscalingOutputScale = min(max(value, Fsr1RenderDefaults.minimumScale), Fsr1RenderDefaults.maximumScale)
        metalSurface.setFsr1Settings(
            outputScale: upscalingOutputScale,
            sharpness: upscalingSharpness)
    }

    func setUpscalingSharpness(_ value: Double) {
        upscalingSharpness = min(max(value, Fsr1RenderDefaults.minimumSharpness), Fsr1RenderDefaults.maximumSharpness)
        metalSurface.setFsr1Settings(
            outputScale: upscalingOutputScale,
            sharpness: upscalingSharpness)
    }

    var upscalingOutputDescription: String? {
        guard let frameSize else { return nil }
        let width = Int((frameSize.width * upscalingOutputScale).rounded())
        let height = Int((frameSize.height * upscalingOutputScale).rounded())
        return "\(width) × \(height) pixels (source: \(Int(frameSize.width)) × \(Int(frameSize.height)))"
    }

    func sendKey(usage: UInt16, action: InputKeyAction) {
        do {
            guard let connection = inputConnection else {
                inputDescription = "Input unavailable; retrying..."
                return
            }
            try connection.sendKey(usage: usage, action: action)
        } catch {
            inputConnection = nil
            inputDescription = "Input disconnected; retrying..."
            bootLog.append("[error] \(error.localizedDescription)")
        }
    }

    func sendTouch(action: InputTouchAction, normalizedX: UInt32, normalizedY: UInt32) {
        do {
            guard let connection = inputConnection else {
                inputDescription = "Input unavailable; retrying..."
                return
            }
            try connection.sendTouch(
                pointerId: ViewerRuntimeDefaults.defaultPointerId,
                action: action,
                normalizedX: normalizedX,
                normalizedY: normalizedY)
        } catch {
            inputConnection = nil
            inputDescription = "Input disconnected; retrying..."
            bootLog.append("[error] \(error.localizedDescription)")
        }
    }

    func sendScroll(_ event: ScrollInputEvent) {
        do {
            guard let connection = inputConnection else {
                inputDescription = "Input unavailable; retrying..."
                return
            }
            guard connection.supportsScroll else {
                return
            }
            try connection.sendScroll(
                deltaX: event.deltaX,
                deltaY: event.deltaY,
                phase: event.phase,
                momentumPhase: event.momentumPhase,
                flags: event.flags,
                sequence: event.sequence)
        } catch {
            inputConnection = nil
            inputDescription = "Input disconnected; retrying..."
            bootLog.append("[error] \(error.localizedDescription)")
        }
    }

    func sendSystemAction(_ action: InputSystemAction) {
        do {
            guard let connection = inputConnection else {
                inputDescription = "Input unavailable; retrying..."
                return
            }
            try connection.sendSystemAction(action)
        } catch {
            inputConnection = nil
            inputDescription = "Input disconnected; retrying..."
            bootLog.append("[error] \(error.localizedDescription)")
        }
    }

    private func accept(header: FrameHeader, pixels: Data) {
        guard header.width > 0, header.height > 0 else {
            errorDescription = "Invalid RGBA frame: \(header.width)x\(header.height)."
            return
        }

        let isYv12 = header.pixelFormat == FrameProtocolConstants.yv12PixelFormat
        let isRgba = header.pixelFormat == FrameProtocolConstants.rgba8888PixelFormat
        let requiredBytes: Int
        if isYv12 {
            let lumaStride = Int(header.strideBytes)
            let lumaHeight = Int(header.height)
            requiredBytes = Yv12FrameLayout.minimumPayloadBytes(
                lumaStride: lumaStride,
                lumaHeight: lumaHeight)
        } else if isRgba {
            guard header.strideBytes >= header.width * ViewerRuntimeDefaults.rgbaBytesPerPixel else {
                errorDescription = "Invalid RGBA stride: \(header.width)x\(header.height)."
                return
            }
            requiredBytes = Int(header.strideBytes) * Int(header.height)
        } else {
            errorDescription = "Unsupported frame format: \(header.pixelFormat)."
            return
        }

        guard pixels.count >= requiredBytes else {
            errorDescription = "Incomplete frame payload: \(pixels.count)/\(requiredBytes)."
            return
        }

        guard !isYv12 || usesMetal else {
            errorDescription = "YV12 frames require Metal rendering."
            return
        }

        let visibleHeight = Int(header.height)
        if usesMetal {
            metalSurface.submit(
                sequence: header.sequence,
                width: Int(header.width),
                height: visibleHeight,
                strideBytes: Int(header.strideBytes),
                pixelFormat: header.pixelFormat,
                pixels: pixels)
        } else {
            let visibleByteCount = Int(header.strideBytes) * visibleHeight
            let visiblePixels = Data(pixels.prefix(visibleByteCount))

            guard let provider = CGDataProvider(data: visiblePixels as CFData),
                  let image = CGImage(
                      width: Int(header.width),
                      height: visibleHeight,
                      bitsPerComponent: 8,
                      bitsPerPixel: Int(ViewerRuntimeDefaults.rgbaBytesPerPixel * 8),
                      bytesPerRow: Int(header.strideBytes),
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                      provider: provider,
                      decode: nil,
                      shouldInterpolate: false,
                      intent: .defaultIntent) else {
                errorDescription = "Could not create the frame image."
                return
            }

            self.image = image
        }

        self.hasFrame = true
        self.frameSize = CGSize(
            width: CGFloat(header.width),
            height: CGFloat(visibleHeight))
        self.errorDescription = nil
        self.frameDescription = "Video connected"
        self.updateVideoMetrics(width: header.width, height: header.height)
        if header.sequence == 0 {
            bootLog.append("[ok] First frame displayed")
        }
    }

}
