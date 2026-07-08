import Foundation

protocol NsTreatmentWriter: Sendable {
    func sendCarbs(grams: Double, at date: Date) async throws
    func sendTempTarget(targetMgdl: Int, durationMin: Int, reason: TtReason) async throws
    func cancelTempTarget() async throws
    func switchProfile(name: String, percentage: Int, durationMin: Int, timeshiftHours: Int, profileJson: String?) async throws
    func logEvent(eventType: String, at: Date, notes: String?, glucoseMgdl: Int?, durationMin: Int?) async throws
    func setLoopMode(_ mode: String, durationMin: Int) async throws
}

extension NsTreatmentWriter {
    /// Convenience for callers that don't need to specify a timeshift (defaults to 0 = no shift).
    func switchProfile(name: String, percentage: Int, durationMin: Int, profileJson: String?) async throws {
        try await switchProfile(name: name, percentage: percentage, durationMin: durationMin, timeshiftHours: 0, profileJson: profileJson)
    }
}
