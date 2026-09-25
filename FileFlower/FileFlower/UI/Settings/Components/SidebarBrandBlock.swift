import SwiftUI

/// Top of sidebar: 36×36 icon tile + "FileFlower" + version sub.
struct SidebarBrandBlock: View {
    let appVersion: String
    let licenseTier: String   // "pro" | "trial" | etc.

    var body: some View {
        HStack(spacing: 12) {
            // 36×36 rounded icon tile
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 1) {
                Text("FileFlower")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.ink)
                Text("v\(appVersion) · \(licenseTier)")
                    .font(.brandMono(size: 10.5))
                    .foregroundColor(.ink3)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(
            Rectangle()
                .fill(Color.line)
                .frame(height: 1),
            alignment: .bottom
        )
    }
}
