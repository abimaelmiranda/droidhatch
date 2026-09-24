import AppKit
import SwiftUI

struct AppRow: View {
    let app: InstalledApp

    var body: some View {
        HStack(spacing: 12) {
            if let iconData = app.iconData, let image = NSImage(data: iconData) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 30))
                    .frame(width: 48, height: 48)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(app.alias).font(.headline)
                Text(app.packageName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 5)
    }
}
