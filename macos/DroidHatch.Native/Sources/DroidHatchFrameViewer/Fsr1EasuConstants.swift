import simd

struct Fsr1EasuConstants {
    let con0: SIMD4<Float>
    let con1: SIMD4<Float>
    let con2: SIMD4<Float>
    let con3: SIMD4<Float>

    init(inputWidth: Int, inputHeight: Int, outputWidth: Int, outputHeight: Int) {
        let inputWidthFloat = Float(inputWidth)
        let inputHeightFloat = Float(inputHeight)
        let outputWidthFloat = Float(outputWidth)
        let outputHeightFloat = Float(outputHeight)
        let reciprocalInputWidth = 1 / inputWidthFloat
        let reciprocalInputHeight = 1 / inputHeightFloat

        con0 = SIMD4(
            inputWidthFloat / outputWidthFloat,
            inputHeightFloat / outputHeightFloat,
            0.5 * inputWidthFloat / outputWidthFloat - 0.5,
            0.5 * inputHeightFloat / outputHeightFloat - 0.5)
        con1 = SIMD4(
            reciprocalInputWidth,
            reciprocalInputHeight,
            reciprocalInputWidth,
            -reciprocalInputHeight)
        con2 = SIMD4(
            -reciprocalInputWidth,
            2 * reciprocalInputHeight,
            reciprocalInputWidth,
            2 * reciprocalInputHeight)
        con3 = SIMD4(0, 4 * reciprocalInputHeight, 0, 0)
    }
}
