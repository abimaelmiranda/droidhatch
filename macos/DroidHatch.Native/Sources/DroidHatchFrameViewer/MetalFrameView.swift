import AppKit
import DroidHatchFrameTransport
import Metal
import MetalKit

final class MetalFrameView: MTKView, MTKViewDelegate {
    private struct Vertex {
        var position: SIMD2<Float>
        var textureCoordinate: SIMD2<Float>
    }

    private struct Uniforms {
        var scale: SIMD2<Float>
        var pixelFormat: UInt32
        var padding: UInt32
    }

    private let surface: MetalFrameSurface
    private let commandQueue: MTLCommandQueue?
    private let pipelineState: MTLRenderPipelineState?
    private let vertexBuffer: MTLBuffer?
    private let uniformBuffer: MTLBuffer?
    private var texture: MTLTexture?
    private var cbTexture: MTLTexture?
    private var crTexture: MTLTexture?
    private var textureWidth = 0
    private var textureHeight = 0
    private var uploadedSequence: UInt64?

    init(surface: MetalFrameSurface) {
        self.surface = surface

        guard let device = surface.device,
              let commandQueue = device.makeCommandQueue() else {
            commandQueue = nil
            pipelineState = nil
            vertexBuffer = nil
            uniformBuffer = nil
            super.init(frame: .zero, device: nil)
            return
        }

        self.commandQueue = commandQueue
        pipelineState = MetalRenderSupport.makePipeline(device: device)

        let vertices = [
            Vertex(position: SIMD2(-1, -1), textureCoordinate: SIMD2(0, 1)),
            Vertex(position: SIMD2(1, -1), textureCoordinate: SIMD2(1, 1)),
            Vertex(position: SIMD2(-1, 1), textureCoordinate: SIMD2(0, 0)),
            Vertex(position: SIMD2(1, 1), textureCoordinate: SIMD2(1, 0)),
        ]
        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<Vertex>.stride * vertices.count,
            options: .storageModeShared)
        uniformBuffer = device.makeBuffer(
            length: MemoryLayout<Uniforms>.stride,
            options: .storageModeShared)

        super.init(frame: .zero, device: device)
        configureView()
    }

    required init(coder: NSCoder) {
        surface = MetalFrameSurface()
        commandQueue = nil
        pipelineState = nil
        vertexBuffer = nil
        uniformBuffer = nil
        super.init(coder: coder)
    }

    private func configureView() {
        delegate = self
        isPaused = false
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = MetalRenderDefaults.preferredFramesPerSecond
        framebufferOnly = true
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        colorPixelFormat = .bgra8Unorm
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandQueue,
              let pipelineState,
              let vertexBuffer,
              let uniformBuffer,
              let device = view.device,
              let packet = surface.snapshot() else {
            return
        }

        guard view.drawableSize.width > 0, view.drawableSize.height > 0 else {
            return
        }

        if textureWidth != packet.width
            || textureHeight != packet.height
            || texture?.pixelFormat != (packet.pixelFormat == FrameProtocolConstants.yv12PixelFormat
                ? .r8Unorm
                : .rgba8Unorm) {
            let isYv12 = packet.pixelFormat == FrameProtocolConstants.yv12PixelFormat
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: isYv12 ? .r8Unorm : .rgba8Unorm,
                width: packet.width,
                height: packet.height,
                mipmapped: false)
            descriptor.usage = [.shaderRead]
            texture = device.makeTexture(descriptor: descriptor)
            if isYv12 {
                let chromaDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .r8Unorm,
                    width: chromaDimension(for: packet.width),
                    height: chromaDimension(for: packet.height),
                    mipmapped: false)
                chromaDescriptor.usage = [.shaderRead]
                cbTexture = device.makeTexture(descriptor: chromaDescriptor)
                crTexture = device.makeTexture(descriptor: chromaDescriptor)
            } else {
                cbTexture = nil
                crTexture = nil
            }
            textureWidth = packet.width
            textureHeight = packet.height
            uploadedSequence = nil
        }

        guard let texture else {
            return
        }

        if uploadedSequence != packet.sequence {
            packet.pixels.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else {
                    return
                }
                let region = MTLRegion(
                    origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: packet.width, height: packet.height, depth: 1))
                if packet.pixelFormat == FrameProtocolConstants.yv12PixelFormat {
                    let chromaHeight = Yv12FrameLayout.chromaHeight(for: packet.height)
                    let chromaStride = Yv12FrameLayout.chromaStride(for: packet.strideBytes)
                    let yBytes = packet.strideBytes * packet.height
                    let chromaBytes = Yv12FrameLayout.chromaPlaneBytes(
                        lumaStride: packet.strideBytes,
                        lumaHeight: packet.height)
                    guard packet.pixels.count >= yBytes + chromaBytes * Yv12FrameLayout.chromaPlaneCount,
                          let cbTexture,
                          let crTexture else {
                        return
                    }
                    texture.replace(
                        region: region,
                        mipmapLevel: 0,
                        withBytes: baseAddress,
                        bytesPerRow: packet.strideBytes)
                    let crAddress = baseAddress.advanced(by: yBytes)
                    let cbAddress = crAddress.advanced(by: chromaBytes)
                    let chromaRegion = MTLRegion(
                        origin: MTLOrigin(x: 0, y: 0, z: 0),
                        size: MTLSize(
                            width: chromaDimension(for: packet.width),
                            height: chromaHeight,
                            depth: 1))
                    crTexture.replace(
                        region: chromaRegion,
                        mipmapLevel: 0,
                        withBytes: crAddress,
                        bytesPerRow: chromaStride)
                    cbTexture.replace(
                        region: chromaRegion,
                        mipmapLevel: 0,
                        withBytes: cbAddress,
                        bytesPerRow: chromaStride)
                } else {
                    texture.replace(
                        region: region,
                        mipmapLevel: 0,
                        withBytes: baseAddress,
                        bytesPerRow: packet.strideBytes)
                }
            }
            uploadedSequence = packet.sequence
        }

        let drawableAspect = max(
            view.drawableSize.width
                / max(view.drawableSize.height, MetalRenderDefaults.minimumDrawableDimension),
            MetalRenderDefaults.minimumDrawableAspect)
        let frameAspect = CGFloat(packet.width)
            / CGFloat(max(packet.height, Int(MetalRenderDefaults.minimumDrawableDimension)))
        let scale: SIMD2<Float>
        if frameAspect > drawableAspect {
            scale = SIMD2(1, Float(drawableAspect / frameAspect))
        } else {
            scale = SIMD2(Float(frameAspect / drawableAspect), 1)
        }
        uniformBuffer.contents().storeBytes(
            of: Uniforms(scale: scale, pixelFormat: packet.pixelFormat, padding: 0),
            as: Uniforms.self)

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentTexture(cbTexture, index: 1)
        encoder.setFragmentTexture(crTexture, index: 2)
        encoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: MetalRenderDefaults.vertexCount)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func chromaDimension(for dimension: Int) -> Int {
        (dimension + Yv12FrameLayout.chromaSubsamplingFactor - 1)
            / Yv12FrameLayout.chromaSubsamplingFactor
    }
}
