import AppIntents
import Observation

/// The "Scansiona" button on the ringing system alarm: opens the app straight on the scan.
nonisolated struct OpenScannerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Scansiona il tag"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { ScanRequest.shared.isPending = true }
        return .result()
    }
}

@Observable
final class ScanRequest {
    static let shared = ScanRequest()
    var isPending = false
}
