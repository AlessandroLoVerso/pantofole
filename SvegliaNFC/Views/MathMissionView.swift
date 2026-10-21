import SvegliaCore
import SwiftUI

/// The wake-up mission: a few math problems, each a bit harder, typed on a big keypad.
/// Used while an alarm rings and to unlock edits when no tag is paired.
struct MathMissionView: View {
    var onComplete: () -> Void

    @State private var mission: MathMission<SystemRandomNumberGenerator>
    @State private var entry = ""
    @State private var shakes: CGFloat = 0
    @State private var showsWrong = false

    init(difficulty: MissionDifficulty, onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        _mission = State(initialValue: MathMission(difficulty: difficulty))
    }

    var body: some View {
        VStack(spacing: 18) {
            ProgressDots(total: mission.length, solved: mission.solved)

            if let problem = mission.current {
                VStack(spacing: 10) {
                    Text(problem.text)
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                        .accessibilityLabel(Self.spoken(problem.text))
                        .id(problem.text)
                        .transition(.push(from: .trailing).combined(with: .opacity))

                    Text(entry.isEmpty ? "?" : entry)
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(showsWrong ? Theme.dawn : (entry.isEmpty ? Theme.muted : Theme.sunrise))
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(Theme.surface, in: .rect(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(showsWrong ? Theme.dawn : Theme.stroke, lineWidth: showsWrong ? 2 : 1)
                        )
                        .modifier(ShakeEffect(animatableData: shakes))
                        .accessibilityLabel(entry.isEmpty ? Text("Risposta vuota") : Text("Risposta \(entry)"))
                }

                Text(showsWrong ? "Non è giusto: eccone un altro." : "Risolvi \(mission.length) calcoli per spegnerla.")
                    .font(.callout.weight(showsWrong ? .semibold : .regular))
                    .foregroundStyle(showsWrong ? Theme.dawn : Theme.muted)
                    .multilineTextAlignment(.center)
            }

            NumericKeypad(entry: $entry, canSubmit: !entry.isEmpty && !mission.isComplete, onSubmit: submit)
        }
        .animation(.spring(duration: 0.4), value: mission.current)
        .animation(.easeInOut(duration: 0.2), value: showsWrong)
        .sensoryFeedback(.error, trigger: mission.mistakes)
        .sensoryFeedback(.success, trigger: mission.solved)
    }

    private func submit() {
        guard let answer = Int(entry) else { return }
        if mission.submit(answer) {
            entry = ""
            showsWrong = false
            if mission.isComplete { onComplete() }
        } else {
            showsWrong = true
            withAnimation(.linear(duration: 0.4)) { shakes += 1 }
            Task {
                try? await Task.sleep(for: .seconds(0.6))
                entry = ""
            }
        }
    }

    /// "12 × 7 − 4" read aloud as "12 per 7 meno 4".
    private static func spoken(_ text: String) -> String {
        text
            .replacingOccurrences(of: "×", with: String(localized: "per"))
            .replacingOccurrences(of: "−", with: String(localized: "meno"))
            .replacingOccurrences(of: "+", with: String(localized: "più"))
    }
}

/// One dot per problem: filled when solved, wider for the one in progress.
private struct ProgressDots: View {
    let total: Int
    let solved: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < solved ? AnyShapeStyle(Theme.sunriseGradient) : AnyShapeStyle(Theme.surface))
                    .overlay(Capsule().strokeBorder(index == solved ? Theme.sunrise : Theme.stroke))
                    .frame(width: index == solved ? 28 : 12, height: 12)
            }
        }
        .animation(.spring(duration: 0.4), value: solved)
        .accessibilityElement()
        .accessibilityLabel("Risolti \(solved) su \(total)")
    }
}

/// A big phone-style keypad: digits, delete, confirm. No system keyboard.
private struct NumericKeypad: View {
    @Binding var entry: String
    var canSubmit: Bool
    var onSubmit: () -> Void

    private let maxDigits = String(MathProblem.maxAnswer).count
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(1...9, id: \.self) { digit in
                key(Text("\(digit)"), label: Text("\(digit)")) { type(digit) }
            }
            key(Image(systemName: "delete.left"), label: Text("Cancella")) {
                if !entry.isEmpty { entry.removeLast() }
            }
            .disabled(entry.isEmpty)
            key(Text(verbatim: "0"), label: Text(verbatim: "0")) { type(0) }
            key(Image(systemName: "checkmark"), label: Text("Conferma"), prominent: true, action: onSubmit)
                .disabled(!canSubmit)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: entry)
    }

    private func type(_ digit: Int) {
        guard entry.count < maxDigits else { return }
        if entry == "0" { entry = "" }
        entry.append(String(digit))
    }

    private func key(
        _ content: some View,
        label: Text,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            content
                .font(.system(.title, design: .rounded).weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 60)
                .foregroundStyle(prominent ? .black.opacity(0.85) : .white)
                .background(prominent ? AnyShapeStyle(Theme.sunriseGradient) : AnyShapeStyle(Theme.surface), in: .rect(cornerRadius: 20))
                .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(KeyStyle())
        .accessibilityLabel(label)
    }
}

private struct KeyStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.35)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Horizontal wobble for a wrong answer.
private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(animatableData * .pi * 6), y: 0))
    }
}
