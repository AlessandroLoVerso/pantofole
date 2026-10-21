import AVFoundation
import Observation
import SvegliaCore
import SwiftData
import UIKit

/// Runs the night: starts listening on "Buonanotte", stores one minute of numbers at a time,
/// and closes the night when the user stops the alarm or taps "Sono sveglio".
@Observable
final class SleepTracker {
    enum StartResult {
        case started
        case microphoneDenied
    }

    /// The night being tracked right now.
    private(set) var activeSession: SleepSession?
    /// Live loudness during the placement test, in dB above the room's floor.
    private(set) var testLevel = 0.0
    private(set) var lastError: String?

    var isListening: Bool { activeSession != nil }

    /// Shorter sessions (a tap by mistake) are thrown away.
    static let minimumMinutes = 10
    /// A night that was never closed ends by itself after this long.
    static let maximumDuration: TimeInterval = 14 * 3600
    static let placementTestDuration: Duration = .seconds(10)

    private let container: ModelContainer
    private let listener = NightListener()
    private var minutes: [SleepMinute] = []
    private var events: [SleepEvent] = []
    private var isTesting = false

    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
        closeInterruptedNights()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seedSleepData") { SleepSampleData.seed(into: context) }
        #endif
    }

    // MARK: - Night

    func start(now: Date = .now) async -> StartResult {
        guard activeSession == nil else { return .started }
        guard await Self.requestMicrophone() else { return .microphoneDenied }
        let session = SleepSession(start: now)
        context.insert(session)
        try? context.save()
        activeSession = session
        minutes = []
        events = []
        lastError = nil
        listener.start(classify: true, callbacks: callbacks())
        return .started
    }

    /// Ends the night (no-op when nothing is being tracked). Called when the alarm is stopped with the tag.
    func finish(at date: Date = .now) {
        guard let session = activeSession else { return }
        activeSession = nil
        listener.stop { start, minute, heard in
            Task { @MainActor in self.closeNight(session, at: date, lastMinute: (start, minute, heard)) }
        }
    }

    private func closeNight(_ session: SleepSession, at date: Date, lastMinute: (Date, SleepMinute, [SleepEvent.Kind: [Date]])) {
        if date.timeIntervalSince(lastMinute.0) >= 30 { append(lastMinute.1, startingAt: lastMinute.0, heard: lastMinute.2, to: session) }
        if minutes.count < Self.minimumMinutes {
            context.delete(session)
        } else {
            session.close(at: date)
        }
        try? context.save()
        minutes = []
        events = []
    }

    private func callbacks() -> NightListener.Callbacks {
        var callbacks = NightListener.Callbacks()
        callbacks.minute = { start, minute, heard in
            Task { @MainActor in self.received(minute, startingAt: start, heard: heard) }
        }
        callbacks.failure = { error in
            Task { @MainActor in self.lastError = error.localizedDescription }
        }
        return callbacks
    }

    private func received(_ minute: SleepMinute, startingAt start: Date, heard: [SleepEvent.Kind: [Date]]) {
        guard let session = activeSession else { return }
        append(minute, startingAt: start, heard: heard, to: session)
        // Save every few minutes: if the app is killed, the night so far is kept.
        if minutes.count % 5 == 0 { try? context.save() }
        if start.timeIntervalSince(session.start) > Self.maximumDuration { finish(at: start) }
    }

    private func append(_ minute: SleepMinute, startingAt start: Date, heard: [SleepEvent.Kind: [Date]], to session: SleepSession) {
        // Minutes the engine missed (a call, the alarm) are filled as empty, so the timeline stays aligned.
        let index = max(0, Int((start.timeIntervalSince(session.start) / 60).rounded()))
        while minutes.count < index { minutes.append(SleepMinute()) }
        if minute.snoring, minutes.last?.snoring != true {
            events.append(SleepEvent(offset: start.timeIntervalSince(session.start), kind: .snoring))
        }
        minutes.append(minute)
        for (kind, dates) in heard {
            events += dates.map { SleepEvent(offset: $0.timeIntervalSince(session.start), kind: kind) }
        }
        session.minutesData = SleepCodec.encode(minutes)
        session.eventsData = SleepCodec.encode(events.sorted { $0.offset < $1.offset })
    }

    /// Nights left open by a crash or a forced quit: closed where their data ends.
    private func closeInterruptedNights() {
        let open = (try? context.fetch(FetchDescriptor<SleepSession>(predicate: #Predicate { $0.end == nil }))) ?? []
        for session in open {
            let count = session.minutes.count
            if count < Self.minimumMinutes {
                context.delete(session)
            } else {
                session.close(at: session.start.addingTimeInterval(Double(count) * 60))
            }
        }
        if !open.isEmpty { try? context.save() }
    }

    // MARK: - Placement test

    /// Listens for 10 seconds while the user moves under the covers. Nil if the microphone isn't available.
    func runPlacementTest() async -> Bool? {
        guard activeSession == nil, !isTesting, await Self.requestMicrophone() else { return nil }
        isTesting = true
        defer { isTesting = false }
        testLevel = 0
        var callbacks = NightListener.Callbacks()
        callbacks.level = { level in
            Task { @MainActor in self.testLevel = level }
        }
        listener.start(classify: false, callbacks: callbacks)
        try? await Task.sleep(for: Self.placementTestDuration)
        let (quietest, loudest) = await withCheckedContinuation { continuation in
            listener.extremes { continuation.resume(returning: ($0, $1)) }
        }
        listener.stop()
        testLevel = 0
        guard loudest > -150 else { return false }
        return PlacementCheck.isGood(floorDB: quietest, loudestDB: loudest)
    }

    // MARK: - Helpers

    static func requestMicrophone() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: true
        case .denied: false
        default: await AVAudioApplication.requestRecordPermission()
        }
    }
}

/// Battery state for the "plug it in" hints.
enum Battery {
    static var isCharging: Bool {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return [.charging, .full].contains(UIDevice.current.batteryState)
    }

    /// 0...1, nil when unknown (the simulator).
    static var level: Double? {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        return level < 0 ? nil : Double(level)
    }

    /// Below 20% and not charging: the night might not make it to the morning.
    static var isLowForTheNight: Bool {
        guard let level else { return false }
        return level < 0.2 && !isCharging
    }
}
