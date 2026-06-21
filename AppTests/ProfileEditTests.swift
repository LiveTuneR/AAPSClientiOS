import XCTest
@testable import AAPSClientiOS

final class ProfileEditTests: XCTestCase {

    private var rawJson: String!

    override func setUp() {
        let data = try! loadFixture("profile")
        let store = try! NsMapping.profileStore(from: data)
        rawJson = store.rawJson["Default"]
    }

    func test_applyChangesBasalValueOnly() throws {
        let result = try ProfileEdit.apply([ProfileEdit.Edit("basal", 1, 0.9)], to: rawJson)

        let parsed = try parseRawProfile(result)
        XCTAssertEqual(parsed.basal[1].rate, 0.9)
        XCTAssertEqual(parsed.basal[0].rate, 0.5)
        XCTAssertEqual(parsed.basal[2].rate, 0.6)
        XCTAssertEqual(parsed.sensitivity[0].value, 49)
        XCTAssertEqual(parsed.carbRatio[0].value, 6)
        XCTAssertEqual(parsed.targetLow[0].value, 100)
        XCTAssertEqual(parsed.targetHigh[0].value, 100)
    }

    func test_applyChangesMultipleSchedules() throws {
        let edits: [ProfileEdit.Edit] = [
            ProfileEdit.Edit("basal", 0, 0.8),
            ProfileEdit.Edit("sens", 0, 55),
            ProfileEdit.Edit("carbratio", 0, 7),
        ]
        let result = try ProfileEdit.apply(edits, to: rawJson)

        let parsed = try parseRawProfile(result)
        XCTAssertEqual(parsed.basal[0].rate, 0.8)
        XCTAssertEqual(parsed.sensitivity[0].value, 55)
        XCTAssertEqual(parsed.carbRatio[0].value, 7)
    }

    func test_mergePreservesUntouchedFields() throws {
        let result = try ProfileEdit.apply([ProfileEdit.Edit("basal", 0, 0.8)], to: rawJson)

        let dict = try parseRawDict(result)
        XCTAssertEqual(dict["units"] as? String, "mg/dl")
        XCTAssertEqual(dict["dia"] as? Double, 5)
        XCTAssertEqual(dict["timezone"] as? String, "UTC")

        func timeBlockCount(_ key: String) -> Int {
            (dict[key] as? [[String: Any]])?.count ?? 0
        }
        XCTAssertEqual(timeBlockCount("basal"), 3)
        XCTAssertEqual(timeBlockCount("sens"), 1)
        XCTAssertEqual(timeBlockCount("carbratio"), 1)

        func firstBlock(_ key: String) -> [String: Any]? {
            (dict[key] as? [[String: Any]])?.first
        }

        let basalBlock0 = firstBlock("basal")
        XCTAssertEqual(basalBlock0?["time"] as? String, "00:00")
        XCTAssertEqual(basalBlock0?["timeAsSeconds"] as? Int, 0)

        let sensBlock = firstBlock("sens")
        XCTAssertEqual(sensBlock?["time"] as? String, "00:00")
        XCTAssertEqual(sensBlock?["timeAsSeconds"] as? Int, 0)
    }

    func test_unchangedValueRoundtripsWithoutDrift() throws {
        let result = try ProfileEdit.apply([ProfileEdit.Edit("basal", 1, 0.9)], to: rawJson)

        let dict = try parseRawDict(result)
        let basalBlocks = dict["basal"] as? [[String: Any]]

        let block0Value = (basalBlocks?[0]["value"] as? Double) ?? 0
        let block2Value = (basalBlocks?[2]["value"] as? Double) ?? 0

        XCTAssertEqual(block0Value, 0.5, accuracy: 0.0001)
        XCTAssertEqual(block2Value, 0.6, accuracy: 0.0001)

        let block1Value = (basalBlocks?[1]["value"] as? Double) ?? 0
        XCTAssertEqual(block1Value, 0.9, accuracy: 0.0001)
    }

    func test_applyInvalidIndexThrows() throws {
        let edits = [ProfileEdit.Edit("basal", 99, 1.0)]
        XCTAssertThrowsError(try ProfileEdit.apply(edits, to: rawJson)) { error in
            guard case ProfileEdit.Error.invalidIndex("basal", 99) = error else {
                XCTFail("Expected invalidIndex, got \(error)")
                return
            }
        }
    }

    func test_applyInvalidScheduleKeyThrows() throws {
        let edits = [ProfileEdit.Edit("nonexistent", 0, 1.0)]
        XCTAssertThrowsError(try ProfileEdit.apply(edits, to: rawJson)) { error in
            guard case ProfileEdit.Error.invalidIndex("nonexistent", 0) = error else {
                XCTFail("Expected invalidIndex, got \(error)")
                return
            }
        }
    }

    func test_applyInvalidJsonThrows() {
        let edits = [ProfileEdit.Edit("basal", 0, 1.0)]
        XCTAssertThrowsError(try ProfileEdit.apply(edits, to: "not json"))
    }

    func test_unitConversionMgdlToMmol() {
        let result = convertUnit(value: 49, from: .mgdl, to: .mmol)
        XCTAssertEqual(result, 2.72, accuracy: 0.01)
    }

    func test_unitConversionMmolToMgdl() {
        let result = convertUnit(value: 2.72, from: .mmol, to: .mgdl)
        XCTAssertEqual(result, 49, accuracy: 1)
    }

    func test_unitConversionSameUnits() {
        XCTAssertEqual(convertUnit(value: 100, from: .mgdl, to: .mgdl), 100)
        XCTAssertEqual(convertUnit(value: 5.5, from: .mmol, to: .mmol), 5.5)
    }

    // MARK: - replaceSchedule

    func test_replaceScheduleRebuildsArray() throws {
        let newBlocks: [(Int, Double)] = [
            (0, 0.3),
            (21600, 0.8),
            (43200, 0.5),
            (64800, 0.4),
        ]
        let result = try ProfileEdit.replaceSchedule("basal", blocks: newBlocks, in: rawJson)

        let dict = try parseRawDict(result)
        let basal = dict["basal"] as? [[String: Any]]
        XCTAssertEqual(basal?.count, 4)
        XCTAssertEqual(basal?[0]["time"] as? String, "00:00")
        XCTAssertEqual(basal?[0]["timeAsSeconds"] as? Int, 0)
        XCTAssertEqual(basal?[0]["value"] as? Double, 0.3)
        XCTAssertEqual(basal?[1]["time"] as? String, "06:00")
        XCTAssertEqual(basal?[1]["timeAsSeconds"] as? Int, 21600)
        XCTAssertEqual(basal?[1]["value"] as? Double, 0.8)
        XCTAssertEqual(basal?[3]["time"] as? String, "18:00")
        XCTAssertEqual(basal?[3]["timeAsSeconds"] as? Int, 64800)
        XCTAssertEqual(basal?[3]["value"] as? Double, 0.4)
    }

    func test_replaceSchedulePreservesOtherSchedules() throws {
        let newBlocks: [(Int, Double)] = [(0, 1.0)]
        let result = try ProfileEdit.replaceSchedule("basal", blocks: newBlocks, in: rawJson)

        let dict = try parseRawDict(result)
        XCTAssertEqual(dict["units"] as? String, "mg/dl")
        XCTAssertEqual(dict["dia"] as? Double, 5)
        XCTAssertEqual(dict["timezone"] as? String, "UTC")

        let sens = dict["sens"] as? [[String: Any]]
        XCTAssertEqual(sens?.count, 1)
        XCTAssertEqual(sens?[0]["value"] as? Double, 49)

        let cr = dict["carbratio"] as? [[String: Any]]
        XCTAssertEqual(cr?.count, 1)
        XCTAssertEqual(cr?[0]["value"] as? Double, 6)

        let tLow = dict["target_low"] as? [[String: Any]]
        XCTAssertEqual(tLow?.count, 1)
        XCTAssertEqual(tLow?[0]["value"] as? Double, 100)
    }

    func test_replaceScheduleInvalidJsonThrows() {
        let blocks: [(Int, Double)] = [(0, 1.0)]
        XCTAssertThrowsError(try ProfileEdit.replaceSchedule("basal", blocks: blocks, in: "not json"))
    }

    // MARK: - Mixed patch + replace

    func test_mixedPatchAndReplace() throws {
        var current = rawJson!

        // Patch: change basal[1] value only
        current = try ProfileEdit.apply([ProfileEdit.Edit("basal", 1, 0.9)], to: current)

        // Replace: rebuild sens with new blocks
        current = try ProfileEdit.replaceSchedule("sens", blocks: [(0, 55), (43200, 40)], in: current)

        let dict = try parseRawDict(current)
        let basal = dict["basal"] as? [[String: Any]]
        XCTAssertEqual(basal?.count, 3)
        XCTAssertEqual(basal?[1]["value"] as? Double, 0.9)
        XCTAssertEqual(basal?[0]["value"] as? Double, 0.5)

        let sens = dict["sens"] as? [[String: Any]]
        XCTAssertEqual(sens?.count, 2)
        XCTAssertEqual(sens?[0]["value"] as? Double, 55)
        XCTAssertEqual(sens?[1]["timeAsSeconds"] as? Int, 43200)
    }

    // MARK: - dailyBasalUnits

    func test_dailyBasalUnits() {
        // 0.5 U/h * 6h + 0.7 U/h * 6h + 0.6 U/h * 12h = 3.0 + 4.2 + 7.2 = 14.4
        let blocks: [(Int, Double)] = [(0, 0.5), (21600, 0.7), (43200, 0.6)]
        let result = dailyBasalUnits(blocks)
        XCTAssertEqual(result, 14.4, accuracy: 0.01)
    }

    func test_dailyBasalUnitsSingleBlock() {
        let blocks: [(Int, Double)] = [(0, 1.0)]
        XCTAssertEqual(dailyBasalUnits(blocks), 24.0, accuracy: 0.01)
    }

    func test_dailyBasalUnitsEmpty() {
        XCTAssertEqual(dailyBasalUnits([]), 0)
    }

    // MARK: - stepChartPoints

    func test_stepChartPoints() {
        let blocks: [(Int, Double)] = [(0, 0.5), (21600, 0.7), (43200, 0.6)]
        let points = stepChartPoints(blocks)

        XCTAssertEqual(points.count, 6) // double points at each boundary + closing at 24
        XCTAssertEqual(points[0].hour, 0.0)
        XCTAssertEqual(points[0].value, 0.5)
        XCTAssertEqual(points[1].hour, 6.0)
        XCTAssertEqual(points[1].value, 0.5)
        XCTAssertEqual(points[2].hour, 6.0)
        XCTAssertEqual(points[2].value, 0.7)
        XCTAssertEqual(points[3].hour, 12.0)
        XCTAssertEqual(points[3].value, 0.7)
        XCTAssertEqual(points[4].hour, 12.0)
        XCTAssertEqual(points[4].value, 0.6)
        XCTAssertEqual(points[5].hour, 24.0)
        XCTAssertEqual(points[5].value, 0.6)
    }

    func test_stepChartPointsUnsortedInput() {
        let blocks: [(Int, Double)] = [(43200, 0.6), (0, 0.5), (21600, 0.7)]
        let points = stepChartPoints(blocks)
        XCTAssertEqual(points[0].hour, 0.0)
        XCTAssertEqual(points[0].value, 0.5)
        XCTAssertEqual(points.last?.hour, 24.0)
    }

    func test_stepChartPointsEmpty() {
        XCTAssertEqual(stepChartPoints([]).count, 0)
    }

    func test_lenientUnitsParse() {
        XCTAssertEqual(GlucoseUnits(nsUnits: "mmol/l"), .mmol)
        XCTAssertEqual(GlucoseUnits(nsUnits: "mmol/L"), .mmol)
        XCTAssertEqual(GlucoseUnits(nsUnits: "mmol"), .mmol)
        XCTAssertEqual(GlucoseUnits(nsUnits: "MMOL/L"), .mmol)
        XCTAssertEqual(GlucoseUnits(nsUnits: "mg/dl"), .mgdl)
        XCTAssertEqual(GlucoseUnits(nsUnits: "mg/dL"), .mgdl)
        XCTAssertEqual(GlucoseUnits(nsUnits: nil), .mgdl)
    }

    // MARK: - scheduleStructureChanged

    func test_scheduleStructureUnchanged_whenOnlyValuesEdited() {
        let orig = [EditableBlock(startSeconds: 0, valueString: "0.5"), EditableBlock(startSeconds: 21600, valueString: "0.7")]
        let edited = [EditableBlock(startSeconds: 0, valueString: "0.9"), EditableBlock(startSeconds: 21600, valueString: "0.7")]
        XCTAssertFalse(ProfileEdit.scheduleStructureChanged(orig: orig, current: edited))
    }

    func test_scheduleStructureChanged_whenBlockAdded() {
        let orig = [EditableBlock(startSeconds: 0, valueString: "0.5")]
        let edited = [EditableBlock(startSeconds: 0, valueString: "0.5"), EditableBlock(startSeconds: 21600, valueString: "0.7")]
        XCTAssertTrue(ProfileEdit.scheduleStructureChanged(orig: orig, current: edited))
    }

    func test_scheduleStructureChanged_whenBlockRemoved() {
        let orig = [EditableBlock(startSeconds: 0, valueString: "0.5"), EditableBlock(startSeconds: 21600, valueString: "0.7")]
        let edited = [EditableBlock(startSeconds: 0, valueString: "0.5")]
        XCTAssertTrue(ProfileEdit.scheduleStructureChanged(orig: orig, current: edited))
    }

    // MARK: - isValueInRange

    func test_isValueInRange_basal() {
        XCTAssertTrue(ProfileEdit.isValueInRange(0.5, schedule: "basal", profileUnits: .mgdl))
        XCTAssertFalse(ProfileEdit.isValueInRange(50, schedule: "basal", profileUnits: .mgdl))
        XCTAssertFalse(ProfileEdit.isValueInRange(0, schedule: "basal", profileUnits: .mgdl))
    }

    func test_isValueInRange_targetRespectsUnits() {
        XCTAssertTrue(ProfileEdit.isValueInRange(100, schedule: "target", profileUnits: .mgdl))
        XCTAssertFalse(ProfileEdit.isValueInRange(100, schedule: "target", profileUnits: .mmol))
        XCTAssertTrue(ProfileEdit.isValueInRange(6, schedule: "target", profileUnits: .mmol))
    }

    // MARK: - duplicate time

    func test_duplicateStartSecondsDetected() {
        let blocks = [EditableBlock(startSeconds: 0, valueString: "0.5"), EditableBlock(startSeconds: 21600, valueString: "0.7")]
        XCTAssertTrue(blocks.contains { $0.startSeconds == 0 })
        XCTAssertFalse(blocks.contains { $0.startSeconds == 3600 })
    }

    // MARK: - Helpers

    private func parseRawProfile(_ raw: String) throws -> NsProfile {
        let dict = try parseRawDict(raw)
        return NsMapping.parseProfileObject(dict)
    }

    private func parseRawDict(_ raw: String) throws -> [String: Any] {
        guard let data = raw.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "test", code: 0)
        }
        return dict
    }
}
