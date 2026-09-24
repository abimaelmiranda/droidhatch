import Foundation
import DroidHatchFrameTransport
import Metal

enum MetalRenderSupport {
    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Vertex {
        float2 position;
        float2 textureCoordinate;
    };

    struct Uniforms {
        float2 scale;
        uint pixelFormat;
        uint padding;
    };

    struct VertexOut {
        float4 position [[position]];
        float2 textureCoordinate;
    };

    constexpr uint yv12PixelFormat = \(FrameProtocolConstants.yv12PixelFormat);
    constexpr float yuvByteScale = 255.0;
    constexpr float yuvLumaOffset = 16.0;
    constexpr float yuvChromaOffset = 128.0;
    constexpr float yuvLumaScale = 1.164;
    constexpr float yuvRedChromaScale = 1.596;
    constexpr float yuvGreenBlueChromaScale = 0.392;
    constexpr float yuvGreenRedScale = 0.813;
    constexpr float yuvBlueChromaScale = 2.017;

    vertex VertexOut vertex_main(
        uint vertexID [[vertex_id]],
        const device Vertex *vertices [[buffer(0)]],
        constant Uniforms &uniforms [[buffer(1)]]) {
        Vertex inputVertex = vertices[vertexID];
        VertexOut output;
        output.position = float4(inputVertex.position * uniforms.scale, 0.0, 1.0);
        output.textureCoordinate = inputVertex.textureCoordinate;
        return output;
    }

    fragment float4 fragment_main(
        VertexOut input [[stage_in]],
        texture2d<float> yTexture [[texture(0)]],
        texture2d<float> cbTexture [[texture(1)]],
        texture2d<float> crTexture [[texture(2)]],
        constant Uniforms &uniforms [[buffer(1)]]) {
        constexpr sampler textureSampler(
            mag_filter::nearest,
            min_filter::nearest,
            address::clamp_to_edge);
        if (uniforms.pixelFormat == yv12PixelFormat) {
            float y = yTexture.sample(textureSampler, input.textureCoordinate).r * yuvByteScale;
            float cb = cbTexture.sample(textureSampler, input.textureCoordinate).r * yuvByteScale;
            float cr = crTexture.sample(textureSampler, input.textureCoordinate).r * yuvByteScale;
            float red = yuvLumaScale * (y - yuvLumaOffset)
                + yuvRedChromaScale * (cr - yuvChromaOffset);
            float green = yuvLumaScale * (y - yuvLumaOffset)
                - yuvGreenBlueChromaScale * (cb - yuvChromaOffset)
                - yuvGreenRedScale * (cr - yuvChromaOffset);
            float blue = yuvLumaScale * (y - yuvLumaOffset)
                + yuvBlueChromaScale * (cb - yuvChromaOffset);
            return float4(float3(red, green, blue) / yuvByteScale, 1.0);
        }
        return yTexture.sample(textureSampler, input.textureCoordinate);
    }
    """

    static func makePipeline(device: MTLDevice) -> MTLRenderPipelineState? {
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            guard let vertexFunction = library.makeFunction(name: "vertex_main"),
                  let fragmentFunction = library.makeFunction(name: "fragment_main") else {
                report("shader functions were not found")
                return nil
            }
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            report("pipeline creation failed: \(error)")
            return nil
        }
    }

    private static func report(_ message: String) {
        let line = "[Metal] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
