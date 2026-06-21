import Foundation

enum SharedConstants {
    static let appGroup = "group.com.nightaps.aapsclientios"
    static let keychainAccessGroup = "J6275F9A66.com.nightaps.aapsclientios.shared"
    static let keychainService = "org.diy.aapsclient"

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    /// Credentials store on the shared keychain access group — read/written by both
    /// the app and the widget extension. This is the single source of truth.
    static func credentialKeychain() -> KeychainStore {
        KeychainStore(service: keychainService, accessGroup: keychainAccessGroup)
    }

    /// Pre-widget credentials location (app's default access group). Source for a
    /// one-time copy into `credentialKeychain()` at launch.
    static func legacyKeychain() -> KeychainStore {
        KeychainStore(service: keychainService)
    }
}
