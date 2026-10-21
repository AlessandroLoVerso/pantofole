import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PairedTag.pairedAt) private var tags: [PairedTag]

    @State private var showsPairing = false
    @State private var tagToRemove: PairedTag?
    @State private var unlockingRemoval: PairedTag?
    @State private var soundChoice = RingtoneCatalog.preferredSoundName

    /// The sound for every alarm: changing it updates all of them.
    private var preferredSound: Binding<String> {
        Binding(
            get: { soundChoice },
            set: { name in
                soundChoice = name
                Task { await model.setSoundForAllAlarms(name) }
            }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        dismiss()
                        Task { await model.scheduleTestAlarm() }
                    } label: {
                        Label("Fai una sveglia di prova", systemImage: "alarm.waves.left.and.right.fill")
                            .font(.headline)
                    }
                    NavigationLink {
                        RingtonePickerView(selection: preferredSound)
                    } label: {
                        HStack {
                            Label("Suono della sveglia", systemImage: "speaker.wave.3.fill")
                            Spacer()
                            Text(RingtoneCatalog.displayName(for: preferredSound.wrappedValue))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                        }
                    }
                } footer: {
                    Text(tags.isEmpty
                        ? "La prova suona tra 10 secondi, anche col silenzioso: spegnila risolvendo la missione. Il suono scelto vale per tutte le sveglie."
                        : "La prova suona tra 10 secondi, anche col silenzioso: vai al tag e spegnila. Il suono scelto vale per tutte le sveglie.")
                }

                Section {
                    rule("speaker.wave.2.fill", "Volume di \"Suoneria e avvisi\"", "La sveglia di iOS usa questo volume: controllalo in Impostazioni di iOS → Suoni e feedback aptico.")
                    rule("faceid", "Funzioni basate sull'attenzione", "Se guardi l'iPhone mentre suona, iOS abbassa il volume della sveglia. Per una prova fedele, blocca il telefono e appoggialo.")
                } header: {
                    Text("Perché si senta sempre")
                } footer: {
                    Text("Quando la sveglia suona con l'app aperta, Pantofole aggiunge un suono suo al volume dei media.")
                }

                Section {
                    ForEach(tags) { tag in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tag.name)
                                Text("Abbinato il \(tag.pairedAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.muted)
                            }
                        } icon: {
                            Image(systemName: "wave.3.right.circle.fill").foregroundStyle(Theme.sunrise)
                        }
                        .swipeActions {
                            Button("Rimuovi", role: .destructive) { requestRemoval(of: tag) }
                        }
                    }
                    Button {
                        showsPairing = true
                    } label: {
                        Label(tags.isEmpty ? "Abbina un tag" : "Abbina un altro tag", systemImage: "plus.circle")
                    }
                } header: {
                    Text("I tuoi tag")
                } footer: {
                    Text("Con più tag puoi spegnere la sveglia da uno qualsiasi, per esempio uno in bagno e uno in cucina.")
                }

                BlocksSection()

                Section("Come funziona") {
                    rule("nosign", "Niente posticipo", "Non c'è un tasto per rimandarla.")
                    rule("arrow.clockwise", "Se la zittisci, ricomincia", "Il tasto Ferma o i tasti del volume la fermano per un minuto, poi suona di nuovo.")
                    rule("lock.fill", "Bloccata nelle 8 ore prima", "Per modificarla o spegnerla la sera prima serve il tag.")
                    rule("timer", "Uscita di emergenza", "Se nessuno scansiona il tag, dopo 30 minuti si ferma da sola.")
                }

                Section("Privacy") {
                    rule("hand.raised.fill", "Niente account", "Tutto resta sul tuo iPhone. Nessun dato viene inviato.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.night.ignoresSafeArea())
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
            .sheet(isPresented: $showsPairing) { PairTagSheet() }
            .sheet(item: $unlockingRemoval) { tag in
                UnlockSheet { tagToRemove = tag }
            }
            .confirmationDialog(
                "Rimuovere il tag?",
                isPresented: Binding(get: { tagToRemove != nil }, set: { if !$0 { tagToRemove = nil } }),
                titleVisibility: .visible,
                presenting: tagToRemove
            ) { tag in
                Button("Rimuovi \(tag.name)", role: .destructive) { model.remove(tag) }
            } message: { _ in
                Text("Non potrai più usarlo per spegnere la sveglia.")
            }
        }
    }

    private func requestRemoval(of tag: PairedTag) {
        if model.isEditLocked() {
            unlockingRemoval = tag
        } else {
            tagToRemove = tag
        }
    }

    private func rule(_ icon: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(text).font(.footnote).foregroundStyle(Theme.muted)
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(Theme.sunrise)
        }
    }
}
