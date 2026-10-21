import DeviceActivity
import FamilyControls
import Foundation
import Observation
import SvegliaCore

/// App blocks ("Blocchi"): Screen Time pauses the chosen apps during each block's window.
/// The monitor extension puts the shield up and down on time; the app does it too, right away,
/// when a block changes while its window is running.
@Observable
final class BlockController {
    private(set) var blocks: [AppBlock] = []
    private(set) var authorization: AuthorizationStatus = AuthorizationCenter.shared.authorizationStatus
    private(set) var lastError: String?

    private let store = BlockStore()
    private let center = DeviceActivityCenter()

    init() {
        blocks = store.load()
    }

    var isAuthorized: Bool { authorization == .approved }

    // MARK: Reading

    func activeInterval(of block: AppBlock, now: Date = .now) -> DateInterval? {
        block.activeInterval(at: now)
    }

    /// Blocks whose apps are paused right now.
    func activeBlocks(now: Date = .now) -> [AppBlock] {
        blocks.filter { $0.activeInterval(at: now) != nil }
    }

    /// When every paused app is free again, or nil when nothing is paused.
    func pausedUntil(now: Date = .now) -> Date? {
        activeBlocks(now: now).compactMap { $0.activeInterval(at: now)?.end }.max()
    }

    /// A sensible new block: the night first, then the morning.
    func suggestedBlock() -> AppBlock {
        let hasNight = blocks.contains { $0.window.crossesMidnight }
        return hasNight ? BlockPreset.morning.makeBlock() : BlockPreset.night.makeBlock()
    }

    // MARK: Lifecycle

    /// Called when the app comes to the foreground.
    func refresh(now: Date = .now) {
        authorization = AuthorizationCenter.shared.authorizationStatus
        blocks = store.load()
        var changed = false
        for index in blocks.indices {
            if let until = blocks[index].unlockedUntil, until <= now {
                blocks[index].unlockedUntil = nil
                changed = true
            }
        }
        if changed { store.save(blocks) }
        applyShields(now: now)
    }

    func requestAuthorization() async -> Bool {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            lastError = String(localized: "Screen Time non ha dato il permesso.")
        }
        authorization = AuthorizationCenter.shared.authorizationStatus
        if isAuthorized {
            lastError = nil
            reschedule()
        }
        return isAuthorized
    }

    // MARK: Editing

    func save(_ block: AppBlock) {
        if let index = blocks.firstIndex(where: { $0.id == block.id }) {
            blocks[index] = block
        } else {
            blocks.append(block)
        }
        commit()
    }

    func delete(_ block: AppBlock) {
        blocks.removeAll { $0.id == block.id }
        BlockShield.clear(block)
        commit()
    }

    func setEnabled(_ enabled: Bool, for block: AppBlock) {
        guard let index = blocks.firstIndex(where: { $0.id == block.id }) else { return }
        blocks[index].isEnabled = enabled
        commit()
    }

    /// After a scan of the tag: the block's apps are free until its current window ends.
    func unlock(_ block: AppBlock, now: Date = .now) {
        guard let index = blocks.firstIndex(where: { $0.id == block.id }),
              let interval = blocks[index].window.currentInterval(at: now)
        else { return }
        blocks[index].unlockedUntil = interval.end
        store.save(blocks)
        BlockShield.clear(blocks[index])
    }

    func unlockAll(now: Date = .now) {
        for block in activeBlocks(now: now) { unlock(block, now: now) }
    }

    // MARK: Private

    private func commit() {
        store.save(blocks)
        reschedule()
        applyShields(now: .now)
    }

    /// Shield up for blocks inside their window, down for the others.
    private func applyShields(now: Date) {
        guard isAuthorized else { return }
        for block in blocks {
            if block.activeInterval(at: now) != nil, !block.isEmpty {
                BlockShield.apply(block)
            } else {
                BlockShield.clear(block)
            }
        }
    }

    /// Re-registers every enabled block with Screen Time.
    private func reschedule() {
        guard isAuthorized else { return }
        let ours = center.activities.filter { $0.rawValue.hasPrefix(AppBlock.namePrefix) }
        center.stopMonitoring(ours)
        lastError = nil
        for block in blocks where block.isEnabled && !block.isEmpty && block.window.isValid {
            for (name, schedule) in block.schedules {
                do {
                    try center.startMonitoring(name, during: schedule)
                } catch DeviceActivityCenter.MonitoringError.excessiveActivities {
                    lastError = String(localized: "Troppi blocchi attivi: iOS ne gestisce al massimo 20 fasce. Usa \"Ogni giorno\" o unisci dei blocchi.")
                } catch {
                    lastError = String(localized: "Screen Time non ha accettato l'orario di \"\(block.name)\".")
                }
            }
        }
    }
}

/// Ready-made windows offered when creating a block.
enum BlockPreset: CaseIterable, Identifiable {
    case night, morning, focus

    var id: Self { self }

    var title: String {
        switch self {
        case .night: String(localized: "Notte")
        case .morning: String(localized: "Mattina")
        case .focus: String(localized: "Concentrazione")
        }
    }

    var window: BlockWindow {
        switch self {
        case .night: BlockWindow(startHour: 23, startMinute: 0, endHour: 7, endMinute: 0)
        case .morning: BlockWindow(startHour: 7, startMinute: 0, endHour: 9, endMinute: 0)
        case .focus: BlockWindow(startHour: 9, startMinute: 0, endHour: 13, endMinute: 0, weekdays: Set(2...6))
        }
    }

    func makeBlock() -> AppBlock {
        AppBlock(name: title, window: window)
    }
}
