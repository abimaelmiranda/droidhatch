// AMD FidelityFX FSR 1 EASU/RCAS Metal adaptation.
// Copyright (c) 2021 Advanced Micro Devices, Inc. All rights reserved.
// See THIRD_PARTY_NOTICES.md for the upstream MIT license notice.

#include <metal_stdlib>
using namespace metal;

struct EasuUniforms { float4 con0; float4 con1; float4 con2; float4 con3; uint2 inputSize; uint2 outputSize; };
struct RcasUniforms { uint2 size; float sharpness; float padding; };
struct YuvUniforms { uint2 size; };

kernel void yuv_to_rgb_main(texture2d<float, access::sample> yTexture [[texture(0)]],
    texture2d<float, access::sample> cbTexture [[texture(1)]],
    texture2d<float, access::sample> crTexture [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    constant YuvUniforms &u [[buffer(0)]], uint2 p [[thread_position_in_grid]]) {
    if (any(p >= u.size)) return;
    constexpr sampler linearSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    float2 uv = (float2(p) + 0.5) / float2(u.size);
    float y = yTexture.sample(linearSampler, uv).r * 255.0;
    float cb = cbTexture.sample(linearSampler, uv).r * 255.0;
    float cr = crTexture.sample(linearSampler, uv).r * 255.0;
    float luma = 1.164 * (y - 16.0);
    float3 rgb = float3(luma + 1.596 * (cr - 128.0),
        luma - 0.392 * (cb - 128.0) - 0.813 * (cr - 128.0),
        luma + 2.017 * (cb - 128.0)) / 255.0;
    output.write(float4(clamp(rgb, 0.0, 1.0), 1.0), p);
}

float3 tap(texture2d<float, access::read> image, int2 p, uint2 size) {
    int2 limit = int2(size) - 1;
    return image.read(uint2(clamp(p, int2(0), limit))).rgb;
}

void easuDirection(thread float2 &dir, thread float &len, float2 pp,
    bool topLeft, bool topRight, bool bottomLeft, bool bottomRight,
    float a, float b, float c, float d, float e) {
    float w = 0.0;
    if (topLeft) w = (1.0 - pp.x) * (1.0 - pp.y);
    if (topRight) w = pp.x * (1.0 - pp.y);
    if (bottomLeft) w = (1.0 - pp.x) * pp.y;
    if (bottomRight) w = pp.x * pp.y;
    float dc = d - c;
    float cb = c - b;
    float lenX = max(abs(dc), abs(cb));
    lenX = 1.0 / max(lenX, 1.0e-6);
    float dirX = d - b;
    dir.x += dirX * w;
    lenX = saturate(abs(dirX) * lenX);
    len += lenX * lenX * w;
    float ec = e - c;
    float ca = c - a;
    float lenY = max(abs(ec), abs(ca));
    lenY = 1.0 / max(lenY, 1.0e-6);
    float dirY = e - a;
    dir.y += dirY * w;
    lenY = saturate(abs(dirY) * lenY);
    len += lenY * lenY * w;
}

void easuTap(thread float3 &color, thread float &weight, float2 offset,
    float2 direction, float2 length, float lobe, float clipPoint, float3 sampleColor) {
    float2 rotated = float2(dot(offset, direction), dot(offset, float2(-direction.y, direction.x))) * length;
    float distanceSquared = min(dot(rotated, rotated), clipPoint);
    float base = 0.4 * distanceSquared - 1.0;
    float lobed = lobe * distanceSquared - 1.0;
    base *= base;
    lobed *= lobed;
    base = 25.0 / 16.0 * base - (25.0 / 16.0 - 1.0);
    float tapWeight = base * lobed;
    color += sampleColor * tapWeight;
    weight += tapWeight;
}

float3 easu(texture2d<float, access::read> image, uint2 outputPosition, constant EasuUniforms &u) {
    float2 mapped = float2(outputPosition) * u.con0.xy + u.con0.zw;
    int2 base = int2(floor(mapped));
    float2 pp = mapped - float2(base);
    float3 b = tap(image, base + int2(0, -1), u.inputSize);
    float3 c = tap(image, base + int2(1, -1), u.inputSize);
    float3 i = tap(image, base + int2(-1, 1), u.inputSize);
    float3 j = tap(image, base + int2(0, 1), u.inputSize);
    float3 f = tap(image, base, u.inputSize);
    float3 e = tap(image, base + int2(-1, 0), u.inputSize);
    float3 k = tap(image, base + int2(1, 1), u.inputSize);
    float3 l = tap(image, base + int2(2, 1), u.inputSize);
    float3 h = tap(image, base + int2(2, 0), u.inputSize);
    float3 g = tap(image, base + int2(1, 0), u.inputSize);
    float3 o = tap(image, base + int2(1, 2), u.inputSize);
    float3 n = tap(image, base + int2(0, 2), u.inputSize);
    float lb = dot(b, float3(0.5, 1.0, 0.5));
    float lc = dot(c, float3(0.5, 1.0, 0.5));
    float li = dot(i, float3(0.5, 1.0, 0.5));
    float lj = dot(j, float3(0.5, 1.0, 0.5));
    float lf = dot(f, float3(0.5, 1.0, 0.5));
    float le = dot(e, float3(0.5, 1.0, 0.5));
    float lk = dot(k, float3(0.5, 1.0, 0.5));
    float ll = dot(l, float3(0.5, 1.0, 0.5));
    float lh = dot(h, float3(0.5, 1.0, 0.5));
    float lg = dot(g, float3(0.5, 1.0, 0.5));
    float lo = dot(o, float3(0.5, 1.0, 0.5));
    float ln = dot(n, float3(0.5, 1.0, 0.5));
    float2 direction = 0.0;
    float edgeLength = 0.0;
    easuDirection(direction, edgeLength, pp, true, false, false, false, lb, le, lf, lg, lj);
    easuDirection(direction, edgeLength, pp, false, true, false, false, lc, lf, lg, lh, lk);
    easuDirection(direction, edgeLength, pp, false, false, true, false, lf, li, lj, lk, ln);
    easuDirection(direction, edgeLength, pp, false, false, false, true, lg, lj, lk, ll, lo);
    float directionLength = dot(direction, direction);
    if (directionLength < 1.0 / 32768.0) direction = float2(1.0, 0.0);
    else direction *= rsqrt(directionLength);
    edgeLength *= 0.5;
    edgeLength *= edgeLength;
    float stretch = dot(direction, direction) / max(max(abs(direction.x), abs(direction.y)), 1.0e-6);
    float2 length = float2(1.0 + (stretch - 1.0) * edgeLength, 1.0 - 0.5 * edgeLength);
    float lobe = mix(0.5, 0.25 - 0.04, edgeLength);
    float clipPoint = 1.0 / max(lobe, 1.0e-6);
    float3 minimum = min(min(f, g), min(j, k));
    float3 maximum = max(max(f, g), max(j, k));
    float3 color = 0.0;
    float weight = 0.0;
    easuTap(color, weight, float2(0,-1)-pp, direction, length, lobe, clipPoint, b);
    easuTap(color, weight, float2(1,-1)-pp, direction, length, lobe, clipPoint, c);
    easuTap(color, weight, float2(-1,1)-pp, direction, length, lobe, clipPoint, i);
    easuTap(color, weight, float2(0,1)-pp, direction, length, lobe, clipPoint, j);
    easuTap(color, weight, float2(0,0)-pp, direction, length, lobe, clipPoint, f);
    easuTap(color, weight, float2(-1,0)-pp, direction, length, lobe, clipPoint, e);
    easuTap(color, weight, float2(1,1)-pp, direction, length, lobe, clipPoint, k);
    easuTap(color, weight, float2(2,1)-pp, direction, length, lobe, clipPoint, l);
    easuTap(color, weight, float2(2,0)-pp, direction, length, lobe, clipPoint, h);
    easuTap(color, weight, float2(1,0)-pp, direction, length, lobe, clipPoint, g);
    easuTap(color, weight, float2(1,2)-pp, direction, length, lobe, clipPoint, o);
    easuTap(color, weight, float2(0,2)-pp, direction, length, lobe, clipPoint, n);
    return clamp(color / max(weight, 1.0e-6), minimum, maximum);
}

kernel void easu_main(texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant EasuUniforms &u [[buffer(0)]], uint2 p [[thread_position_in_grid]]) {
    if (any(p >= u.outputSize)) return;
    output.write(float4(easu(input, p, u), 1.0), p);
}

kernel void rcas_main(texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant RcasUniforms &u [[buffer(0)]], uint2 p [[thread_position_in_grid]]) {
    if (any(p >= u.size)) return;
    int2 q = int2(p);
    int2 hi = int2(u.size) - 1;
    float3 b = input.read(uint2(clamp(q + int2(0,-1), int2(0), hi))).rgb;
    float3 d = input.read(uint2(clamp(q + int2(-1,0), int2(0), hi))).rgb;
    float3 e = input.read(p).rgb;
    float3 f = input.read(uint2(clamp(q + int2(1,0), int2(0), hi))).rgb;
    float3 h = input.read(uint2(clamp(q + int2(0,1), int2(0), hi))).rgb;
    float3 ringMinimum = min(min(b,d), min(f,h));
    float3 ringMaximum = max(max(b,d), max(f,h));
    float3 hitMinimum = min(ringMinimum, e) / max(4.0 * ringMaximum, 1.0e-6);
    float3 hitMaximumDenominator = 4.0 * ringMinimum - 4.0;
    float3 safeDenominator = select(
        max(hitMaximumDenominator, 1.0e-6),
        min(hitMaximumDenominator, -1.0e-6),
        hitMaximumDenominator < 0.0);
    float3 hitMaximum = (1.0 - max(ringMaximum, e)) / safeDenominator;
    float3 lobeByChannel = max(-hitMinimum, hitMaximum);
    float lobe = max(-0.1875, min(max(max(lobeByChannel.r, lobeByChannel.g), lobeByChannel.b), 0.0));
    float weight = lobe * exp2(-u.sharpness);
    float3 result = (weight * (b + d + f + h) + e) / (4.0 * weight + 1.0);
    output.write(float4(clamp(result, 0.0, 1.0), 1.0), p);
}
