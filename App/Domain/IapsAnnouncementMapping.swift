import Foundation

/// Maps this app's AndroidAPS-style loop-mode strings (the exact values HomeView's Loop Mode
/// menu already uses: `CLOSED_LOOP`/`OPEN_LOOP`/`SUSPENDED_BY_USER`/`DISCONNECTED_PUMP`) to the
/// Nightscout Announcement `notes` format iAPS's `Announcement.action` parser expects. Confirmed
/// against `/Users/jetcat/Projects/Dia/iaps` `FreeAPS/Sources/Models/Announcement.swift` — iAPS
/// only implements `looping:<bool>` and `pump:<suspend|resume>` for loop/pump control; neither
/// carries a duration argument (suspension is indefinite until a matching `resume`/`looping:true`).
enum IapsAnnouncementMapping {
    static func notes(forMode mode: String) -> String? {
        switch mode {
        case "CLOSED_LOOP": return "looping:true"
        case "OPEN_LOOP": return "looping:false"
        case "SUSPENDED_BY_USER", "DISCONNECTED_PUMP": return "pump:suspend"
        default: return nil
        }
    }
}
