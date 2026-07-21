import Foundation

/// How hard the app tries to stay alive in the background.
enum KeepAliveMode: String, CaseIterable, Identifiable {
    case disabled
    case normal
    case aggressive

    var id: String { rawValue }

    var shouldKeepAlive: Bool { self != .disabled }
}
