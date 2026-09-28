import Foundation
import Metal

enum MetalRenderSupport {
    struct PipelineBuildResult {
        let pipelines: (linear: MTLRenderPipelineState, nearest: MTLRenderPipelineState)?
        let failureReason: String?
    }

    static func makePipelines(device: MTLDevice) -> PipelineBuildResult {
        do {
            let library = try MetalShaderLibraryLoader.load(
                named: "DisplayShaders",
                device: device)
            let descriptor = MTLRenderPipelineDescriptor()
            guard let vertexFunction = library.makeFunction(name: "vertex_main"),
                  let linearFunction = library.makeFunction(name: "fragment_main"),
                  let nearestFunction = library.makeFunction(name: "fragment_nearest_main") else {
                let reason = "Metal shader entry point missing"
                report(reason)
                return PipelineBuildResult(pipelines: nil, failureReason: reason)
            }
            descriptor.vertexFunction = vertexFunction
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.fragmentFunction = linearFunction
            let linear = try device.makeRenderPipelineState(descriptor: descriptor)
            descriptor.fragmentFunction = nearestFunction
            let nearest = try device.makeRenderPipelineState(descriptor: descriptor)
            return PipelineBuildResult(
                pipelines: (linear, nearest),
                failureReason: nil)
        } catch {
            let reason = error.localizedDescription
                .replacingOccurrences(of: "\n", with: " ")
                .prefix(280)
            let message = String(reason)
            report("pipeline creation failed: \(message)")
            return PipelineBuildResult(pipelines: nil, failureReason: message)
        }
    }

    private static func report(_ message: String) {
        let line = "[Metal] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
