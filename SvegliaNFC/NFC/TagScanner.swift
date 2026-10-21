import CoreNFC
import Foundation
import SvegliaCore

/// Reads (and when pairing, optionally writes) one NFC tag through the system scan sheet.
///
/// Works with any NFC-A / ISO 15693 tag: the factory serial number identifies it.
/// In the Simulator, which has no NFC, every scan returns the same fake tag so the flows can be tried.
final class TagScanner: NSObject {
    enum Purpose {
        case verify
        /// Pairing; when a link is given it is written on the tag (if the tag is writable).
        case pair(link: URL?)
    }

    struct Reading: Equatable {
        let serial: String
        let wroteLink: Bool
    }

    enum ScanError: Error {
        case unavailable
        case busy
        case cancelled
        case failed(String)
    }

    static let simulatorSerial = "SIMULATORE"

    static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        NFCTagReaderSession.readingAvailable
        #endif
    }

    private var session: NFCTagReaderSession?
    private var continuation: CheckedContinuation<Reading, Error>?
    private var purpose = Purpose.verify

    func scan(_ purpose: Purpose, message: String) async throws -> Reading {
        #if targetEnvironment(simulator)
        try await Task.sleep(for: .milliseconds(800))
        return Reading(serial: Self.simulatorSerial, wroteLink: false)
        #else
        guard NFCTagReaderSession.readingAvailable else { throw ScanError.unavailable }
        guard continuation == nil else { throw ScanError.busy }
        self.purpose = purpose
        return try await withCheckedThrowingContinuation { continuation in
            guard let session = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693], delegate: self, queue: .main)
            else {
                continuation.resume(throwing: ScanError.unavailable)
                return
            }
            self.continuation = continuation
            self.session = session
            session.alertMessage = message
            session.begin()
        }
        #endif
    }

    private func finish(_ result: Result<Reading, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        session = nil
    }

    private func handle(_ tags: [NFCTag], in session: NFCTagReaderSession) {
        guard tags.count == 1, let tag = tags.first else {
            session.alertMessage = String(localized: "Avvicina un solo tag alla volta.")
            session.restartPolling()
            return
        }
        session.connect(to: tag) { error in
            MainActor.assumeIsolated {
                if let error {
                    session.invalidate(errorMessage: String(localized: "Lettura non riuscita, riprova."))
                    self.finish(.failure(ScanError.failed(error.localizedDescription)))
                    return
                }
                guard let serial = Self.serial(of: tag) else {
                    session.invalidate(errorMessage: String(localized: "Questo tag non è supportato."))
                    self.finish(.failure(ScanError.failed(String(localized: "Questo tag non è supportato."))))
                    return
                }
                if case .pair(let link?) = self.purpose, let ndefTag = Self.ndefTag(of: tag) {
                    self.write(link, to: ndefTag, serial: serial, in: session)
                } else {
                    self.complete(Reading(serial: serial, wroteLink: false), in: session)
                }
            }
        }
    }

    private func write(_ link: URL, to tag: any NFCNDEFTag, serial: String, in session: NFCTagReaderSession) {
        tag.queryNDEFStatus { status, _, _ in
            MainActor.assumeIsolated {
                guard status == .readWrite, let record = NFCNDEFPayload.wellKnownTypeURIPayload(url: link) else {
                    self.complete(Reading(serial: serial, wroteLink: false), in: session)
                    return
                }
                tag.writeNDEF(NFCNDEFMessage(records: [record])) { error in
                    MainActor.assumeIsolated {
                        self.complete(Reading(serial: serial, wroteLink: error == nil), in: session)
                    }
                }
            }
        }
    }

    private func complete(_ reading: Reading, in session: NFCTagReaderSession) {
        session.alertMessage = String(localized: "Fatto!")
        session.invalidate()
        finish(.success(reading))
    }

    private static func serial(of tag: NFCTag) -> String? {
        let identifier: Data? = switch tag {
        case .miFare(let tag): tag.identifier
        case .iso7816(let tag): tag.identifier
        case .iso15693(let tag): tag.identifier
        case .feliCa(let tag): tag.currentIDm
        @unknown default: nil
        }
        guard let identifier, !identifier.isEmpty else { return nil }
        return TagSerial.hex(identifier)
    }

    private static func ndefTag(of tag: NFCTag) -> (any NFCNDEFTag)? {
        switch tag {
        case .miFare(let tag): tag
        case .iso7816(let tag): tag
        case .iso15693(let tag): tag
        case .feliCa(let tag): tag
        @unknown default: nil
        }
    }
}

extension TagScanner: NFCTagReaderSessionDelegate {
    nonisolated func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: any Error) {
        let cancelled = (error as? NFCReaderError)?.code == .readerSessionInvalidationErrorUserCanceled
        let message = error.localizedDescription
        MainActor.assumeIsolated {
            finish(.failure(cancelled ? ScanError.cancelled : ScanError.failed(message)))
        }
    }

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        MainActor.assumeIsolated {
            handle(tags, in: session)
        }
    }
}
