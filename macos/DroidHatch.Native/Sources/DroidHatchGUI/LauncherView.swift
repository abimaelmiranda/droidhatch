import SwiftUI

struct LauncherView: View {
    @StateObject private var model = LauncherModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DroidHatch")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Instalar APK", systemImage: "plus") { model.install() }
                    .disabled(model.isBusy)
            }
            .padding()

            Divider()

            if model.apps.isEmpty {
                ContentUnavailableView(
                    "Nenhum aplicativo instalado",
                    systemImage: "square.stack.3d.up",
                    description: Text("Instale um APK para começar."))
            } else {
                List(model.apps, selection: $model.selectedAlias) { app in
                    AppRow(app: app)
                        .tag(app.alias)
                        .contextMenu {
                            Button("Abrir") { model.selectedAlias = app.alias; model.openSelected() }
                            Button("Remover", role: .destructive) {
                                model.selectedAlias = app.alias
                                model.removeSelected()
                            }
                        }
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Text(model.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Remover", role: .destructive) { model.removeSelected() }
                    .disabled(model.selectedApp == nil || model.isBusy)
                Button("Abrir") { model.openSelected() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.selectedApp == nil || model.isBusy)
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}
