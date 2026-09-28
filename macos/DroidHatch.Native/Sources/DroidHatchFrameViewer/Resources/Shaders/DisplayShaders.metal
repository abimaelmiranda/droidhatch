#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float2 position;
    float2 textureCoordinate;
};

struct Uniforms {
    float2 scale;
    uint isYv12;
    uint padding;
};

struct VertexOut {
    float4 position [[position]];
    float2 textureCoordinate;
};

constant float yuvByteScale = 255.0;
constant float yuvLumaOffset = 16.0;
constant float yuvChromaOffset = 128.0;
constant float yuvLumaScale = 1.164;
constant float yuvRedChromaScale = 1.596;
constant float yuvGreenBlueChromaScale = 0.392;
constant float yuvGreenRedScale = 0.813;
constant float yuvBlueChromaScale = 2.017;

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

float4 convert_yuv(float ySample, float cbSample, float crSample) {
    float y = ySample * yuvByteScale;
    float cb = cbSample * yuvByteScale;
    float cr = crSample * yuvByteScale;
    float red = yuvLumaScale * (y - yuvLumaOffset)
        + yuvRedChromaScale * (cr - yuvChromaOffset);
    float green = yuvLumaScale * (y - yuvLumaOffset)
        - yuvGreenBlueChromaScale * (cb - yuvChromaOffset)
        - yuvGreenRedScale * (cr - yuvChromaOffset);
    float blue = yuvLumaScale * (y - yuvLumaOffset)
        + yuvBlueChromaScale * (cb - yuvChromaOffset);
    return float4(float3(red, green, blue) / yuvByteScale, 1.0);
}

fragment float4 fragment_main(
    VertexOut input [[stage_in]],
    texture2d<float> yTexture [[texture(0)]],
    texture2d<float> cbTexture [[texture(1)]],
    texture2d<float> crTexture [[texture(2)]],
    constant Uniforms &uniforms [[buffer(1)]]) {
    constexpr sampler textureSampler(
        mag_filter::linear,
        min_filter::linear,
        address::clamp_to_edge);
    if (uniforms.isYv12 != 0) {
        float y = yTexture.sample(textureSampler, input.textureCoordinate).r;
        float cb = cbTexture.sample(textureSampler, input.textureCoordinate).r;
        float cr = crTexture.sample(textureSampler, input.textureCoordinate).r;
        return convert_yuv(y, cb, cr);
    }
    return yTexture.sample(textureSampler, input.textureCoordinate);
}

fragment float4 fragment_nearest_main(
    VertexOut input [[stage_in]], texture2d<float> yTexture [[texture(0)]],
    texture2d<float> cbTexture [[texture(1)]], texture2d<float> crTexture [[texture(2)]],
    constant Uniforms &uniforms [[buffer(1)]]) {
    constexpr sampler textureSampler(
        mag_filter::nearest, min_filter::nearest, address::clamp_to_edge);
    if (uniforms.isYv12 != 0) {
        float y = yTexture.sample(textureSampler, input.textureCoordinate).r;
        float cb = cbTexture.sample(textureSampler, input.textureCoordinate).r;
        float cr = crTexture.sample(textureSampler, input.textureCoordinate).r;
        return convert_yuv(y, cb, cr);
    }
    return yTexture.sample(textureSampler, input.textureCoordinate);
}
