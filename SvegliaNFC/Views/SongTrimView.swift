import SwiftUI

/// A song picked by the user, copied to a temporary file and waiting to be trimmed.
struct PendingClip: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let duration: TimeInterval
}

/// Choose which part of the song wakes you up: one slider, one preview button, one "use it".
struct SongTrimView: View {
    let clip: PendingClip
    var onSave: (CustomSong) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var start: TimeInterval = 0
    @State private var previewer = RingtonePreviewer()
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saved = 0

    private let clipLength = RingtoneCatalog.maxClipDuration

    init(clip: PendingClip, onSave: @escaping (CustomSong) -> Void) {
        self.clip = clip
        self.onSave = onSave
        _title = State(initialValue: clip.title)
    }

    private var maxStart: TimeInterval { max(0, clip.duration - clipLength) }
    private var end: TimeInterval { min(clip.duration, start + clipLength) }
    private var isPlaying: Bool { previewer.playingID != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "music.note")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.75))
                        .frame(width: 104, height: 104)
                        .background(Theme.sunriseGradient, in: .circle)
                        .shadow(color: Theme.sunrise.opacity(0.4), radius: 24)
                        .symbolEffect(.bounce, value: isPlaying)
                        .padding(.top, 12)
                        .accessibilityHidden(true)

                    TextField("Nome della canzone", text: $title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .card()

                    VStack(alignment: .leading, spacing: 14) {
                        if maxStart > 0 {
                            Text("Da dove parte?").font(.headline)
                            Slider(value: $start, in: 0...maxStart, step: 1) {
                                Text("Inizio")
                            } onEditingChanged: { editing in
                                if !editing, isPlaying { playPreview() }
                            }
                            .accessibilityValue(Text("Da \(clock(start)) a \(clock(end))"))
                            HStack {
                                Text(clock(start))
                                Spacer()
                                Text("fino a \(clock(end))")
                            }
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(Theme.muted)
                        } else {
                            Text("La canzone dura \(clock(clip.duration)): la sveglia la suonerà tutta.")
                                .font(.subheadline)
                        }
                        Button {
                            if isPlaying { previewer.stop() } else { playPreview() }
                        } label: {
                            Label(isPlaying ? "Ferma l'anteprima" : "Ascolta", systemImage: isPlaying ? "stop.fill" : "play.fill")
                        }
                        .buttonStyle(.secondary)
                    }
                    .card()

                    Text("La sveglia suona questo pezzo e, se non la spegni con il tag, ricomincia ogni minuto.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Theme.dawn)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    save()
                } label: {
                    if isSaving { ProgressView().tint(.black) } else { Text("Usa questa canzone") }
                }
                .buttonStyle(.primary)
                .disabled(isSaving)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .background(Theme.night.ignoresSafeArea())
            .navigationTitle("La tua canzone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
        }
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.selection, trigger: start)
        .interactiveDismissDisabled(isSaving)
        .onDisappear {
            previewer.stop()
            try? FileManager.default.removeItem(at: clip.url)
        }
    }

    private func playPreview() {
        previewer.play(id: "trim", url: clip.url, from: start, duration: clipLength)
    }

    private func save() {
        previewer.stop()
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let song = try await CustomSongLibrary.shared.add(from: clip.url, start: start, title: title)
                saved += 1
                onSave(song)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    /// "1:05".
    private func clock(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.rounded()).formatted(.time(pattern: .minuteSecond))
    }
}
