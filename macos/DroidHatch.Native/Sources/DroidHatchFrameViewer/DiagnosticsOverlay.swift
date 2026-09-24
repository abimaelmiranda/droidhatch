import SwiftUI

struct DiagnosticsOverlay: View {
    let videoDescription: String
    let videoDiagnostics: String
    let inputDescription: String
    let audioDescription: String
    let audioDiagnostics: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DiagnosticSection(title: "VIDEO") {
                DiagnosticLine(text: videoDescription)
                DiagnosticLine(text: videoDiagnostics)
            }
            DiagnosticSection(title: "AUDIO") {
                DiagnosticLine(
                    text: audioDescription,
                    tint: audioDescription == "Audio connected" ? .green : .yellow)
                DiagnosticLine(text: audioDiagnostics, tint: .white.opacity(0.78))
            }
            DiagnosticSection(title: "INPUT") {
                DiagnosticLine(
                    text: inputDescription,
                    tint: inputDescription == "Input connected" ? .green : .yellow)
            }
        }
        .frame(maxWidth: 430, alignment: .leading)
        .padding(9)
        .background(.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .padding(10)
    }
}
