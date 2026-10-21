import MediaPlayer
import SwiftUI
import UniformTypeIdentifiers

/// Pick the alarm's sound: tap to hear it and choose it in one go.
struct RingtonePickerView: View {
    @Binding var selection: String

    @Environment(AppModel.self) private var model
    @State private var previewer = RingtonePreviewer()
    @State private var library = CustomSongLibrary.shared
    @State private var importsFromFiles = false
    @State private var showsMusicPicker = false
    @State private var pendingClip: PendingClip?
    @State private var isPreparing = false
    @State private var notice: Notice?

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if !library.songs.isEmpty { songsSection }
                ForEach(RingtoneFamily.allCases) { family in
                    Section {
                        ForEach(RingtoneCatalog.ringtones(in: family)) { ringtone in
                            row(id: ringtone.fileName, title: ringtone.name)
                        }
                    } header: {
                        Label(family.title, systemImage: family.symbol)
                    } footer: {
                        Text(family.subtitle)
                    }
                }
                if library.songs.isEmpty { songsSection }
                Section {
                    row(id: RingtoneCatalog.systemSoundName, title: String(localized: "Standard di iOS"))
                } footer: {
                    Text("Il suono delle sveglie di sistema. Non si può ascoltare in anteprima.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.night.ignoresSafeArea())
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
        }
        .navigationTitle("Suoneria")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                addMenu {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Aggiungi una tua canzone")
            }
        }
        .fileImporter(isPresented: $importsFromFiles, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url): prepare { try SongSource.copyFromFiles(url) } title: { url.deletingPathExtension().lastPathComponent }
            case .failure(let error): notice = Notice(message: error.localizedDescription)
            }
        }
        .sheet(isPresented: $showsMusicPicker) {
            MusicPicker { item in handle(item) }
                .ignoresSafeArea()
        }
        .sheet(item: $pendingClip) { clip in
            SongTrimView(clip: clip) { song in
                selection = song.fileName
            }
        }
        .alert(item: $notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message))
        }
        .overlay {
            if isPreparing {
                ProgressView("Preparo la canzone…")
                    .padding(24)
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: 20))
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .onDisappear { previewer.stop() }
    }

    // MARK: - Rows

    private func row(id: String, title: String) -> some View {
        let isSelected = selection == id
        let isPlaying = previewer.playingID == id
        return Button {
            choose(id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.sunrise)
                    .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                    .opacity(isPlaying ? 1 : 0)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Theme.sunrise)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Theme.sunrise.opacity(0.14) : Theme.surface)
        .id(id)
        .accessibilityLabel(title)
        .accessibilityValue(isPlaying ? String(localized: "In riproduzione") : "")
        .accessibilityHint(id.isEmpty ? "" : String(localized: "Tocca per sceglierla e ascoltarla"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var songsSection: some View {
        Section {
            ForEach(library.songs) { song in
                row(id: song.fileName, title: song.title)
                    .swipeActions {
                        Button("Elimina", role: .destructive) { delete(song) }
                    }
            }
            addMenu {
                Label("Aggiungi una tua canzone", systemImage: "plus.circle")
                    .foregroundStyle(Theme.sunrise)
            }
            .listRowBackground(Theme.surface)
        } header: {
            Label("Le tue canzoni", systemImage: "music.note")
        } footer: {
            Text("Scegli un brano da File o dalla libreria Musica e il punto da cui partire: la sveglia ne suona \(Int(RingtoneCatalog.maxClipDuration)) secondi.")
        }
    }

    private func addMenu<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        Menu {
            Button("Da File", systemImage: "folder") { importsFromFiles = true }
            Button("Dalla libreria Musica", systemImage: "music.note.list") { openMusicLibrary() }
        } label: {
            label()
        }
    }

    // MARK: - Actions

    private func choose(_ id: String) {
        if selection == id, previewer.playingID == id {
            previewer.stop()
            return
        }
        selection = id
        if let url = RingtoneCatalog.url(for: id) {
            previewer.play(id: id, url: url)
        } else {
            previewer.stop()
        }
    }

    private func delete(_ song: CustomSong) {
        if previewer.playingID == song.fileName { previewer.stop() }
        if selection == song.fileName { selection = RingtoneCatalog.defaultSoundName }
        library.delete(song)
        Task { await model.replaceSound(song.fileName, with: RingtoneCatalog.defaultSoundName) }
    }

    private func openMusicLibrary() {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized:
            showsMusicPicker = true
        case .notDetermined:
            MPMediaLibrary.requestAuthorization { status in
                Task { @MainActor in
                    if status == .authorized { showsMusicPicker = true } else { notice = .musicDenied }
                }
            }
        default:
            notice = .musicDenied
        }
    }

    private func handle(_ item: MPMediaItem) {
        guard let assetURL = item.assetURL, !item.hasProtectedAsset else {
            notice = .protectedSong
            return
        }
        let title = item.title ?? ""
        prepare { try await SongSource.exportFromMusicLibrary(assetURL) } title: { title }
    }

    /// Copies the picked song to a temporary file, then opens the trim screen.
    private func prepare(_ load: @escaping () async throws -> URL, title: @escaping () -> String) {
        previewer.stop()
        isPreparing = true
        Task {
            defer { isPreparing = false }
            do {
                let url = try await load()
                let duration = try SongClipper.duration(of: url)
                pendingClip = PendingClip(url: url, title: title(), duration: duration)
            } catch {
                notice = Notice(message: String(localized: "Non riesco a usare questo brano. Prova con un altro file audio (MP3, M4A, WAV, AIFF)."))
            }
        }
    }
}

private struct Notice: Identifiable {
    let id = UUID()
    var title = String(localized: "Canzone non disponibile")
    let message: String

    static let protectedSong = Notice(message: String(localized: "Questo brano è protetto o arriva in streaming da Apple Music, e iOS non permette di usarlo come suoneria. Scegline uno acquistato o importato nella libreria, oppure un file da File."))

    static let musicDenied = Notice(
        title: String(localized: "Accesso a Musica negato"),
        message: String(localized: "Per scegliere un brano dalla libreria, consenti l'accesso a Musica in Impostazioni > Sveglia NFC. Puoi sempre importare un file da File.")
    )
}

/// Wraps the system Music library picker.
struct MusicPicker: UIViewControllerRepresentable {
    var onPick: (MPMediaItem) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let picker = MPMediaPickerController(mediaTypes: .music)
        picker.allowsPickingMultipleItems = false
        picker.showsCloudItems = false
        picker.prompt = String(localized: "Scegli la canzone per la sveglia")
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: MPMediaPickerController, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, MPMediaPickerControllerDelegate {
        var parent: MusicPicker

        init(parent: MusicPicker) { self.parent = parent }

        func mediaPicker(_ picker: MPMediaPickerController, didPickMediaItems collection: MPMediaItemCollection) {
            parent.dismiss()
            if let item = collection.items.first { parent.onPick(item) }
        }

        func mediaPickerDidCancel(_ picker: MPMediaPickerController) {
            parent.dismiss()
        }
    }
}
