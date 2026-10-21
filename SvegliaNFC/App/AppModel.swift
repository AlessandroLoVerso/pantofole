import Foundation
import Observation
import SvegliaCore
import SwiftData

/// What a scan of the tag led to.
enum ScanOutcome: Equatable {
    /// The ringing alarm is stopped.
    case stoppedAlarm(secondsToScan: TimeInterval, streak: Int)
    /// Nothing was ringing: edits are unlocked for a few minutes.
    case unlocked
    case wrongTag
    case noPairedTag
    case cancelled
    case failed(String)
}

enum PairOutcome: Equatable {
    case paired(PairedTag)
    case alreadyPaired
    case failed(String)
    case cancelled
}

/// The morning just won, shown on the "Buongiorno" screen.
struct WakeSummary: Equatable {
    let secondsToScan: TimeInterval
    let streak: Int
}

@Observable
final class AppModel {
    let container: ModelContainer
    let scheduler = AlarmScheduler()
    private let scanner = TagScanner()

    /// Start of the alarm that is ringing right now (its chain is running), if any.
    private(set) var ringingStart: Date?
    /// The full-screen ringing view stays up after the scan to show the result, until the user closes it.
    var isRingingScreenPresented = false
    private(set) var lastWake: WakeSummary?
    private(set) var unlockedUntil: Date?

    private var context: ModelContext { container.mainContext }

    init() {
        do {
            container = try ModelContainer(for: AlarmItem.self, PairedTag.self, WakeRecord.self)
        } catch {
            fatalError("Impossibile aprire il database: \(error)")
        }
    }

    // MARK: - Reading state

    var alarms: [AlarmItem] { (try? context.fetch(FetchDescriptor<AlarmItem>())) ?? [] }
    var tags: [PairedTag] { (try? context.fetch(FetchDescriptor<PairedTag>())) ?? [] }
    var wakeResults: [WakeResult] { ((try? context.fetch(FetchDescriptor<WakeRecord>())) ?? []).map(\.result) }

    func nextStart(of item: AlarmItem, now: Date = .now) -> Date? {
        Occurrences.upcoming(rule: item.rule, armedAt: item.armedAt, now: now, count: 1).first
    }

    /// The enabled alarm that rings first.
    func nextAlarm(now: Date = .now) -> (item: AlarmItem, start: Date)? {
        alarms
            .filter(\.isEnabled)
            .compactMap { item in nextStart(of: item, now: now).map { (item: item, start: $0) } }
            .min { $0.start < $1.start }
    }

    func isEditLocked(now: Date = .now) -> Bool {
        let starts = alarms.filter(\.isEnabled).compactMap { nextStart(of: $0, now: now) }
        return AppConfig.editLock.isLocked(
            now: now, nextStarts: starts, chainRunning: ringingStart != nil, unlockedUntil: unlockedUntil
        )
    }

    /// Changing a switched-off alarm never makes waking up easier, so only enabled ones are locked.
    func needsUnlock(toChange item: AlarmItem) -> Bool {
        item.isEnabled && isEditLocked()
    }

    // MARK: - Lifecycle

    func refresh(now: Date = .now) async {
        for item in alarms where item.isEnabled
        && Occurrences.isFinished(rule: item.rule, armedAt: item.armedAt, now: now, chain: AppConfig.chain) {
            item.isEnabled = false
        }
        let missed = await scheduler.sync(enabled: alarms.filter(\.isEnabled), now: now)
        for start in missed {
            context.insert(WakeRecord(alarmStart: start, stoppedAt: nil))
        }
        save()
        updateRinging(now: now)
    }

    func updateRinging(now: Date = .now) {
        ringingStart = scheduler.ringingStart(items: alarms, now: now)
        if ringingStart != nil {
            isRingingScreenPresented = true
        }
    }

    /// Re-checks every few seconds whether a chain started or ended while the app is open.
    func tick() async {
        while !Task.isCancelled {
            updateRinging()
            try? await Task.sleep(for: .seconds(5))
        }
    }

    func watchAlarms() async {
        await scheduler.observeAlarms { [weak self] in self?.updateRinging() }
    }

    func dismissRingingScreen() {
        isRingingScreenPresented = false
        lastWake = nil
    }

    // MARK: - Scanning

    /// Scan to stop the alarm, or (when nothing rings) to unlock edits.
    func scanTag() async -> ScanOutcome {
        let paired = tags
        guard !paired.isEmpty else { return .noPairedTag }
        let reading: TagScanner.Reading
        do {
            reading = try await scanner.scan(.verify, message: String(localized: "Avvicina la parte alta dell'iPhone al tuo tag."))
        } catch {
            return Self.outcome(for: error)
        }
        guard paired.contains(where: { $0.serial == reading.serial }) else { return .wrongTag }
        return await acceptScan(at: .now)
    }

    /// The app was opened by touching one of our tags (the link written on it).
    func handle(url: URL) async {
        guard let token = AppConfig.tagLink?.token(from: url),
              tags.contains(where: { $0.linkToken == token })
        else { return }
        _ = await acceptScan(at: .now)
    }

    func pairNewTag() async -> PairOutcome {
        let token = AppConfig.tagLink.map { _ in TagLink.makeToken() }
        let link = token.flatMap { AppConfig.tagLink?.url(token: $0) }
        let reading: TagScanner.Reading
        do {
            reading = try await scanner.scan(.pair(link: link), message: String(localized: "Avvicina la parte alta dell'iPhone al tag da abbinare."))
        } catch {
            switch Self.outcome(for: error) {
            case .cancelled: return .cancelled
            case .failed(let message): return .failed(message)
            default: return .failed(String(localized: "Lettura non riuscita."))
            }
        }
        guard !tags.contains(where: { $0.serial == reading.serial }) else { return .alreadyPaired }
        let tag = PairedTag(
            name: String(localized: "Il mio tag"),
            serial: reading.serial,
            linkToken: reading.wroteLink ? token : nil
        )
        context.insert(tag)
        save()
        return .paired(tag)
    }

    private func acceptScan(at now: Date) async -> ScanOutcome {
        unlockedUntil = AppConfig.editLock.unlockedUntil(scanAt: now)
        guard let start = ringingStart else { return .unlocked }
        let wasTest = scheduler.stopChain(startedAt: start, items: alarms, now: now)
        if !wasTest {
            context.insert(WakeRecord(alarmStart: start, stoppedAt: now))
        }
        let summary = WakeSummary(secondsToScan: now.timeIntervalSince(start), streak: WakeInsights.streak(wakeResults))
        lastWake = summary
        await refresh(now: now)
        return .stoppedAlarm(secondsToScan: summary.secondsToScan, streak: summary.streak)
    }

    private static func outcome(for error: Error) -> ScanOutcome {
        switch error as? TagScanner.ScanError {
        case .cancelled: .cancelled
        case .unavailable: .failed(String(localized: "Questo iPhone non può leggere tag NFC."))
        case .busy: .failed(String(localized: "Una scansione è già in corso."))
        case .failed(let message): .failed(message)
        case nil: .failed(error.localizedDescription)
        }
    }

    // MARK: - Editing

    func add(_ item: AlarmItem) async {
        context.insert(item)
        await refresh()
    }

    /// Call after changing an alarm's time, days or label.
    func commitChanges(to item: AlarmItem) async {
        item.armedAt = .now
        await refresh()
    }

    func setEnabled(_ enabled: Bool, for item: AlarmItem) async {
        item.isEnabled = enabled
        item.armedAt = .now
        await refresh()
    }

    func delete(_ item: AlarmItem) async {
        context.delete(item)
        await refresh()
    }

    func remove(_ tag: PairedTag) {
        context.delete(tag)
        save()
    }

    func scheduleTestAlarm() async {
        await scheduler.scheduleTest(now: .now, sound: testAlarmSound)
        updateRinging()
    }

    func save() {
        try? context.save()
    }
}
