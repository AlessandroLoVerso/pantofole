import Foundation

/// How a physical tag is recognised.
///
/// Every tag has a factory serial number (UID), which works with any cheap sticker, even a read-only one.
/// When a link domain is configured, pairing also writes `https://<host>/t/<token>` on the tag:
/// with the screen on, touching the tag then opens the app by itself (universal link).
public enum TagSerial {
    public static func hex<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
        bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

public struct TagLink: Sendable, Equatable {
    public static let pathPrefix = "/t/"

    public let host: String

    public init(host: String) {
        self.host = host
    }

    public func url(token: String) -> URL? {
        URL(string: "https://\(host)\(Self.pathPrefix)\(token)")
    }

    /// The token carried by a link written on one of our tags, or nil for any other URL.
    public func token(from url: URL) -> String? {
        guard url.scheme == "https", url.host() == host, url.path().hasPrefix(Self.pathPrefix) else { return nil }
        let token = String(url.path().dropFirst(Self.pathPrefix.count))
        guard !token.isEmpty, !token.contains("/") else { return nil }
        return token
    }

    /// 128 random bits, base64url without padding (22 characters): short enough for the smallest NTAG213.
    public static func makeToken<Generator: RandomNumberGenerator>(using generator: inout Generator) -> String {
        let bytes = (0..<16).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func makeToken() -> String {
        var generator = SystemRandomNumberGenerator()
        return makeToken(using: &generator)
    }
}
