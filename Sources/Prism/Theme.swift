import SwiftUI

/// Central place for the "old-school 3D modeling app" look:
/// beveled metal, glassy gradients, neon wireframe accents, and
/// reusable view modifiers that give every panel real depth.
enum Theme {

    // MARK: - Palette
    static let neon       = Color(red: 0.35, green: 0.95, blue: 1.00)   // cyan wireframe glow
    static let neonPink   = Color(red: 1.00, green: 0.35, blue: 0.85)
    static let amber      = Color(red: 1.00, green: 0.78, blue: 0.30)
    static let deepSpace   = Color(red: 0.04, green: 0.05, blue: 0.09)
    static let panelTop    = Color(red: 0.16, green: 0.18, blue: 0.24)
    static let panelBottom = Color(red: 0.07, green: 0.08, blue: 0.12)
    static let metalLight  = Color(red: 0.46, green: 0.50, blue: 0.58)
    static let metalDark   = Color(red: 0.12, green: 0.13, blue: 0.18)

    // MARK: - Gradients
    /// Brushed-metal bevel used for the toolbar and tab strip.
    static var brushedMetal: LinearGradient {
        LinearGradient(
            colors: [metalLight, panelTop, panelBottom, metalDark],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// Glassy panel fill for the AI sidebar and content frame.
    static var glassPanel: LinearGradient {
        LinearGradient(
            colors: [panelTop.opacity(0.92), panelBottom.opacity(0.96)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    /// Cyan-to-magenta wireframe sheen for active accents.
    static var wireSheen: LinearGradient {
        LinearGradient(colors: [neon, neonPink], startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - Reusable 3D view modifiers

/// Gives a view a raised, beveled, "extruded plastic/metal" appearance:
/// a light top edge, a dark bottom edge, and a drop shadow underneath.
struct BeveledPanel: ViewModifier {
    var corner: CGFloat = 14
    var tilt: Double = 0          // degrees of perspective tilt on the X axis
    var glow: Color = Theme.neon

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Theme.glassPanel)
            )
            .overlay(
                // Top highlight + bottom shade = bevel
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.45), .clear, .black.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1.2
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(glow.opacity(0.18), lineWidth: 0.6)
                    .blur(radius: 1.5)
            )
            .shadow(color: .black.opacity(0.6), radius: 14, x: 0, y: 10)
            .rotation3DEffect(.degrees(tilt), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
    }
}

/// A glossy, clickable 3D button face (chrome bubble) with press feedback.
struct ChromeButtonStyle: ButtonStyle {
    var tint: Color = Theme.neon
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [Theme.metalLight, Theme.metalDark],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.6), .black.opacity(0.6)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            )
            .overlay(
                // top gloss
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.35), .clear],
                                         startPoint: .top, endPoint: .center))
                    .padding(1)
                    .allowsHitTesting(false)
            )
            .foregroundStyle(tint)
            .shadow(color: tint.opacity(configuration.isPressed ? 0.0 : 0.35), radius: 6, y: 2)
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension View {
    func beveledPanel(corner: CGFloat = 14, tilt: Double = 0, glow: Color = Theme.neon) -> some View {
        modifier(BeveledPanel(corner: corner, tilt: tilt, glow: glow))
    }
}
