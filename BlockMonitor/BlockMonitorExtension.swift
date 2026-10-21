import DeviceActivity
import Foundation

/// Woken by Screen Time at the start and end of each block's window, even when the app is closed.
final class BlockMonitorExtension: DeviceActivityMonitor {
    private let store = BlockStore()

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard let id = AppBlock.id(from: activity), let block = store.block(id: id), block.isEnabled else { return }
        // Unlocked early with the tag: stays free until this window ends (also when monitoring restarts mid-window).
        guard !block.isUnlocked(at: .now) else { return }
        BlockShield.apply(block)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard let id = AppBlock.id(from: activity), let block = store.block(id: id) else { return }
        BlockShield.clear(block)
        // The early unlock was for the window that just ended.
        store.update(id: id) { block in
            if let until = block.unlockedUntil, until <= Date.now.addingTimeInterval(60) { block.unlockedUntil = nil }
        }
    }
}
