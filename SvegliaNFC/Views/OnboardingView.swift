import SwiftUI

/// Four screens, under two minutes: what it is → permission → pair the tag → place it and try it.
struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(AppModel.self) private var model
    @State private var step = Step.welcome
    @State private var hasTag = false

    private enum Step: Int, CaseIterable {
        case welcome, permission, pair, place
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? Theme.sunrise : Theme.surface)
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .accessibilityHidden(true)

            ScrollView {
                content
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .id(step)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .animation(.smooth(duration: 0.35), value: step)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            page(
                title: "Per spegnerla devi alzarti.",
                text: "Niente posticipo. Per farla smettere appoggi l'iPhone sul tuo tag NFC, lontano dal letto."
            ) {
                PuckIllustration(size: 120)
            } actions: {
                Button("Iniziamo") { step = .permission }.buttonStyle(.primary)
            }

        case .permission:
            page(
                title: "Deve suonare sempre",
                text: "Anche con l'iPhone bloccato, in silenzioso o in Full immersion. iOS ti chiederà il permesso."
            ) {
                Image(systemName: "bell.and.waves.left.and.right.fill")
                    .font(.system(size: 88))
                    .foregroundStyle(Theme.sunriseGradient)
                    .padding(.vertical, 40)
            } actions: {
                Button("Consenti le sveglie") {
                    Task {
                        _ = await model.scheduler.requestAuthorization()
                        step = .pair
                    }
                }
                .buttonStyle(.primary)
            }

        case .pair:
            PairTagFlow(
                onFinished: { _ in
                    hasTag = true
                    step = .place
                },
                onSkip: { step = .place }
            )
            .padding(.top, 20)

        case .place:
            page(
                title: hasTag ? "Ora mettilo lontano dal letto" : "Quando avrai un tag",
                text: hasTag
                    ? "Bagno, cucina o corridoio: un posto che ti costringa ad alzarti. Più è scomodo, meglio funziona."
                    : "Abbinalo dalle impostazioni. Fino ad allora la sveglia si ferma da sola dopo 30 minuti."
            ) {
                Image(systemName: "figure.walk.motion")
                    .font(.system(size: 80))
                    .foregroundStyle(Theme.sunriseGradient)
                    .padding(.vertical, 24)
            } actions: {
                if hasTag {
                    VStack(alignment: .leading, spacing: 14) {
                        tip("door.left.hand.open", "In un'altra stanza, non sul comodino.")
                        tip("refrigerator", "Non su metallo, come il frigo: blocca il segnale.")
                        tip("iphone.gen3", "Avvicina la parte alta dell'iPhone, anche con la cover.")
                    }
                    .card()
                    .padding(.bottom, 10)
                }
                if hasTag {
                    Button("Fai una prova: suona tra 10 secondi") {
                        Task {
                            await model.scheduleTestAlarm()
                            onFinish()
                        }
                    }
                    .buttonStyle(.primary)
                    Button("Salta la prova", action: onFinish)
                        .foregroundStyle(Theme.muted)
                } else {
                    Button("Vai alla sveglia", action: onFinish).buttonStyle(.primary)
                }
            }
        }
    }

    private func page<Art: View, Actions: View>(
        title: LocalizedStringKey,
        text: LocalizedStringKey,
        @ViewBuilder art: () -> Art,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 18) {
            art()
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
            Text(title)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
            Text(text)
                .font(.title3)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Spacer(minLength: 24)
            VStack(spacing: 14, content: actions)
        }
    }

    private func tip(_ icon: String, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text).font(.callout)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(Theme.sunrise)
                .frame(width: 28)
        }
    }
}
