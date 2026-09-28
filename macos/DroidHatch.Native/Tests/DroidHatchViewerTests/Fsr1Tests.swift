import Metal
import Testing
@testable import DroidHatchViewer

struct Fsr1Tests {
    @Test
    func easuConstantsFor720pTo1080p() {
        let constants = Fsr1EasuConstants(
            inputWidth: 1280,
            inputHeight: 720,
            outputWidth: 1920,
            outputHeight: 1080)

        #expect(constants.con0 == SIMD4(2.0 / 3.0, 2.0 / 3.0, -1.0 / 6.0, -1.0 / 6.0))
        #expect(constants.con1 == SIMD4(1.0 / 1280.0, 1.0 / 720.0, 1.0 / 1280.0, -1.0 / 720.0))
        #expect(constants.con2 == SIMD4(-1.0 / 1280.0, 2.0 / 720.0, 1.0 / 1280.0, 2.0 / 720.0))
        #expect(constants.con3 == SIMD4(0, 4.0 / 720.0, 0, 0))
    }

    @Test
    func upscalingModesAndDefault() {
        #expect(UpscalingMode.allCases == [.nearest, .linear, .fsr1])
        #expect(UpscalingMode.defaultMode == .fsr1)
        #expect(UpscalingMode.fsr1.title == "FSR 1")
    }

    @Test
    func metalPipelinesCompileWhenMetalIsAvailable() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Issue.record("Metal is unavailable on this machine")
            return
        }

        #expect(MetalRenderSupport.makePipelines(device: device).pipelines != nil)
        #expect(Fsr1MetalSupport.makePipelines(device: device) != nil)
    }
}
