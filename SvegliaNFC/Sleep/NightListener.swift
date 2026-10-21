import Accelerate
import AVFoundation
@preconcurrency import SoundAnalysis
import SvegliaCore

/// Listens to the bedroom all night and turns the sound into numbers, one `SleepMinute` per minute.
///
/// Privacy: buffers are measured and classified in memory, then dropped. Nothing is written to disk,
/// nothing is sent anywhere. The only output is per-minute numbers and timed events.
///
/// Everything runs on a private serial queue; callbacks arrive on that queue too.
nonisolated final class NightListener: NSObject, @unchecked Sendable {
    struct Callbacks: Sendable {
        /// A minute ended (its start date, its numbers, the events heard during it).
        var minute: @Sendable (Date, SleepMinute, [SleepEvent.Kind: [Date]]) -> Void = { _, _, _ in }
        /// Loudness of the latest buffer in dB above the noise floor (about 10 times a second).
        var level: @Sendable (Double) -> Void = { _ in }
        /// Listening could not start or restart.
        var failure: @Sendable (Error) -> Void = { _ in }
    }

    private let queue = DispatchQueue(label: "com.sveglianfc.night-listener", qos: .utility)
    private var engine = AVAudioEngine()
    private var analyzer: SNAudioStreamAnalyzer?
    private var callbacks = Callbacks()
    private var classify = true
    private var isRunning = false
    private var observers: [NSObjectProtocol] = []

    // Minute accumulation (queue only).
    private var builder = MinuteBuilder()
    private var minuteStart = Date.now
    private var events: [SleepEvent.Kind: [Date]] = [:]
    private var lastEvent: [SleepEvent.Kind: Date] = [:]
    private var pendingNoise: Date?
    private var inLoudNoise = false
    private var classifyUntil = Date.distantPast
    private var restartAttempts = 0

    // Placement test (queue only).
    private var quietestDB = 0.0
    private var loudestDB = -160.0

    /// Classifier labels (Apple's built-in sound classifier) grouped the way the app shows them.
    private static let talkingLabels: Set<String> = ["speech", "whispering", "shout", "yell", "laughter", "crying_sobbing"]
    private static let confidence = 0.5
    /// dB above the floor that wake the classifier up (it sleeps when the room is quiet, to save battery).
    private static let classifyAbove = 3.0
    private static let classifyHangover: TimeInterval = 3

    // MARK: - Control

    /// Configures the audio session for a whole night of listening and starts the engine.
    /// `classify: false` only measures loudness (the 10-second placement test).
    func start(classify: Bool, callbacks: Callbacks) {
        queue.async { [self] in
            self.callbacks = callbacks
            self.classify = classify
            builder = MinuteBuilder()
            minuteStart = .now
            events = [:]
            lastEvent = [:]
            pendingNoise = nil
            quietestDB = 0
            loudestDB = -160
            restartAttempts = 0
            isRunning = true
            observeSession()
            startEngine()
        }
    }

    /// Stops listening and releases the microphone. Calls `completion` with the last, partial minute.
    func stop(completion: @escaping @Sendable (Date, SleepMinute, [SleepEvent.Kind: [Date]]) -> Void = { _, _, _ in }) {
        queue.async { [self] in
            isRunning = false
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            stopEngine()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            flushPendingNoise(force: true)
            completion(minuteStart, builder.finishMinute(), events)
            events = [:]
        }
    }

    /// Quietest and loudest buffer (dBFS) since `start`, for the placement test.
    func extremes(_ completion: @escaping @Sendable (_ quietest: Double, _ loudest: Double) -> Void) {
        queue.async { [self] in completion(quietestDB, loudestDB) }
    }

    // MARK: - Engine

    private func startEngine() {
        guard isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // Play-and-record mixes with other audio (a white-noise app keeps playing) instead of
            // silencing it as `.record` would; `.measurement` turns off automatic gain, so levels are honest.
            // The system plays AlarmKit alarms on its own: an interruption stops us cleanly and we restart after.
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers])
            try session.setActive(true)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw ListenerError.noMicrophone }

            input.removeTap(onBus: 0)
            if classify {
                let analyzer = SNAudioStreamAnalyzer(format: format)
                let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
                try analyzer.add(request, withObserver: self)
                self.analyzer = analyzer
            } else {
                analyzer = nil
            }
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
                self?.queue.async { self?.process(buffer, at: time.sampleTime) }
            }
            engine.prepare()
            try engine.start()
            restartAttempts = 0
        } catch {
            stopEngine()
            restartAttempts += 1
            if restartAttempts <= 5 {
                queue.asyncAfter(deadline: .now() + 3) { [weak self] in self?.startEngine() }
            } else {
                callbacks.failure(error)
            }
        }
    }

    private func stopEngine() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        analyzer?.completeAnalysis()
        analyzer = nil
    }

    private func restartEngine() {
        guard isRunning else { return }
        stopEngine()
        startEngine()
    }

    private func observeSession() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers.forEach(center.removeObserver)
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: nil) { [weak self] note in
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let ended = raw.flatMap(AVAudioSession.InterruptionType.init) == .ended
                // A call or the alarm took the microphone: the engine stopped; listen again once it's over.
                if ended { self?.queue.async { self?.restartEngine() } }
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: nil) { [weak self] note in
                let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                switch raw.flatMap(AVAudioSession.RouteChangeReason.init) {
                case .newDeviceAvailable, .oldDeviceUnavailable, .override:
                    self?.queue.async { self?.restartEngine() }
                default:
                    break
                }
            },
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil) { [weak self] _ in
                self?.queue.async { self?.restartEngine() }
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: nil) { [weak self] _ in
                self?.queue.async {
                    guard let self, self.isRunning else { return }
                    self.stopEngine()
                    self.engine = AVAudioEngine()
                    self.startEngine()
                }
            },
        ]
    }

    // MARK: - Measuring

    private func process(_ buffer: AVAudioPCMBuffer, at framePosition: AVAudioFramePosition) {
        guard isRunning, let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        let count = vDSP_Length(buffer.frameLength)
        var rms: Float = 0
        var peak: Float = 0
        vDSP_rmsqv(samples, 1, &rms, count)
        vDSP_maxmgv(samples, 1, &peak, count)
        let rmsDB = 20 * log10(Double(max(rms, 1e-9)))
        let peakDB = 20 * log10(Double(max(peak, 1e-9)))
        let now = Date.now

        if now.timeIntervalSince(minuteStart) >= 60 { closeMinute(now: now) }

        builder.add(rmsDB: rmsDB, peakDB: peakDB)
        let above = builder.loudness(of: rmsDB)
        callbacks.level(above)
        quietestDB = quietestDB == 0 ? rmsDB : min(quietestDB, rmsDB)
        loudestDB = max(loudestDB, rmsDB)

        guard classify else { return }
        // Loud noises are found by level; the classifier may later say it was a cough or speech.
        let peakAbove = max(0, peakDB - (builder.floor ?? peakDB))
        if !inLoudNoise, peakAbove >= builder.loudNoise {
            inLoudNoise = true
            builder.addNoise()
            pendingNoise = now
        } else if inLoudNoise, peakAbove < builder.loudNoise - 10 {
            inLoudNoise = false
        }
        flushPendingNoise(force: false)

        if above >= Self.classifyAbove { classifyUntil = now.addingTimeInterval(Self.classifyHangover) }
        if now < classifyUntil { analyzer?.analyze(buffer, atAudioFramePosition: framePosition) }
    }

    private func closeMinute(now: Date) {
        flushPendingNoise(force: true)
        let minute = builder.finishMinute()
        callbacks.minute(minuteStart, minute, events)
        events = [:]
        minuteStart = minuteStart.addingTimeInterval(60)
        // After a long gap (engine stopped), realign to the clock.
        if now.timeIntervalSince(minuteStart) >= 60 { minuteStart = now }
    }

    /// Keeps a loud-noise event only if, within a few seconds, the classifier didn't call it a cough or speech.
    private func flushPendingNoise(force: Bool) {
        guard let noise = pendingNoise, force || Date.now.timeIntervalSince(noise) > 3 else { return }
        pendingNoise = nil
        record(.noise, at: noise, spacing: 30)
    }

    private func record(_ kind: SleepEvent.Kind, at date: Date, spacing: TimeInterval) {
        if let last = lastEvent[kind], date.timeIntervalSince(last) < spacing { return }
        lastEvent[kind] = date
        events[kind, default: []].append(date)
    }

    fileprivate func handle(_ result: SNClassificationResult) {
        let now = Date.now
        for classification in result.classifications where classification.confidence >= Self.confidence {
            let label = classification.identifier
            if label == "snoring" {
                builder.addSnoring()
            } else if label == "cough" {
                if lastEvent[.cough].map({ now.timeIntervalSince($0) >= 2 }) ?? true { builder.addCough() }
                record(.cough, at: now, spacing: 2)
                pendingNoise = nil
            } else if Self.talkingLabels.contains(label) {
                builder.addTalking()
                record(.talking, at: now, spacing: 120)
                pendingNoise = nil
            }
        }
    }

    enum ListenerError: LocalizedError {
        case noMicrophone

        var errorDescription: String? { String(localized: "Il microfono non è disponibile.") }
    }
}

nonisolated extension NightListener: SNResultsObserving {
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        queue.async { [self] in handle(result) }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        // The classifier failing is not fatal: loudness and movement keep being measured.
    }
}
