import SwiftData
import SwiftUI

@main
struct SvegliaNFCApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.sunrise)
        }
        .modelContainer(model.container)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false

    var body: some View {
        @Bindable var model = model
        ZStack {
            Theme.night.ignoresSafeArea()
            if onboardingCompleted {
                HomeView()
            } else {
                OnboardingView { onboardingCompleted = true }
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: onboardingCompleted)
        .fullScreenCover(isPresented: $model.isRingingScreenPresented) {
            RingingView()
        }
        .task {
            await model.refresh()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ringTest") { await model.scheduleTestAlarm() }
            #endif
        }
        .task { await model.watchAlarms() }
        .task { await model.scheduler.observeAuthorization() }
        .task { await model.tick() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
        .onOpenURL { url in
            Task { await model.handle(url: url) }
        }
    }
}
