import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import SvegliaCore

// Compiled into the app and into both Screen Time extensions (monitor and shield).

/// An app block ("Blocco"): the apps the user chose, paused by Screen Time during a daily window.
/// The selection holds opaque tokens: neither the app nor the extensions learn which apps they are.
nonisolated struct AppBlock: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var window: BlockWindow
    /// A `FamilyActivitySelection`, encoded.
    var selectionData = Data()
    var isEnabled = true
    /// Set when the tag unlocked the block early: the end of the window it was unlocked in.
    var unlockedUntil: Date?

    var selection: FamilyActivitySelection {
        get { (try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData)) ?? FamilyActivitySelection() }
        set { selectionData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var isEmpty: Bool {
        let selection = selection
        return selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty && selection.webDomainTokens.isEmpty
    }

    func isUnlocked(at now: Date) -> Bool {
        unlockedUntil.map { now < $0 } ?? false
    }

    /// The window the apps are paused in right now, or nil when they are free.
    func activeInterval(at now: Date, calendar: Calendar = .current) -> DateInterval? {
        guard isEnabled, !isUnlocked(at: now) else { return nil }
        return window.currentInterval(at: now, calendar: calendar)
    }

    // MARK: Screen Time names

    static let namePrefix = "block."

    /// One Screen Time store per block, so overlapping blocks don't undo each other.
    var storeName: ManagedSettingsStore.Name { .init(Self.namePrefix + id.uuidString) }

    /// What `DeviceActivityCenter` monitors for this block: one daily schedule, or one per chosen weekday.
    var schedules: [(DeviceActivityName, DeviceActivitySchedule)] {
        let w = window
        func components(_ hour: Int, _ minute: Int, _ weekday: Int?) -> DateComponents {
            DateComponents(hour: hour, minute: minute, weekday: weekday)
        }
        if w.startsEveryDay {
            let schedule = DeviceActivitySchedule(
                intervalStart: components(w.startHour, w.startMinute, nil),
                intervalEnd: components(w.endHour, w.endMinute, nil),
                repeats: true
            )
            return [(DeviceActivityName(Self.namePrefix + id.uuidString), schedule)]
        }
        return w.weekdays.sorted().map { day in
            let schedule = DeviceActivitySchedule(
                intervalStart: components(w.startHour, w.startMinute, day),
                intervalEnd: components(w.endHour, w.endMinute, w.endWeekday(forStart: day)),
                repeats: true
            )
            return (DeviceActivityName(Self.namePrefix + id.uuidString + ".\(day)"), schedule)
        }
    }

    /// The block a monitored activity belongs to ("block.<uuid>" or "block.<uuid>.<weekday>").
    static func id(from activity: DeviceActivityName) -> UUID? {
        let raw = activity.rawValue
        guard raw.hasPrefix(namePrefix) else { return nil }
        let rest = raw.dropFirst(namePrefix.count)
        return UUID(uuidString: String(rest.prefix(36)))
    }
}

/// Blocks saved in the App Group, readable by the extensions.
nonisolated struct BlockStore {
    static let appGroup = "group.com.sveglianfc.app"
    private static let key = "appBlocks.v1"

    private var defaults: UserDefaults { UserDefaults(suiteName: Self.appGroup) ?? .standard }

    func load() -> [AppBlock] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([AppBlock].self, from: data)) ?? []
    }

    func save(_ blocks: [AppBlock]) {
        guard let data = try? JSONEncoder().encode(blocks) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func block(id: UUID) -> AppBlock? {
        load().first { $0.id == id }
    }

    func update(id: UUID, _ change: (inout AppBlock) -> Void) {
        var blocks = load()
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        change(&blocks[index])
        save(blocks)
    }
}

/// Puts the shield up or takes it down, through the block's own Screen Time store.
nonisolated enum BlockShield {
    static func apply(_ block: AppBlock) {
        let selection = block.selection
        let store = ManagedSettingsStore(named: block.storeName)
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
    }

    static func clear(_ block: AppBlock) {
        ManagedSettingsStore(named: block.storeName).clearAllSettings()
    }
}
