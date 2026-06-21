import Foundation

enum ProfileEdit {
    struct Edit: Equatable {
        let scheduleKey: String
        let blockIndex: Int
        let newValue: Double

        init(_ scheduleKey: String, _ blockIndex: Int, _ newValue: Double) {
            self.scheduleKey = scheduleKey
            self.blockIndex = blockIndex
            self.newValue = newValue
        }
    }

    enum Error: Swift.Error {
        case invalidJson
        case invalidIndex(String, Int)
    }

    static let scheduleKeys = ["basal", "sens", "carbratio", "target_low", "target_high"]

    /// True if the set of block start times differs between orig and current
    /// (a block was added or removed). Value-only edits return false.
    static func scheduleStructureChanged(orig: [EditableBlock], current: [EditableBlock]) -> Bool {
        Set(orig.map(\.startSeconds)) != Set(current.map(\.startSeconds))
    }

    /// Range check for a profile value already converted to the profile's native units.
    static func isValueInRange(_ profileValue: Double, schedule: String, profileUnits: GlucoseUnits) -> Bool {
        guard profileValue > 0 else { return false }
        switch schedule {
        case "basal":     return profileValue >= 0.01 && profileValue <= 10
        case "sens":      return profileValue >= 1 && profileValue <= 500
        case "carbratio": return profileValue >= 0.5 && profileValue <= 200
        case "target", "target_low", "target_high":
            return profileUnits == .mmol ? profileValue >= 2 && profileValue <= 14 : profileValue >= 40 && profileValue <= 250
        default: return true
        }
    }

    static func apply(_ edits: [Edit], to rawJson: String) throws -> String {
        guard let data = rawJson.data(using: .utf8),
              var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Error.invalidJson
        }

        for edit in edits {
            guard var blocks = obj[edit.scheduleKey] as? [[String: Any]],
                  edit.blockIndex >= 0, edit.blockIndex < blocks.count else {
                throw Error.invalidIndex(edit.scheduleKey, edit.blockIndex)
            }
            blocks[edit.blockIndex]["value"] = edit.newValue
            obj[edit.scheduleKey] = blocks
        }

        return try serialize(obj)
    }

    static func replaceSchedule(
        _ scheduleKey: String,
        blocks: [(startSeconds: Int, value: Double)],
        in rawJson: String
    ) throws -> String {
        guard let data = rawJson.data(using: .utf8),
              var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Error.invalidJson
        }

        let newBlocks: [[String: Any]] = blocks.map { (secs, val) in
            let h = secs / 3600
            let m = (secs % 3600) / 60
            return [
                "time": String(format: "%02d:%02d", h, m),
                "timeAsSeconds": secs,
                "value": val
            ]
        }

        obj[scheduleKey] = newBlocks
        return try serialize(obj)
    }

    private static func serialize(_ obj: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: obj)
        guard let str = String(data: data, encoding: .utf8) else {
            throw Error.invalidJson
        }
        return str
    }
}
