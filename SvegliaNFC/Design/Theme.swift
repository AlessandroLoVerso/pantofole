import SwiftUI

/// Night-first palette: deep blue background, one warm "sunrise" accent.
enum Theme {
    static let night = Color(red: 0.035, green: 0.043, blue: 0.086)
    static let surface = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.08)
    static let muted = Color.white.opacity(0.58)
    static let sunrise = Color(red: 1.0, green: 0.56, blue: 0.24)
    static let dawn = Color(red: 1.0, green: 0.38, blue: 0.33)
    static let sunriseGradient = LinearGradient(
        colors: [dawn, sunrise, Color(red: 1.0, green: 0.78, blue: 0.38)],
        startPoint: .bottomLeading,
        endPoint: .topTrailing
    )
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Theme.stroke))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black.opacity(0.85))
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.sunriseGradient, in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.9 : 1) : 0.4)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.surface, in: .capsule)
            .overlay(Capsule().strokeBorder(Theme.stroke))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// The puck with NFC waves, pulsing gently: the app's recurring illustration.
struct PuckIllustration: View {
    var size: CGFloat = 160
    var pulsing = true
    @State private var expanded = false

    var body: some View {
        ZStack {
            ForEach(0..<3) { ring in
                Circle()
                    .stroke(Theme.sunrise.opacity(0.35 - Double(ring) * 0.1), lineWidth: 1.5)
                    .frame(width: size, height: size)
                    .scaleEffect(expanded ? 1.0 + Double(ring + 1) * 0.22 : 0.9)
                    .opacity(expanded ? 0 : 1)
                    .animation(
                        pulsing
                            ? .easeOut(duration: 2.4).repeatForever(autoreverses: false).delay(Double(ring) * 0.5)
                            : .default,
                        value: expanded
                    )
            }
            Circle()
                .fill(Theme.sunriseGradient)
                .frame(width: size, height: size)
                .shadow(color: Theme.sunrise.opacity(0.45), radius: 30)
            Image(systemName: "wave.3.right")
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(.black.opacity(0.75))
        }
        .frame(width: size * 1.8, height: size * 1.8)
        .onAppear { if pulsing { expanded = true } }
        .accessibilityHidden(true)
    }
}
