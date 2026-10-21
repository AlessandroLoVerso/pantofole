import Foundation
import SvegliaCore

enum AppConfig {
    /// Domain that serves the tag links and `apple-app-site-association` (see `server/`).
    /// Empty: tags are recognised by their serial number only and nothing is written on them.
    static let tagLinkHost = ""

    static var tagLink: TagLink? { tagLinkHost.isEmpty ? nil : TagLink(host: tagLinkHost) }

    static let chain = WakeChain.standard
    static let editLock = EditLock.standard

    /// How many upcoming mornings get their whole chain registered with iOS in advance.
    static let chainsAhead = 2
    /// Upper bound on chains registered at once across all alarms (about 30 system alarms each),
    /// so many alarms never push the app past AlarmKit's limit.
    static let maxChains = 3

    /// The trial alarm offered after pairing a tag: rings after a few seconds, three times.
    static let testDelay: TimeInterval = 10
    static let testRings = 3
}
