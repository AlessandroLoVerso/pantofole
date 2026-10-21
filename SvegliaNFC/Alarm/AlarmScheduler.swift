import AlarmKit
import Foundation
import Observation
import SvegliaCore
import SwiftUI

nonisolated struct WakeMetadata: AlarmMetadata {}

/// Keeps the alarms registered with iOS (AlarmKit) in line with the ones the user switched on.
///
/// Each enabled alarm becomes:
/// - a *head*: one repeating system alarm at the chosen time, which keeps ringing every morning
///   even if the app is never opened again;
/// - a *chain*: one-off system alarms every minute after the head, for the running morning and the
///   next ones. Silencing a ring (Stop button, hardware keys) leaves the rest of the chain in place;
///   only a scan of the tag cancels it, and after 30 minutes it ends by itself.
@Observable
final class AlarmScheduler {
    private(set) var authorization: AlarmManager.AuthorizationState
    private(set) var alertingIDs: Set<Alarm.ID> = []
    private(set) var lastError: String?

    var isDenied: Bool { authorization == .denied }
    var isUndetermined: Bool { authorization == .notDetermined }

    private let manager = AlarmManager.shared
    private let chain = AppConfig.chain
    private var ledger: Ledger {
        didSet { ledger.save() }
    }

    init() {
        authorization = AlarmManager.shared.authorizationState
        ledger = Ledger.load()
    }

    func requestAuthorization() async -> Bool {
        do {
            authorization = try await manager.requestAuthorization()
        } catch {
            authorization = manager.authorizationState
        }
        return authorization == .authorized
    }

    func observeAlarms(onChange: @escaping () -> Void) async {
        for await alarms in manager.alarmUpdates {
            alertingIDs = Set(alarms.filter { $0.state == .alerting }.map(\.id))
            onChange()
        }
    }

    func observeAuthorization() async {
        for await state in manager.authorizationUpdates {
            authorization = state
        }
    }

    // MARK: - Sync

    /// Registers what is missing, cancels what is no longer wanted, and returns the starts of chains
    /// that ran out without a scan (mornings ended by the emergency exit).
    func sync(enabled items: [AlarmItem], now: Date) async -> [Date] {
        guard authorization == .authorized else { return [] }
        lastError = nil
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let missed = dropFinishedAndUnwantedChains(items: byID, now: now)
        await syncHeads(items: byID)
        for item in items.sorted(by: { nextStart($0, now) < nextStart($1, now) }) {
            for start in wantedStarts(for: item, now: now)
            where !ledger.chains.contains(where: { $0.itemID == item.id && $0.start == start }) {
                let rings = chain.remainingRings(from: start, after: now).filter { $0 > start }
                await scheduleChain(
                    itemID: item.id, start: start, end: chain.end(of: start), rings: rings, sound: item.soundName
                )
            }
        }
        return missed
    }

    /// A short trial chain, a few seconds from now, so the user walks to the tag once while setting up.
    func scheduleTest(now: Date, sound: String) async {
        let start = now.addingTimeInterval(AppConfig.testDelay)
        let rings = (0..<AppConfig.testRings).map { start.addingTimeInterval(Double($0) * chain.interval) }
        await scheduleChain(
            itemID: nil, start: start, end: rings.last!.addingTimeInterval(chain.interval), rings: rings, sound: sound
        )
    }

    // MARK: - Ringing

    /// Start of the alarm whose chain is running right now, if any.
    func ringingStart(items: [AlarmItem], now: Date) -> Date? {
        if let test = ledger.chains.first(where: { $0.itemID == nil && $0.start <= now && now < $0.end }) {
            return test.start
        }
        let starts = items.filter(\.isEnabled).compactMap { item -> Date? in
            guard let start = Occurrences.active(rule: item.rule, armedAt: item.armedAt, now: now, chain: chain),
                  ledger.stopped[item.id] != start
            else { return nil }
            return start
        }
        if let earliest = starts.min() { return earliest }
        return alertingIDs.isEmpty ? nil : now
    }

    /// The tag was scanned: silence what is ringing and cancel the rest of the chain.
    /// Returns whether it was the trial alarm.
    @discardableResult
    func stopChain(startedAt start: Date, items: [AlarmItem], now: Date) -> Bool {
        let wasTest = ledger.chains.contains { $0.itemID == nil && $0.start == start }
        for item in items where item.isEnabled
        && Occurrences.active(rule: item.rule, armedAt: item.armedAt, now: now, chain: chain) == start {
            ledger.stopped[item.id] = start
        }
        for entry in ledger.chains where entry.start == start || (entry.start <= now && now < entry.end) {
            cancel(entry)
        }
        let alerting = (try? manager.alarms.filter { $0.state == .alerting }.map(\.id)) ?? Array(alertingIDs)
        for id in alerting {
            try? manager.stop(id: id)
        }
        return wasTest
    }

    // MARK: - Private

    private func nextStart(_ item: AlarmItem, _ now: Date) -> Date {
        Occurrences.upcoming(rule: item.rule, armedAt: item.armedAt, now: now, count: 1).first ?? .distantFuture
    }

    private func wantedStarts(for item: AlarmItem, now: Date) -> [Date] {
        var starts = Occurrences.upcoming(
            rule: item.rule, armedAt: item.armedAt, now: now, count: AppConfig.chainsAhead
        )
        if let active = Occurrences.active(rule: item.rule, armedAt: item.armedAt, now: now, chain: chain) {
            starts.insert(active, at: 0)
        }
        return starts.filter { ledger.stopped[item.id] != $0 }
    }

    private func dropFinishedAndUnwantedChains(items: [UUID: AlarmItem], now: Date) -> [Date] {
        var missed: [Date] = []
        for entry in ledger.chains {
            if now >= entry.end {
                if entry.itemID != nil { missed.append(entry.start) }
                cancel(entry)
            } else if let itemID = entry.itemID {
                // A chain registered with another sound is dropped here and registered again by `sync`.
                let stillWanted = items[itemID].map {
                    wantedStarts(for: $0, now: now).contains(entry.start) && entry.soundName == $0.soundName
                } ?? false
                if !stillWanted { cancel(entry) }
            }
        }
        return missed
    }

    private func syncHeads(items: [UUID: AlarmItem]) async {
        let live = Set((try? manager.alarms.map(\.id)) ?? [])
        for (itemID, head) in ledger.heads {
            // A one-off head disappears once it has rung: that is expected, not a reason to schedule it again.
            let lost = head.rule.repeats && !live.contains(head.alarmID)
            if items[itemID]?.rule != head.rule || items[itemID]?.soundName != head.soundName || lost {
                try? manager.cancel(id: head.alarmID)
                ledger.heads[itemID] = nil
            }
        }
        for item in items.values where ledger.heads[item.id] == nil {
            let alarmID = UUID()
            do {
                _ = try await manager.schedule(
                    id: alarmID, configuration: configuration(relativeSchedule(item.rule), sound: item.soundName)
                )
                ledger.heads[item.id] = Ledger.Head(alarmID: alarmID, rule: item.rule, sound: item.soundName)
            } catch {
                lastError = message(for: error)
            }
        }
    }

    private func scheduleChain(itemID: UUID?, start: Date, end: Date, rings: [Date], sound: String) async {
        var alarmIDs: [Alarm.ID] = []
        for ring in rings {
            let alarmID = UUID()
            do {
                _ = try await manager.schedule(id: alarmID, configuration: configuration(.fixed(ring), sound: sound))
                alarmIDs.append(alarmID)
            } catch {
                lastError = message(for: error)
                break
            }
        }
        ledger.chains.append(Ledger.Chain(itemID: itemID, start: start, end: end, alarmIDs: alarmIDs, sound: sound))
    }

    private func cancel(_ entry: Ledger.Chain) {
        for alarmID in entry.alarmIDs {
            try? manager.cancel(id: alarmID)
        }
        ledger.chains.removeAll { $0 == entry }
    }

    private func configuration(_ schedule: Alarm.Schedule, sound: String) -> AlarmManager.AlarmConfiguration<WakeMetadata> {
        // Same wording for tag and mission alarms: the button opens the app on whichever one applies.
        let alert = AlarmPresentation.Alert(
            title: "Alzati per spegnerla",
            secondaryButton: AlarmButton(text: "Spegnila", textColor: .white, systemImageName: "sunrise.fill"),
            secondaryButtonBehavior: .custom
        )
        let attributes = AlarmAttributes<WakeMetadata>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: Theme.sunrise
        )
        return .alarm(
            schedule: schedule,
            attributes: attributes,
            secondaryIntent: OpenScannerIntent(),
            sound: RingtoneCatalog.alertSound(for: sound)
        )
    }

    private func relativeSchedule(_ rule: AlarmRule) -> Alarm.Schedule {
        let time = Alarm.Schedule.Relative.Time(hour: rule.hour, minute: rule.minute)
        let recurrence: Alarm.Schedule.Relative.Recurrence = rule.repeats
            ? .weekly(rule.weekdays.sorted().compactMap { Self.weekdays[$0] })
            : .never
        return .relative(Alarm.Schedule.Relative(time: time, repeats: recurrence))
    }

    private static let weekdays: [Int: Locale.Weekday] = [
        1: .sunday, 2: .monday, 3: .tuesday, 4: .wednesday, 5: .thursday, 6: .friday, 7: .saturday,
    ]

    private func message(for error: Error) -> String {
        if let error = error as? AlarmManager.AlarmError, error == .maximumLimitReached {
            return String(localized: "iOS non accetta altre sveglie: disattivane qualcuna.")
        }
        return error.localizedDescription
    }
}

/// What this app registered with AlarmKit, so it can be cancelled later. Stored in UserDefaults.
nonisolated private struct Ledger: Codable {
    struct Head: Codable, Equatable {
        var alarmID: UUID
        var rule: AlarmRule
        /// `AlarmItem.soundName` it was registered with. Optional so ledgers saved before sounds
        /// existed still decode (nil = the iOS sound they were registered with).
        var sound: String?

        var soundName: String { sound ?? "" }
    }

    struct Chain: Codable, Equatable {
        /// Nil for the trial alarm.
        var itemID: UUID?
        var start: Date
        var end: Date
        var alarmIDs: [UUID]
        /// Same as `Head.sound`.
        var sound: String?

        var soundName: String { sound ?? "" }
    }

    var heads: [UUID: Head] = [:]
    var chains: [Chain] = []
    /// The last start stopped with the tag, per alarm, so its chain is not registered again.
    var stopped: [UUID: Date] = [:]

    private static let key = "alarmLedger"

    static func load() -> Ledger {
        guard let data = UserDefaults.standard.data(forKey: key),
              let ledger = try? JSONDecoder().decode(Ledger.self, from: data)
        else { return Ledger() }
        return ledger
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
