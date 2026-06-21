import SwiftUI

struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: AppStore
    let writer: NsTreatmentWriter
    let profileName: String
    let rawJson: String

    private let profile: NsProfile
    private let profileUnits: GlucoseUnits

    @State private var basalBlocks: [EditableBlock]
    @State private var isfBlocks: [EditableBlock]
    @State private var icrBlocks: [EditableBlock]
    @State private var targetLowBlocks: [EditableBlock]
    @State private var targetHighBlocks: [EditableBlock]

    private let origBasal: [EditableBlock]
    private let origIsf: [EditableBlock]
    private let origIcr: [EditableBlock]
    private let origTargetLow: [EditableBlock]
    private let origTargetHigh: [EditableBlock]

    @State private var isPermanent = true
    @State private var durationStr = "60"
    @State private var showConfirm = false
    @State private var saving = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    @State private var addBlockTarget: AddBlockTarget?

    init(store: AppStore, writer: NsTreatmentWriter, profileName: String, rawJson: String) {
        self.store = store
        self.writer = writer
        self.profileName = profileName
        self.rawJson = rawJson

        guard let data = rawJson.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fatalError("Invalid profile JSON")
        }
        let parsed = NsMapping.parseProfileObject(obj)
        profile = parsed
        profileUnits = parsed.units
        let du = store.displayUnits

        func blocks(_ entries: [ScheduledValue], schedule: String) -> [EditableBlock] {
            entries.map { EditableBlock(startSeconds: $0.startSeconds,
                                         valueString: Self.formatDisplay($0.value, schedule: schedule, profileUnits: parsed.units, displayUnits: du)) }
        }
        func basalEntries(_ entries: [BasalEntry]) -> [EditableBlock] {
            entries.map { EditableBlock(startSeconds: $0.startSeconds,
                                         valueString: Self.formatDisplay($0.rate, schedule: "basal", profileUnits: parsed.units, displayUnits: du)) }
        }

        let basal = basalEntries(parsed.basal)
        let isf = blocks(parsed.sensitivity, schedule: "sens")
        let icr = blocks(parsed.carbRatio, schedule: "carbratio")
        let tLow = blocks(parsed.targetLow, schedule: "target")
        let tHigh = blocks(parsed.targetHigh, schedule: "target")

        _basalBlocks = State(initialValue: basal)
        _isfBlocks = State(initialValue: isf)
        _icrBlocks = State(initialValue: icr)
        _targetLowBlocks = State(initialValue: tLow)
        _targetHighBlocks = State(initialValue: tHigh)

        origBasal = basal
        origIsf = isf
        origIcr = icr
        origTargetLow = tLow
        origTargetHigh = tHigh
    }

    var body: some View {
        NavigationStack {
            Form {
                editableSection(String(localized: "edit.basal"), $basalBlocks, schedule: "basal", chartColor: .blue, unitLabel: "U/h")
                editableSection(String(localized: "edit.isf"), $isfBlocks, schedule: "sens", chartColor: .orange, unitLabel: store.displayUnits.rawValue)
                editableSection(String(localized: "edit.ic"), $icrBlocks, schedule: "carbratio", chartColor: .purple, unitLabel: "g/U")
                editableSection(String(localized: "edit.target_low"), $targetLowBlocks, schedule: "target_low", chartColor: .green, unitLabel: store.displayUnits.rawValue)
                editableSection(String(localized: "edit.target_high"), $targetHighBlocks, schedule: "target_high", chartColor: .green, unitLabel: store.displayUnits.rawValue)

                Section {
                    Toggle(String(localized: "edit.permanent"), isOn: $isPermanent)
                    if !isPermanent {
                        TextField(String(localized: "edit.duration_min"), text: $durationStr)
                            .keyboardType(.numberPad)
                    }
                }

                Section {
                    Text(String(localized: "edit.hint_accept_switch"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let msg = statusMessage {
                    Section {
                        Text(msg)
                            .foregroundColor(statusIsError ? .red : .green)
                    }
                }
            }
            .navigationTitle(String(format: String(localized: "edit.title"), profileName))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "edit.save")) { showConfirm = true }
                        .disabled(!allValid || saving)
                }
            }
            .confirmationDialog(String(localized: "edit.apply_title"), isPresented: $showConfirm) {
                Button(String(localized: "edit.apply"), action: save)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(changeSummary)
            }
            .sheet(item: $addBlockTarget) { target in
                addBlockSheet(for: target.schedule)
            }
        }
    }

    // MARK: - Section

    private func editableSection(_ title: String, _ blocks: Binding<[EditableBlock]>, schedule: String, chartColor: Color, unitLabel: String) -> some View {
        Section {
            ForEach(Array(blocks.wrappedValue.indices), id: \.self) { i in
                let block = blocks.wrappedValue[i]
                HStack {
                    Text(timeLabel(block.startSeconds))
                        .font(.body.monospacedDigit())
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .leading)
                    TextField("", text: Binding(
                        get: { blocks.wrappedValue[i].valueString },
                        set: { blocks.wrappedValue[i].valueString = $0 }
                    ))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(isFieldValid(blocks.wrappedValue[i].valueString, schedule: schedule) ? .primary : .red)
                    Button {
                        blocks.wrappedValue.removeAll { $0.id == block.id }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .disabled(block.startSeconds == 0)
                }
            }
            Button {
                addBlockTarget = AddBlockTarget(schedule: schedule)
            } label: {
                Label(String(localized: "edit.add_block"), systemImage: "plus")
            }
            StepChart(
                points: stepChartPoints(blocks.wrappedValue.map { ($0.startSeconds, Double($0.valueString) ?? 0) }),
                unitLabel: unitLabel,
                color: chartColor
            )
        } header: {
            if schedule == "basal" {
                let sum = dailyBasalUnits(basalBlocks.map { ($0.startSeconds, Double($0.valueString) ?? 0) })
                Text("\(title)  Σ \(String(format: "%.2f", sum)) ед")
            } else {
                Text(title)
            }
        }
    }

    // MARK: - Add block sheet

    private func addBlockSheet(for schedule: String) -> some View {
        AddBlockSheetView(
            schedule: schedule,
            displayUnits: store.displayUnits,
            profileUnits: profileUnits,
            existingSeconds: existingSeconds(for: schedule),
            onAdd: { startSeconds, valueString in
                appendBlock(EditableBlock(startSeconds: startSeconds, valueString: valueString), to: schedule)
                addBlockTarget = nil
            },
            onCancel: { addBlockTarget = nil }
        )
    }

    private func existingSeconds(for schedule: String) -> Set<Int> {
        switch schedule {
        case "basal": return Set(basalBlocks.map(\.startSeconds))
        case "sens": return Set(isfBlocks.map(\.startSeconds))
        case "carbratio": return Set(icrBlocks.map(\.startSeconds))
        case "target_low": return Set(targetLowBlocks.map(\.startSeconds))
        case "target_high": return Set(targetHighBlocks.map(\.startSeconds))
        default: return []
        }
    }

    private func appendBlock(_ block: EditableBlock, to schedule: String) {
        switch schedule {
        case "basal": basalBlocks.append(block); basalBlocks.sort { $0.startSeconds < $1.startSeconds }
        case "sens": isfBlocks.append(block); isfBlocks.sort { $0.startSeconds < $1.startSeconds }
        case "carbratio": icrBlocks.append(block); icrBlocks.sort { $0.startSeconds < $1.startSeconds }
        case "target_low": targetLowBlocks.append(block); targetLowBlocks.sort { $0.startSeconds < $1.startSeconds }
        case "target_high": targetHighBlocks.append(block); targetHighBlocks.sort { $0.startSeconds < $1.startSeconds }
        default: break
        }
    }

    // MARK: - Add block target

    private struct AddBlockTarget: Identifiable {
        let schedule: String
        var id: String { schedule }
    }

    // MARK: - Validation

    private var allValid: Bool {
        allFieldsValid(basalBlocks.map(\.valueString), schedule: "basal")
            && allFieldsValid(isfBlocks.map(\.valueString), schedule: "sens")
            && allFieldsValid(icrBlocks.map(\.valueString), schedule: "carbratio")
            && allFieldsValid(targetLowBlocks.map(\.valueString), schedule: "target_low")
            && allFieldsValid(targetHighBlocks.map(\.valueString), schedule: "target_high")
            && (isPermanent || (Int(durationStr).map { $0 > 0 } ?? false))
    }

    private func allFieldsValid(_ strings: [String], schedule: String) -> Bool {
        strings.allSatisfy { isFieldValid($0, schedule: schedule) }
    }

    private func isFieldValid(_ s: String, schedule: String) -> Bool {
        guard let v = Double(s), v > 0 else { return false }
        let pv = toProfileValue(v, schedule: schedule)
        return ProfileEdit.isValueInRange(pv, schedule: schedule, profileUnits: profileUnits)
    }

    // MARK: - Summary

    private var changeSummary: String {
        var lines: [String] = []

        func add(_ label: String, _ blocks: [EditableBlock], _ orig: [EditableBlock]) {
            for b in blocks {
                guard let origB = orig.first(where: { $0.startSeconds == b.startSeconds }),
                      b.valueString != origB.valueString else { continue }
                lines.append("\(label) \(timeLabel(b.startSeconds)): \(origB.valueString) → \(b.valueString)")
            }
            let removed = orig.filter { o in !blocks.contains(where: { $0.startSeconds == o.startSeconds }) }
            for r in removed {
                lines.append("\(label) \(timeLabel(r.startSeconds)): removed")
            }
            let added = blocks.filter { b in !orig.contains(where: { $0.startSeconds == b.startSeconds }) }
            for a in added {
                lines.append("\(label) \(timeLabel(a.startSeconds)): +\(a.valueString) (new)")
            }
        }

        add("Basal", basalBlocks, origBasal)
        add("ISF", isfBlocks, origIsf)
        add("IC", icrBlocks, origIcr)
        add("Target Low", targetLowBlocks, origTargetLow)
        add("Target High", targetHighBlocks, origTargetHigh)

        if lines.isEmpty { return String(localized: "edit.no_changes") }
        return lines.joined(separator: "\n")
    }

    // MARK: - Save

    private func applyEditsToJson() -> String? {
        var json = rawJson
        let schedules: [(blocks: [EditableBlock], orig: [EditableBlock], key: String)] = [
            (basalBlocks, origBasal, "basal"),
            (isfBlocks, origIsf, "sens"),
            (icrBlocks, origIcr, "carbratio"),
            (targetLowBlocks, origTargetLow, "target_low"),
            (targetHighBlocks, origTargetHigh, "target_high"),
        ]

        for s in schedules {
            guard hasChanges(s.blocks, s.orig) else { continue }
            do {
                if ProfileEdit.scheduleStructureChanged(orig: s.orig, current: s.blocks) {
                    let rebuilt: [(startSeconds: Int, value: Double)] = s.blocks
                        .sorted { $0.startSeconds < $1.startSeconds }
                        .compactMap { block in
                            guard let dv = Double(block.valueString) else { return nil }
                            return (block.startSeconds, toProfileValue(dv, schedule: s.key))
                        }
                    json = try ProfileEdit.replaceSchedule(s.key, blocks: rebuilt, in: json)
                } else {
                    let origByTime = Dictionary(uniqueKeysWithValues: s.orig.map { ($0.startSeconds, $0.valueString) })
                    let sorted = s.blocks.sorted { $0.startSeconds < $1.startSeconds }
                    var edits: [ProfileEdit.Edit] = []
                    for (i, block) in sorted.enumerated() {
                        guard let origStr = origByTime[block.startSeconds], origStr != block.valueString,
                              let dv = Double(block.valueString) else { continue }
                        edits.append(ProfileEdit.Edit(s.key, i, toProfileValue(dv, schedule: s.key)))
                    }
                    if !edits.isEmpty { json = try ProfileEdit.apply(edits, to: json) }
                }
            } catch {
                return nil
            }
        }
        return json
    }

    private func hasChanges(_ blocks: [EditableBlock], _ orig: [EditableBlock]) -> Bool {
        if ProfileEdit.scheduleStructureChanged(orig: orig, current: blocks) { return true }
        let origByTime = Dictionary(uniqueKeysWithValues: orig.map { ($0.startSeconds, $0.valueString) })
        return blocks.contains { origByTime[$0.startSeconds] != $0.valueString }
    }

    private func save() {
        saving = true
        let anyChanges = [
            (basalBlocks, origBasal), (isfBlocks, origIsf), (icrBlocks, origIcr),
            (targetLowBlocks, origTargetLow), (targetHighBlocks, origTargetHigh),
        ].contains { hasChanges($0.0, $0.1) }

        guard anyChanges, let modifiedJson = applyEditsToJson() else {
            statusMessage = String(localized: "edit.no_changes")
            statusIsError = false
            saving = false
            return
        }
        Task {
            do {
                let duration = isPermanent ? 0 : (Int(durationStr) ?? 0)
                try await writer.switchProfile(name: profileName, percentage: 100, durationMin: duration, profileJson: modifiedJson)
                try? await store.refresh()
                await MainActor.run {
                    statusMessage = duration == 0
                        ? String(localized: "edit.applied_permanent")
                        : String(format: String(localized: "edit.applied_temporary"), duration)
                    statusIsError = false
                }
                try? await Task.sleep(nanoseconds: 600_000_000)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    statusMessage = error.localizedDescription
                    statusIsError = true
                }
            }
            await MainActor.run { saving = false }
        }
    }

    // MARK: - Helpers

    private func toProfileValue(_ displayValue: Double, schedule: String) -> Double {
        switch schedule {
        case "basal", "carbratio":
            return displayValue
        case "sens", "target", "target_low", "target_high":
            return convertUnit(value: displayValue, from: store.displayUnits, to: profileUnits)
        default:
            return displayValue
        }
    }

    static func formatDisplay(_ profileValue: Double, schedule: String, profileUnits: GlucoseUnits, displayUnits: GlucoseUnits) -> String {
        let dv: Double
        switch schedule {
        case "basal", "carbratio":
            dv = profileValue
        case "sens", "target", "target_low", "target_high":
            dv = convertUnit(value: profileValue, from: profileUnits, to: displayUnits)
        default:
            dv = profileValue
        }
        return String(format: "%.2f", dv)
    }

    private func timeLabel(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 3600, (seconds % 3600) / 60)
    }
}
