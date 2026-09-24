import SwiftUI

struct DiagnosticLine: View {
    let text: String
    var tint: Color = .white

    var body: some View {
        Text(text)
            .font(.caption.monospaced())
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
