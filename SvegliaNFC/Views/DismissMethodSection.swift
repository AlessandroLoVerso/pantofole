import SvegliaCore
import SwiftUI

/// "Come spegnerla": the tag or the math mission, plus the mission's difficulty.
struct DismissMethodSection: View {
    @Binding var method: DismissMethod
    @Binding var difficulty: MissionDifficulty
    let hasTag: Bool

    @State private var pairsTag = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Come spegnerla").font(.headline)

            HStack(spacing: 10) {
                option(.tag, title: "Tag NFC", symbol: "wave.3.right")
                option(.math, title: "Matematica", symbol: "function")
            }

            Text(explanation)
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if method == .tag, !hasTag {
                Button { pairsTag = true } label: {
                    Label("Non hai ancora un tag: abbinalo ora. Finché manca, servirà la missione.", systemImage: "exclamationmark.circle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.dawn)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }

            if method == .math {
                HStack(spacing: 8) {
                    ForEach(MissionDifficulty.allCases, id: \.self) { level in
                        chip(level)
                    }
                }
                Text(example)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.snappy, value: method)
        .sensoryFeedback(.selection, trigger: method)
        .sensoryFeedback(.selection, trigger: difficulty)
        .sheet(isPresented: $pairsTag) { PairTagSheet() }
    }

    private var explanation: LocalizedStringKey {
        switch method {
        case .tag: "Per spegnerla devi alzarti e appoggiare l'iPhone sul tag."
        case .math: "Per spegnerla risolvi 3 calcoli, uno più difficile dell'altro."
        }
    }

    private var example: LocalizedStringKey {
        switch difficulty {
        case .easy: "Somme e sottrazioni, come 34 + 8."
        case .medium: "Arrivano le tabelline, come 14 × 6."
        case .hard: "Con le precedenze, come 45 + 6 × 7."
        }
    }

    private func option(_ value: DismissMethod, title: LocalizedStringKey, symbol: String) -> some View {
        let isOn = method == value
        return Button { method = value } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .foregroundStyle(isOn ? .black.opacity(0.85) : .white)
            .background(isOn ? AnyShapeStyle(Theme.sunriseGradient) : AnyShapeStyle(Theme.surface), in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(isOn ? .clear : Theme.stroke))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func chip(_ level: MissionDifficulty) -> some View {
        let isOn = difficulty == level
        return Button { difficulty = level } label: {
            Text(level.title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 40)
                .foregroundStyle(isOn ? .black.opacity(0.85) : .white)
                .background(isOn ? AnyShapeStyle(Theme.sunriseGradient) : AnyShapeStyle(Theme.surface), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Difficoltà \(level.title)"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

extension MissionDifficulty {
    var title: String {
        switch self {
        case .easy: String(localized: "Facile")
        case .medium: String(localized: "Media")
        case .hard: String(localized: "Difficile")
        }
    }
}
