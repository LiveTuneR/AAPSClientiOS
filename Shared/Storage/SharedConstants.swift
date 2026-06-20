import Foundation

enum SharedConstants {
    static let appGroup = "group.com.nightaps.aapsclientios"
    static let keychainAccessGroup = "J6275F9A66.com.nightaps.aapsclientios.shared"
    static let keychainService = "org.diy.aapsclient"

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }
}
