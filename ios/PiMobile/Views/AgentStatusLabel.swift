import SwiftUI

/// Agent status always includes text; unknown and cached agents never appear ready.
struct AgentStatusLabel: View {
    let state: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var title: String {
        switch state {
        case "blocked": return "Needs input"
        case "working": return "Working"
        case "done": return "Finished"
        case "idle": return "Ready"
        case "offline": return "Offline"
        default: return "Unknown"
        }
    }

    private var color: Color {
        switch state {
        case "blocked": return .orange
        case "working": return .blue
        case "done", "idle": return .green
        default: return .secondary
        }
    }

    private var symbol: String {
        switch state {
        case "blocked": return "hand.raised.fill"
        case "working": return "circle.dotted"
        case "done": return "checkmark.circle.fill"
        case "idle": return "circle.fill"
        case "offline": return "network.slash"
        default: return "questionmark.circle"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .symbolEffect(.bounce, value: reduceMotion ? "" : state)
            Text(title).foregroundStyle(.primary)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(color.opacity(contrast == .increased ? 0.2 : 0.1), in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}
