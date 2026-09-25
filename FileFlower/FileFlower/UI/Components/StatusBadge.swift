import SwiftUI

struct StatusBadge: View {
    let status: ItemStatus
    var failureReason: String? = nil

    var body: some View {
        Text(status.displayName)
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(status.color.opacity(0.15))
            .foregroundColor(status.color)
            .clipShape(Capsule())
            // Ook bij .completed kan er een reden zijn (verplaatst, maar niet geïmporteerd
            // in de NLE). Die alleen bij .failed tonen maakte zo'n item stil.
            .help(failureReason ?? "")
            .accessibilityLabel("Status: \(status.displayName)")
    }
}

extension ItemStatus {
    var displayName: String {
        switch self {
        case .queued: return String(localized: "status.queued")
        case .classifying: return String(localized: "status.classifying")
        case .processing: return String(localized: "status.processing")
        case .completed: return String(localized: "status.completed")
        case .failed: return String(localized: "status.failed")
        case .skipped: return String(localized: "status.skipped")
        }
    }

    var color: Color {
        switch self {
        case .queued: return .blue
        case .classifying: return .purple
        case .processing: return .orange
        case .completed: return .green
        case .failed: return .red
        case .skipped: return .gray
        }
    }
}
