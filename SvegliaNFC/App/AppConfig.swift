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

    /// Pages on the project site (GitHub Pages, `docs/`), linked from Settings. App Store review asks
    /// for the privacy policy to be reachable from inside the app.
    static let privacyPolicyURL = URL(string: "https://alessandroloverso.github.io/pantofole/privacy.html")!
    static let termsURL = URL(string: "https://alessandroloverso.github.io/pantofole/termini.html")!
    static let supportURL = URL(string: "https://alessandroloverso.github.io/pantofole/supporto.html")!

    // App blocks (Screen Time) are compiled only with the `APP_BLOCKS` Swift flag. v1 ships without
    // them: the App Store needs Apple's Family Controls (Distribution) approval first. To bring them
    // back: add `APP_BLOCKS` to the app target's Swift compilation conditions, put the
    // family-controls and app-group entitlements back in `Config/SvegliaNFC.entitlements`, and
    // embed BlockMonitor and BlockShield in the app again ("Embed Foundation Extensions").

    /// The trial alarm offered after pairing a tag: rings after a few seconds, three times.
    static let testDelay: TimeInterval = 10
    static let testRings = 3
}
