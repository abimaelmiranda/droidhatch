import Foundation

enum Yv12FrameLayout {
    static let chromaSubsamplingFactor = 2
    static let chromaPlaneCount = 2
    static let strideAlignment = 16

    static func chromaStride(for lumaStride: Int) -> Int {
        let unalignedStride = lumaStride / chromaSubsamplingFactor
        let alignedUnitCount = (unalignedStride + strideAlignment - 1) / strideAlignment
        return alignedUnitCount * strideAlignment
    }

    static func chromaHeight(for lumaHeight: Int) -> Int {
        (lumaHeight + chromaSubsamplingFactor - 1) / chromaSubsamplingFactor
    }

    static func chromaPlaneBytes(lumaStride: Int, lumaHeight: Int) -> Int {
        chromaStride(for: lumaStride) * chromaHeight(for: lumaHeight)
    }

    static func minimumPayloadBytes(lumaStride: Int, lumaHeight: Int) -> Int {
        let lumaPlaneBytes = lumaStride * lumaHeight
        let chromaBytes = chromaPlaneBytes(
            lumaStride: lumaStride,
            lumaHeight: lumaHeight)
        return lumaPlaneBytes + chromaBytes * chromaPlaneCount
    }
}
