import Metal
import DroidHatchFrameTransport

final class Fsr1FrameProcessor {
    private struct YuvUniforms {
        var size: SIMD2<UInt32>
    }

    private struct EasuUniforms {
        var con0: SIMD4<Float>
        var con1: SIMD4<Float>
        var con2: SIMD4<Float>
        var con3: SIMD4<Float>
        var inputSize: SIMD2<UInt32>
        var outputSize: SIMD2<UInt32>
    }

    private struct RcasUniforms {
        var size: SIMD2<UInt32>
        var sharpness: Float
        var padding: Float = 0
    }

    private let device: MTLDevice
    private let pipelines: (convert: MTLComputePipelineState, easu: MTLComputePipelineState, rcas: MTLComputePipelineState)
    private var convertedTexture: MTLTexture?
    private var easuTexture: MTLTexture?
    private var outputTexture: MTLTexture?
    private var sourceSize = SIMD2<Int>(0, 0)
    private var outputSize = SIMD2<Int>(0, 0)
    private var lastProcessedSequence: UInt64?
    private var lastPixelFormat: UInt32?
    private var lastSharpness: Float?

    init(device: MTLDevice, pipelines: (convert: MTLComputePipelineState, easu: MTLComputePipelineState, rcas: MTLComputePipelineState)) {
        self.device = device
        self.pipelines = pipelines
    }

    func encode(
        commandBuffer: MTLCommandBuffer,
        yTexture: MTLTexture,
        cbTexture: MTLTexture?,
        crTexture: MTLTexture?,
        pixelFormat: UInt32,
        inputWidth: Int,
        inputHeight: Int,
        sequence: UInt64,
        requestedScale: Double,
        sharpness: Double) -> MTLTexture? {
        let targetSize = scaledSize(
            inputWidth: inputWidth,
            inputHeight: inputHeight,
            requestedScale: requestedScale)
        let needsYuvConversion = pixelFormat == FrameProtocolConstants.yv12PixelFormat
        guard ensureTextures(
            inputWidth: inputWidth,
            inputHeight: inputHeight,
            outputSize: targetSize,
            needsYuvConversion: needsYuvConversion) else {
            return nil
        }
        let normalizedSharpness = Float(sharpness)
        if lastProcessedSequence == sequence,
           lastPixelFormat == pixelFormat,
           lastSharpness == normalizedSharpness,
           self.outputSize == targetSize {
            return outputTexture
        }

        let sourceTexture: MTLTexture
        if needsYuvConversion {
            guard let cbTexture, let crTexture, let convertedTexture else { return nil }
            var uniforms = YuvUniforms(size: SIMD2(UInt32(inputWidth), UInt32(inputHeight)))
            guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
            encoder.setComputePipelineState(pipelines.convert)
            encoder.setTexture(yTexture, index: 0)
            encoder.setTexture(cbTexture, index: 1)
            encoder.setTexture(crTexture, index: 2)
            encoder.setTexture(convertedTexture, index: 3)
            encoder.setBytes(&uniforms, length: MemoryLayout<YuvUniforms>.stride, index: 0)
            dispatch(encoder, pipeline: pipelines.convert, width: inputWidth, height: inputHeight)
            encoder.endEncoding()
            sourceTexture = convertedTexture
        } else {
            sourceTexture = yTexture
        }

        guard let easuTexture, let outputTexture,
              let easuEncoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        let constants = Fsr1EasuConstants(
            inputWidth: inputWidth,
            inputHeight: inputHeight,
            outputWidth: targetSize.x,
            outputHeight: targetSize.y)
        var easuUniforms = EasuUniforms(
            con0: constants.con0,
            con1: constants.con1,
            con2: constants.con2,
            con3: constants.con3,
            inputSize: SIMD2(UInt32(inputWidth), UInt32(inputHeight)),
            outputSize: SIMD2(UInt32(targetSize.x), UInt32(targetSize.y)))
        easuEncoder.setComputePipelineState(pipelines.easu)
        easuEncoder.setTexture(sourceTexture, index: 0)
        easuEncoder.setTexture(easuTexture, index: 1)
        easuEncoder.setBytes(&easuUniforms, length: MemoryLayout<EasuUniforms>.stride, index: 0)
        dispatch(easuEncoder, pipeline: pipelines.easu, width: targetSize.x, height: targetSize.y)
        easuEncoder.endEncoding()

        var rcasUniforms = RcasUniforms(
            size: SIMD2(UInt32(targetSize.x), UInt32(targetSize.y)),
            sharpness: (1 - normalizedSharpness) * Fsr1RenderDefaults.sharpnessStopRange)
        guard let rcasEncoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        rcasEncoder.setComputePipelineState(pipelines.rcas)
        rcasEncoder.setTexture(easuTexture, index: 0)
        rcasEncoder.setTexture(outputTexture, index: 1)
        rcasEncoder.setBytes(&rcasUniforms, length: MemoryLayout<RcasUniforms>.stride, index: 0)
        dispatch(rcasEncoder, pipeline: pipelines.rcas, width: targetSize.x, height: targetSize.y)
        rcasEncoder.endEncoding()
        lastProcessedSequence = sequence
        lastPixelFormat = pixelFormat
        lastSharpness = normalizedSharpness
        return outputTexture
    }

    private func ensureTextures(
        inputWidth: Int,
        inputHeight: Int,
        outputSize: SIMD2<Int>,
        needsYuvConversion: Bool) -> Bool {
        let inputSize = SIMD2(inputWidth, inputHeight)
        let inputSizeChanged = sourceSize != inputSize
        let outputSizeChanged = self.outputSize != outputSize
        if inputSizeChanged {
            sourceSize = inputSize
            convertedTexture = nil
        }
        if outputSizeChanged {
            self.outputSize = outputSize
        }
        if inputSizeChanged || outputSizeChanged {
            lastProcessedSequence = nil
            lastSharpness = nil
            lastPixelFormat = nil
        }

        if needsYuvConversion, convertedTexture == nil {
            convertedTexture = makeTexture(width: inputWidth, height: inputHeight, format: .rgba8Unorm)
        } else if !needsYuvConversion {
            convertedTexture = nil
        }

        if outputSizeChanged || easuTexture == nil {
            easuTexture = makeTexture(width: outputSize.x, height: outputSize.y, format: .rgba16Float)
        }
        if outputSizeChanged || self.outputTexture == nil {
            self.outputTexture = makeTexture(width: outputSize.x, height: outputSize.y, format: .rgba16Float)
        }

        let conversionTextureAvailable = !needsYuvConversion || convertedTexture != nil
        return conversionTextureAvailable && easuTexture != nil && self.outputTexture != nil
    }

    private func makeTexture(width: Int, height: Int, format: MTLPixelFormat) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: width,
            height: height,
            mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }

    private func scaledSize(inputWidth: Int, inputHeight: Int, requestedScale: Double) -> SIMD2<Int> {
        let scale = min(max(CGFloat(requestedScale), Fsr1RenderDefaults.minimumScale),
            Fsr1RenderDefaults.maximumScale)
        return SIMD2(
            max(inputWidth, Int((CGFloat(inputWidth) * scale).rounded())),
            max(inputHeight, Int((CGFloat(inputHeight) * scale).rounded())))
    }

    private func dispatch(_ encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, width: Int, height: Int) {
        let threads = MTLSize(width: Fsr1RenderDefaults.threadgroupWidth, height: Fsr1RenderDefaults.threadgroupHeight, depth: 1)
        let groups = MTLSize(
            width: (width + threads.width - 1) / threads.width,
            height: (height + threads.height - 1) / threads.height,
            depth: 1)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threads)
    }
}
