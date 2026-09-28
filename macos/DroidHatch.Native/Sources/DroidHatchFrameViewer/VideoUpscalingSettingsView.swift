import SwiftUI

struct VideoUpscalingSettingsView: View {
    @ObservedObject var model: ViewerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Video Upscaling")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Output resolution")
                    Spacer()
                    Text(String(format: "%.2fx", model.upscalingOutputScale))
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { model.upscalingOutputScale },
                        set: model.setUpscalingOutputScale),
                    in: Fsr1RenderDefaults.minimumScale...Fsr1RenderDefaults.maximumScale,
                    step: Fsr1RenderDefaults.scaleStep)
                    .help("Sets the FSR output resolution relative to the Android frame.")
                if let outputDescription = model.upscalingOutputDescription {
                    Text(outputDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("RCAS sharpness")
                    Spacer()
                    Text(String(format: "%.0f%%", model.upscalingSharpness * 100))
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { model.upscalingSharpness },
                        set: model.setUpscalingSharpness),
                    in: Fsr1RenderDefaults.minimumSharpness...Fsr1RenderDefaults.maximumSharpness,
                    step: Fsr1RenderDefaults.sharpnessStep)
                    .help("Higher values apply stronger RCAS sharpening.")
            }

            HStack {
                Spacer()
                Button("Done") {
                    model.isScalingSettingsPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
