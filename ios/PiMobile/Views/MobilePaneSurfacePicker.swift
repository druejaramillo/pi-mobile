import SwiftUI

/// Glass pane choices switch views of the same process, never its input ownership.
struct MobilePaneSurfacePicker: View {
    @Binding var selection: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if #available(iOS 26.0, *) {
            MobileGlassContainer {
                HStack(spacing: 12) {
                    paneSurfaceButton("Agent", symbol: "sparkles")
                    paneSurfaceButton("Terminal", symbol: "terminal")
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: selection)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Pane view")
        } else {
            Picker("Pane view", selection: $selection) {
                Text("Agent").tag("Agent")
                Text("Terminal").tag("Terminal")
            }.pickerStyle(.segmented)
        }
    }

    private func paneSurfaceButton(_ title: String, symbol: String) -> some View {
        Button { selection = title } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity)
        }
        .mobileGlassButtonStyle(prominent: selection == title)
        .buttonBorderShape(.capsule).controlSize(.regular)
        .frame(minHeight: 44)
        .accessibilityAddTraits(selection == title ? .isSelected : [])
    }
}
