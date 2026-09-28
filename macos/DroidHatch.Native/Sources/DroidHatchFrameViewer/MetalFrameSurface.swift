import Foundation
import Metal

final class MetalFrameSurface {
    struct Packet {
        let sequence: UInt64
        let width: Int
        let height: Int
        let strideBytes: Int
        let pixelFormat: UInt32
        let pixels: Data
    }

    let device: MTLDevice?
    let commandQueue: MTLCommandQueue?
    let isAvailable: Bool
    let unavailableRendererDescription: String
    let linearPipeline: MTLRenderPipelineState?
    let nearestPipeline: MTLRenderPipelineState?
    let fsr1Pipelines: (convert: MTLComputePipelineState, easu: MTLComputePipelineState, rcas: MTLComputePipelineState)?
    private var latestPacket: Packet?
    private var selectedUpscalingMode = UpscalingMode.defaultMode
    private var fsr1OutputScale = Fsr1RenderDefaults.defaultOutputScale
    private var fsr1Sharpness = Fsr1RenderDefaults.defaultSharpness
    private var fsr1RuntimeUnavailable = false
    private let lock = NSLock()

    init() {
        let candidate = MTLCreateSystemDefaultDevice()
        let commandQueue = candidate?.makeCommandQueue()
        device = candidate
        self.commandQueue = commandQueue
        let renderPipelineBuild = candidate.map(MetalRenderSupport.makePipelines)
        let renderPipelines = renderPipelineBuild?.pipelines
        linearPipeline = renderPipelines?.linear
        nearestPipeline = renderPipelines?.nearest
        fsr1Pipelines = candidate.flatMap(Fsr1MetalSupport.makePipelines)
        if candidate == nil {
            unavailableRendererDescription = "software (Metal device unavailable)"
        } else if commandQueue == nil {
            unavailableRendererDescription = "software (Metal command queue unavailable)"
        } else if renderPipelines == nil {
            let reason = renderPipelineBuild?.failureReason ?? "unknown error"
            unavailableRendererDescription = "software (Metal pipeline: \(reason))"
        } else {
            unavailableRendererDescription = "software"
        }
        isAvailable = commandQueue != nil && renderPipelines != nil
    }

    func submit(
        sequence: UInt64,
        width: Int,
        height: Int,
        strideBytes: Int,
        pixelFormat: UInt32,
        pixels: Data) {
        let packet = Packet(
            sequence: sequence,
            width: width,
            height: height,
            strideBytes: strideBytes,
            pixelFormat: pixelFormat,
            pixels: pixels)
        lock.lock()
        defer { lock.unlock() }
        latestPacket = packet
    }

    func snapshot() -> Packet? {
        lock.lock()
        defer { lock.unlock() }
        return latestPacket
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        latestPacket = nil
    }

    func setUpscalingMode(_ mode: UpscalingMode) {
        lock.lock()
        defer { lock.unlock() }
        selectedUpscalingMode = mode
        if mode == .fsr1 {
            fsr1RuntimeUnavailable = false
        }
    }

    func upscalingMode() -> UpscalingMode {
        lock.lock()
        defer { lock.unlock() }
        return selectedUpscalingMode
    }

    func setFsr1Settings(outputScale: Double, sharpness: Double) {
        lock.lock()
        defer { lock.unlock() }
        fsr1OutputScale = min(max(outputScale, Fsr1RenderDefaults.minimumScale), Fsr1RenderDefaults.maximumScale)
        fsr1Sharpness = min(
            max(sharpness, Fsr1RenderDefaults.minimumSharpness),
            Fsr1RenderDefaults.maximumSharpness)
    }

    func fsr1Settings() -> (outputScale: Double, sharpness: Double) {
        lock.lock()
        defer { lock.unlock() }
        return (fsr1OutputScale, fsr1Sharpness)
    }

    func markFsr1UnavailableAtRuntime() {
        lock.lock()
        defer { lock.unlock() }
        fsr1RuntimeUnavailable = true
    }

    var resolvedUpscalingMode: UpscalingMode {
        let requestedMode = upscalingMode()
        if requestedMode == .fsr1,
           fsr1Pipelines == nil || runtimeFsr1Unavailable {
            return .linear
        }
        return requestedMode
    }

    private var runtimeFsr1Unavailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return fsr1RuntimeUnavailable
    }

    var rendererDescription: String {
        guard isAvailable else { return "software" }
        if upscalingMode() == .fsr1,
           fsr1Pipelines == nil || runtimeFsr1Unavailable {
            return "metal-linear (FSR1 fallback)"
        }
        return "metal-\(resolvedUpscalingMode.rawValue)"
    }
}
