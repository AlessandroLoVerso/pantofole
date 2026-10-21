import Foundation
import ManagedSettings
import ManagedSettingsUI
import UIKit

/// The screen iOS shows over a paused app or website, in the app's night colours.
final class BlockShieldExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    private func makeConfiguration() -> ShieldConfiguration {
        let night = UIColor(red: 0.035, green: 0.043, blue: 0.086, alpha: 1)
        let sunrise = UIColor(red: 1.0, green: 0.56, blue: 0.24, alpha: 1)
        let muted = UIColor.white.withAlphaComponent(0.65)

        let now = Date.now
        let subtitle: String
        if let end = BlockStore().load().compactMap({ $0.activeInterval(at: now)?.end }).max() {
            let time = end.formatted(date: .omitted, time: .shortened)
            subtitle = String(localized: "Si sblocca alle \(time) o con il tuo tag.")
        } else {
            subtitle = String(localized: "Si sblocca con il tuo tag, da Sveglia NFC.")
        }
        let symbol = UIImage.SymbolConfiguration(pointSize: 56, weight: .semibold)
        let icon = UIImage(systemName: "moon.zzz.fill", withConfiguration: symbol)?
            .withTintColor(sunrise, renderingMode: .alwaysOriginal)

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: night,
            icon: icon,
            title: .init(text: String(localized: "In pausa"), color: .white),
            subtitle: .init(text: subtitle, color: muted),
            primaryButtonLabel: .init(text: String(localized: "Ok"), color: .black),
            primaryButtonBackgroundColor: sunrise
        )
    }
}
