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
    let isAvailable: Bool
    private var latestPacket: Packet?
    private let lock = NSLock()

    init() {
        let candidate = MTLCreateSystemDefaultDevice()
        device = candidate
        isAvailable = candidate?.makeCommandQueue() != nil
            && candidate.flatMap(MetalRenderSupport.makePipeline) != nil
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
}
