import SwiftUI

struct DiagnosticSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.bold().monospaced())
                .foregroundStyle(.white.opacity(0.6))
            content
        }
    }
}
