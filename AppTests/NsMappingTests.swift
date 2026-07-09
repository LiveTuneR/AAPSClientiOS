import XCTest
@testable import AAPSClientiOS

final class NsMappingTests: XCTestCase {

    func test_mapsEntryToGlucoseReading() throws {
        let data = try loadFixture("entries")
        let readings = try NsMapping.glucose(from: data)
        XCTAssertEqual(readings.count, 2)
        XCTAssertEqual(readings[0].mgdl, 120)
        XCTAssertEqual(readings[0].trend, .flat)
        XCTAssertEqual(readings[1].mgdl, 124)
        XCTAssertEqual(readings[1].trend, .fortyFiveUp)
    }

    func test_mapsTreatments() throws {
        let data = try loadFixture("treatments")
        let treatments = try NsMapping.treatments(from: data)
        XCTAssertEqual(treatments.count, 4)

        let bolus = treatments[0]
        XCTAssertEqual(bolus.eventType, "Meal Bolus")
        XCTAssertEqual(bolus.insulin, 2.5)
        XCTAssertEqual(bolus.carbs, 30)

        let tt = treatments[1]
        XCTAssertEqual(tt.eventType, "Temporary Target")
        XCTAssertEqual(tt.durationMin, 60)
        XCTAssertEqual(tt.enteredBy, "AndroidAPS")

        let carbs = treatments[2]
        XCTAssertEqual(carbs.eventType, "Carb Correction")
        XCTAssertEqual(carbs.carbs, 15)
        XCTAssertEqual(carbs.enteredBy, "AAPSClient-iOS")
    }

    func test_mapsTreatmentDateFromCreatedAtWhenNumericFieldsMissing() throws {
        let data = try loadFixture("treatments")
        let treatments = try NsMapping.treatments(from: data)
        XCTAssertEqual(treatments.count, 4)

        let siteChange = treatments[3]
        XCTAssertEqual(siteChange.eventType, "Site Change")

        let expected = ISO8601DateFormatter().date(from: "2026-06-20T10:15:00Z")!
        XCTAssertEqual(siteChange.date.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1.0)
    }

    func test_mapsDeviceStatusToLoopStatus() throws {
        let data = try loadFixture("devicestatus")
        let status = try XCTUnwrap(try NsMapping.loopStatus(from: data))
        XCTAssertEqual(status.iob, 1.85)
        XCTAssertEqual(status.cob, 24.0)
        XCTAssertEqual(status.eventualBgMgdl, 110)
        XCTAssertEqual(status.tempBasalRate, 0.6)
        XCTAssertEqual(status.pumpBattery, 76)
        XCTAssertEqual(status.pumpReservoir, 142.5)
    }

    func test_mapsProfile() throws {
        let data = try loadFixture("profile")
        let profile = try NsMapping.profile(from: data)
        XCTAssertEqual(profile.units, .mgdl)
        XCTAssertEqual(profile.dia, 5)
        XCTAssertEqual(profile.basal.count, 3)
        XCTAssertEqual(profile.basal[0].startSeconds, 0)
        XCTAssertEqual(profile.basal[0].rate, 0.5)
    }

    func test_mapsTrendStrings() {
        XCTAssertEqual(TrendArrow.from(nsDirection: "DoubleUp"), .doubleUp)
        XCTAssertEqual(TrendArrow.from(nsDirection: "SingleUp"), .singleUp)
        XCTAssertEqual(TrendArrow.from(nsDirection: "FortyFiveUp"), .fortyFiveUp)
        XCTAssertEqual(TrendArrow.from(nsDirection: "Flat"), .flat)
        XCTAssertEqual(TrendArrow.from(nsDirection: "FortyFiveDown"), .fortyFiveDown)
        XCTAssertEqual(TrendArrow.from(nsDirection: "SingleDown"), .singleDown)
        XCTAssertEqual(TrendArrow.from(nsDirection: "DoubleDown"), .doubleDown)
        XCTAssertEqual(TrendArrow.from(nsDirection: nil), .none)
        XCTAssertEqual(TrendArrow.from(nsDirection: "NONE"), .none)
    }

    func test_emptyDeviceStatusReturnsNil() throws {
        let json = #"{"status":200,"result":[]}"#
        let status = try NsMapping.loopStatus(from: json.data(using: .utf8)!)
        XCTAssertNil(status)
    }

    func test_profileSwitchParsesNameAndPercentage() throws {
        let json = #"{"status":200,"result":[{"eventType":"Profile Switch","profile":"автотюн 10_07","percentage":140,"date":1}]}"#
        let r = try NsMapping.treatments(from: json.data(using: .utf8)!)
        XCTAssertEqual(r[0].profileName, "автотюн 10_07")
        XCTAssertEqual(r[0].percentage, 140)
    }

    func test_tempTargetParsesTargetVariants() throws {
        func tts(from json: String) throws -> [Treatment] {
            try NsMapping.treatments(from: json.data(using: .utf8)!)
        }

        let standard = #"{"status":200,"result":[{"eventType":"Temporary Target","duration":60,"targetBottom":90,"targetTop":100,"date":1}]}"#
        let r1 = try tts(from: standard)
        XCTAssertEqual(r1[0].targetBottom, 90)
        XCTAssertEqual(r1[0].targetTop, 100)

        let mgdlVariant = #"{"status":200,"result":[{"eventType":"Temporary Target","duration":60,"targetBottomMgdl":80,"targetTopMgdl":80,"date":1}]}"#
        let r2 = try tts(from: mgdlVariant)
        XCTAssertEqual(r2[0].targetBottom, 80)

        let singleTarget = #"{"status":200,"result":[{"eventType":"Temporary Target","duration":60,"target":100,"date":1}]}"#
        let r3 = try tts(from: singleTarget)
        XCTAssertEqual(r3[0].targetBottom, 100)

        let mmolField = #"{"status":200,"result":[{"eventType":"Temporary Target","duration":60,"targetBottom":4.5,"date":1}]}"#
        let r4 = try tts(from: mmolField)
        XCTAssertEqual(r4[0].targetBottom, 81)

        let fromReason = #"{"status":200,"result":[{"eventType":"Temporary Target","duration":60,"reason":"120 mg/dl","date":1}]}"#
        let r5 = try tts(from: fromReason)
        XCTAssertEqual(r5[0].targetBottom, 120)

        let cancelled = #"{"status":200,"result":[{"eventType":"Temporary Target","duration":0,"date":1}]}"#
        let r6 = try tts(from: cancelled)
        XCTAssertNil(r6[0].targetBottom)
    }

    func test_profileStoreParsesAllNames() throws {
        let data = try loadFixture("profile")
        let store = try NsMapping.profileStore(from: data)
        XCTAssertEqual(store.defaultProfileName, "Default")
        XCTAssertTrue(store.profileNames.contains("Default"))
        XCTAssertNotNil(store.rawJson["Default"])
    }

    func test_mapsDeviceStatusHistory() throws {
        let data = try loadFixture("devicestatus_history")
        let entries = try NsMapping.deviceStatusHistory(from: data)
        XCTAssertEqual(entries.count, 5)
        XCTAssertEqual(entries[0].iob, 1.20, accuracy: 0.001)
        XCTAssertEqual(entries[0].cob, 10.0, accuracy: 0.01)
        XCTAssertEqual(entries[3].iob, 2.10, accuracy: 0.001)
        XCTAssertEqual(entries[3].cob, 45.0, accuracy: 0.01)
        XCTAssertEqual(entries[4].iob, -0.30, accuracy: 0.001)
        XCTAssertTrue(entries[0].date > entries[4].date)
    }

    func test_mapsTempBasalAbsoluteAndPercent() throws {
        let data = try loadFixture("treatments_tempbasal")
        let treatments = try NsMapping.treatments(from: data)
        XCTAssertEqual(treatments.count, 3)

        let zero = treatments[0]
        XCTAssertEqual(zero.eventType, "Temp Basal")
        XCTAssertEqual(zero.durationMin, 30)
        XCTAssertEqual(zero.absolute, 0.0)
        XCTAssertNil(zero.tempBasalPercent)

        let pct = treatments[1]
        XCTAssertEqual(pct.durationMin, 45)
        XCTAssertNil(pct.absolute)
        XCTAssertEqual(pct.tempBasalPercent, 150)

        let cancel = treatments[2]
        XCTAssertEqual(cancel.durationMin, 0)
    }

    func test_mapsRunningConfigCold() throws {
        let data = try loadFixture("settings_aaps")
        let document = try XCTUnwrap(NsMapping.settingsDocument(from: data, identifier: NightscoutSettingsIdentifier.cold))
        let cold = try NsMapping.runningConfigCold(from: document)

        XCTAssertEqual(document.identifier, "aaps")
        XCTAssertEqual(document.app, "AAPS")
        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertEqual(cold.pump, "Dana-i")
        XCTAssertEqual(cold.version, "4.3.0")
        XCTAssertEqual(cold.isFakingTempsByExtendedBoluses, false)
        XCTAssertEqual(cold.authorizedClientIds, ["abc", "def"])
        XCTAssertEqual(cold.syncedPrefs["NsClientAcceptProfileSwitch"], "true")
        XCTAssertEqual(cold.syncedPrefsSnapshot.activePluginAps, "OpenAPSAMA")
        XCTAssertTrue(cold.remoteCapabilities.canRemoteProfileSwitch)
        XCTAssertTrue(cold.remoteCapabilities.canRemoteTempTarget)
        XCTAssertTrue(cold.remoteCapabilities.canRemoteCarbs)
        XCTAssertFalse(cold.remoteCapabilities.canRemoteRunningMode)
        XCTAssertTrue(cold.remoteCapabilities.usesWebSockets)
    }

    func test_mapsRunningConfigHot() throws {
        let data = try loadFixture("settings_aaps_state")
        let document = try XCTUnwrap(NsMapping.settingsDocument(from: data, identifier: NightscoutSettingsIdentifier.state))
        let hot = try NsMapping.runningConfigHot(from: document)

        XCTAssertEqual(hot.usedAutosensOnMainPhone, true)
        XCTAssertEqual(hot.activeScene?.sceneId, "school-sport")
        XCTAssertEqual(hot.activeScene?.durationMs, 5_400_000)
        XCTAssertEqual(hot.activeScene?.lifecycle, "ACTIVE")
        XCTAssertEqual(hot.activeScene?.ttNsId, "667")
        XCTAssertEqual(hot.activeScene?.rmNsId, "669")
    }

    func test_settingsDocumentReturnsNilWhenMissing() throws {
        let json = #"{"status":200,"result":null}"#
        let document = try NsMapping.settingsDocument(from: Data(json.utf8), identifier: NightscoutSettingsIdentifier.cold)
        XCTAssertNil(document)
    }

    func test_settingsDocumentToleratesAckShapedDocument() throws {
        let json = #"""
        {"status":200,"result":{"identifier":"aaps_clientcontrol_ack_c1","date":1,"utcOffset":0,"app":"AAPS","schemaVersion":1,"ack":{"clientId":"c1","commandCounter":1,"phase":"Done","status":"Ok","timestamp":1000,"signature":"abc"}}}
        """#
        let document = try NsMapping.settingsDocument(from: Data(json.utf8), identifier: "aaps_clientcontrol_ack_c1")
        XCTAssertNotNil(document)
        XCTAssertTrue(document?.runningConfigJson.contains("\"status\":\"Ok\"") == true)
    }

    func test_settingsDocumentThrowsOnInvalidRunningConfig() throws {
        let data = try loadFixture("settings_invalid")
        XCTAssertThrowsError(try NsMapping.settingsDocument(from: data, identifier: NightscoutSettingsIdentifier.cold))
    }

    func test_settingsDocumentThrowsOnInvalidRunningConfig_stillThrows() throws {
        let data = try loadFixture("settings_invalid")
        XCTAssertThrowsError(try NsMapping.settingsDocument(from: data, identifier: NightscoutSettingsIdentifier.cold))
    }

    func test_parsesSyncedPrefsPayloads() {
        let presets = NsSyncedPrefsParser.tempTargetPresets(from: "[{\"name\":\"Eating Soon\",\"targetMgdl\":90,\"durationMin\":45}]")
        XCTAssertEqual(presets, [NsSyncedTempTargetPreset(name: "Eating Soon", targetMgdl: 90, durationMin: 45)])

        let scenes = NsSyncedPrefsParser.sceneDefinitions(from: "[{\"sceneId\":\"school-sport\",\"name\":\"School Sport\"}]")
        XCTAssertEqual(scenes, [NsSceneDefinition(sceneId: "school-sport", name: "School Sport")])

        let qw = NsSyncedPrefsParser.quickWizardEntries(from: "[{\"name\":\"Breakfast\",\"carbs\":30}]")
        XCTAssertEqual(qw, [NsQuickWizardEntry(name: "Breakfast", carbs: 30, percentage: nil, note: nil)])
    }

    func test_remoteCapabilitiesSupportPreferenceKeyAliases() {
        let capabilities = NsRemoteCapabilities(syncedPrefs: [
            "ns_receive_profile_switch": "true",
            "ns_receive_temp_target": "true",
            "ns_receive_carbs": "true",
            "ns_receive_therapy_events": "false",
            "ns_receive_running_mode": "false",
            "ns_use_ws": "true",
        ])

        XCTAssertTrue(capabilities.canRemoteProfileSwitch)
        XCTAssertTrue(capabilities.canRemoteTempTarget)
        XCTAssertTrue(capabilities.canRemoteCarbs)
        XCTAssertFalse(capabilities.canRemoteTherapyEvents)
        XCTAssertFalse(capabilities.canRemoteRunningMode)
        XCTAssertTrue(capabilities.usesWebSockets)
    }

    func test_remoteCapabilitiesSupportNumericBooleanValues() {
        let capabilities = NsRemoteCapabilities(syncedPrefs: [
            "NsClientAcceptTempTarget": "1",
            "NsClientAcceptCarbs": "1",
            "NsClientAcceptTherapyEvent": "0",
            "NsClientAcceptRunningMode": "0",
        ])

        XCTAssertTrue(capabilities.canRemoteTempTarget)
        XCTAssertTrue(capabilities.canRemoteCarbs)
        XCTAssertFalse(capabilities.canRemoteTherapyEvents)
        XCTAssertFalse(capabilities.canRemoteRunningMode)
    }

    func test_loopModeTreatmentGetsReadableNotesFallback() throws {
        let json = #"{"status":200,"result":[{"eventType":"OpenAPS Offline","mode":"DISCONNECTED_PUMP","duration":30,"date":1}]}"#
        let r = try NsMapping.treatments(from: json.data(using: .utf8)!)
        XCTAssertEqual(r[0].notes, "Disconnected")
    }

    func test_loopModeTreatmentPrefersServerNotesOverModeFallback() throws {
        let json = #"{"status":200,"result":[{"eventType":"OpenAPS Offline","mode":"CLOSED_LOOP","duration":0,"notes":"Manual close","date":1}]}"#
        let r = try NsMapping.treatments(from: json.data(using: .utf8)!)
        XCTAssertEqual(r[0].notes, "Manual close")
    }
}
