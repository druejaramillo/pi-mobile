import SwiftUI

/// Native Liquid Glass belongs to controls, never to transcript or directory content.
extension View {
    /// Reduced transparency uses an opaque system surface; iOS 17–25 retain native material.
    func mobileGlassSurface(in shape: some Shape) -> some View {
        modifier(MobileGlassSurfaceModifier(shape: shape))
    }

    /// System button styles retain disabled, pressed, accessibility and destructive-role behavior.
    @ViewBuilder
    func mobileGlassButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) }
            else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) }
            else { buttonStyle(.bordered) }
        }
    }

    /// Header actions use their own glass shape; native back navigation stays system-owned.
    @ViewBuilder
    func mobileGlassHeaderControl(prominent: Bool = false, symbolOnly: Bool = false) -> some View {
        if symbolOnly {
            labelStyle(.iconOnly)
                .mobileGlassButtonStyle(prominent: prominent)
                .buttonBorderShape(.circle).controlSize(.regular)
                .frame(minWidth: 44, minHeight: 44)
        } else {
            mobileGlassButtonStyle(prominent: prominent)
                .buttonBorderShape(.capsule).controlSize(.regular)
                .frame(minHeight: 44)
        }
    }

    /// Native floating tabs contract on scroll, rather than becoming a custom navigation dock.
    @ViewBuilder
    func mobileGlassTabBar() -> some View {
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }

    /// Registers floating bottom controls with the iOS 26 scroll edge and keyboard safe area.
    @ViewBuilder
    func mobileBottomBar(@ViewBuilder content: () -> some View) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .bottom, spacing: 0, content: content)
        } else {
            safeAreaInset(edge: .bottom, spacing: 0, content: content)
        }
    }
}

/// Explicit glass header buttons must not acquire a second shared toolbar glass background.
extension ToolbarContent {
    @ToolbarContentBuilder
    func mobileGlassHeaderItem() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

/// Nearby glass controls share one renderer without merging their shapes at rest.
struct MobileGlassContainer<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) { content }
        } else {
            content
        }
    }
}

private struct MobileGlassSurfaceModifier<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.background(Color(uiColor: .secondarySystemGroupedBackground), in: shape)
                .overlay { shape.stroke(.primary.opacity(0.2), lineWidth: 0.5).allowsHitTesting(false) }
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}
