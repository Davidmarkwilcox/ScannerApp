// Theme.swift
// File: Theme.swift
// Description: Centralized UI theme (design tokens) for ScannerApp. Defines semantic colors, typography,
// spacing, radii, materials, and reusable view modifiers for consistent styling across all screens.
//
// Section 1. Imports
import SwiftUI

// Section 2. Theme tokens
enum Theme {

    // Section 2.1 Debug (default Off)
    // Note: This is UI-theme specific debugging. App-wide debug logging helper currently lives in ContentView.
    static let debugUI: Bool = false

    // Section 2.2 Spacing
    enum Spacing {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
    }

    // Section 2.3 Corners
    enum Corners {
        /// Tight/utilitarian default (survey: 6–8pt)
        static let card: CGFloat = 8
        static let button: CGFloat = 8
        static let chip: CGFloat = 8
    }

    // Section 2.4 Typography
    enum Typography {
        static let title: Font = .system(.title2, design: .default).weight(.semibold)
        static let headline: Font = .system(.headline, design: .default).weight(.semibold)
        static let body: Font = .system(.body, design: .default)
        static let subheadline: Font = .system(.subheadline, design: .default)
        static let caption: Font = .system(.caption, design: .default)
    }

    // Section 2.5 Colors (semantic)
    enum Colors {
        /// Near-black base
        static let baseBlack: Color = Color(red: 0.03, green: 0.03, blue: 0.035)
        /// Metallic grey (dark, cool)
        static let metallicGrey: Color = Color(red: 0.12, green: 0.13, blue: 0.15)
        /// Metallic highlight (slightly lighter)
        static let metallicGrey2: Color = Color(red: 0.18, green: 0.19, blue: 0.22)

        /// Primary text on dark
        static let textPrimary: Color = .white
        /// Secondary text on dark
        static let textSecondary: Color = .white.opacity(0.72)

        /// Accent: system tint (survey: system default accent)
        static let accent: Color = .accentColor

        /// A subtle border stroke for glass surfaces
        static let glassStroke: Color = .white.opacity(0.18)
    }

    // Section 2.6 Backgrounds
    enum Backgrounds {
        /// Dark gradient (survey: black → dark metallic grey)
        static var appGradient: LinearGradient {
            LinearGradient(
                colors: [Colors.baseBlack, Colors.metallicGrey, Colors.baseBlack],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // Section 2.7 Motion
    enum Motion {
        /// Polished but noticeable (survey: noticeable)
        static let standard: Animation = .easeInOut(duration: 0.22)
        static let emphasis: Animation = .spring(response: 0.32, dampingFraction: 0.85)
    }
}

// Section 3. Reusable Modifiers

// Section 3.1 Screen modifier
private struct ScannerScreenModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .tint(Theme.Colors.accent)
            .preferredColorScheme(.dark) // Dark-only (survey)
            .background(Theme.Backgrounds.appGradient.ignoresSafeArea())
            .onAppear {
                if Theme.debugUI {
                    print("[Theme] Screen appeared")
                }
            }
    }
}

// Section 3.2 Glass card modifier
private struct GlassCardModifier: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Corners.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Corners.card, style: .continuous)
                    .stroke(Theme.Colors.glassStroke, lineWidth: 1)
            )
            .shadow(radius: 10, y: 4)
            .animation(Theme.Motion.standard, value: padding)
    }
}

// Section 3.3 Primary button style (filled accent)
struct ScannerPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(Theme.Colors.accent)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Corners.button, style: .continuous))
            .opacity(configuration.isPressed ? 0.86 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(Theme.Motion.emphasis, value: configuration.isPressed)
    }
}

// Section 4. Public extensions
extension View {

    /// Applies app-wide screen styling: dark-only, gradient background, and system tint.
    func scannerScreen() -> some View {
        self.modifier(ScannerScreenModifier())
    }

    /// Wraps content in a frosted/glass card (survey: strong frosted).
    func scannerGlassCard(padding: CGFloat = Theme.Spacing.lg) -> some View {
        self.modifier(GlassCardModifier(padding: padding))
    }
}

// End of file: Theme.swift
