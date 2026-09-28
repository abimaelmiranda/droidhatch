import Foundation
import Metal

enum Fsr1MetalSupport {
    static func makePipelines(device: MTLDevice) -> (convert: MTLComputePipelineState, easu: MTLComputePipelineState, rcas: MTLComputePipelineState)? {
        do {
            let library = try MetalShaderLibraryLoader.load(
                named: "Fsr1Shaders",
                device: device)
            guard let convert = library.makeFunction(name: "yuv_to_rgb_main"),
                  let easu = library.makeFunction(name: "easu_main"),
                  let rcas = library.makeFunction(name: "rcas_main") else { return nil }
            return (try device.makeComputePipelineState(function: convert),
                    try device.makeComputePipelineState(function: easu),
                    try device.makeComputePipelineState(function: rcas))
        } catch {
            FileHandle.standardError.write(Data("[Metal] FSR1 pipeline unavailable: \(error)\n".utf8))
            return nil
        }
    }
}
