import SwiftUI
import WidgetKit

struct SettingsView: View {
    @ObservedObject var store: AppStore
    let writer: NsTreatmentWriter

    @State private var nsUrl = ""
    @State private var accessToken = ""
    @State private var urgentLow: String
    @State private var low: String
    @State private var high: String
    @State private var urgentHigh: String
    @State private var staleMinutes: String
    @State private var testingConnection = false
    @State private var connectionResult: String?
    @State private var liveActivityOn = {
        if #available(iOS 16.1, *) { return LiveActivityController.shared.isRunning }
        return false
    }()

    private let keychain = SharedConstants.credentialKeychain()
    private var thresholdUnit: String { store.displayUnits == .mmol ? "mmol/l" : "mg/dl" }

    init(store: AppStore, writer: NsTreatmentWriter) {
        self.store = store
        self.writer = writer
        let t = store.thresholds
        let isMmol = store.displayUnits == .mmol
        _urgentLow = State(initialValue: isMmol ? String(format: "%.1f", Double(t.urgentLow) / glucoseMmolFactor) : String(t.urgentLow))
        _low = State(initialValue: isMmol ? String(format: "%.1f", Double(t.low) / glucoseMmolFactor) : String(t.low))
        _high = State(initialValue: isMmol ? String(format: "%.1f", Double(t.high) / glucoseMmolFactor) : String(t.high))
        _urgentHigh = State(initialValue: isMmol ? String(format: "%.1f", Double(t.urgentHigh) / glucoseMmolFactor) : String(t.urgentHigh))
        _staleMinutes = State(initialValue: String(t.staleMinutes))
    }

    var body: some View {
        Form {
            Section("settings.ns_connection") {
                TextField("settings.ns_url", text: $nsUrl)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                SecureField("settings.access_token", text: $accessToken)
                    .autocapitalization(.none)

                Button(testingConnection ? String(localized: "settings.testing") : String(localized: "settings.test_connection")) {
                    testConnection()
                }
                .disabled(testingConnection || nsUrl.isEmpty || accessToken.isEmpty)

                if let result = connectionResult {
                    Text(result)
                        .foregroundColor(result.hasPrefix("OK") ? .green : .red)
                }
            }

            Section("settings.glucose_units") {
                Picker("settings.units", selection: Binding(
                    get: { store.displayUnits },
                    set: { store.setDisplayUnits($0) }
                )) {
                    Text("mg/dl").tag(GlucoseUnits.mgdl)
                    Text("mmol/l").tag(GlucoseUnits.mmol)
                }
                .pickerStyle(.segmented)
            }

            Section("settings.alarm_thresholds") {
                HStack {
                    TextField("settings.urgent_low", text: $urgentLow).keyboardType(.decimalPad)
                    Text(thresholdUnit).foregroundColor(.secondary)
                }
                HStack {
                    TextField("settings.low", text: $low).keyboardType(.decimalPad)
                    Text(thresholdUnit).foregroundColor(.secondary)
                }
                HStack {
                    TextField("settings.high", text: $high).keyboardType(.decimalPad)
                    Text(thresholdUnit).foregroundColor(.secondary)
                }
                HStack {
                    TextField("settings.urgent_high", text: $urgentHigh).keyboardType(.decimalPad)
                    Text(thresholdUnit).foregroundColor(.secondary)
                }
                HStack {
                    TextField("settings.stale_min", text: $staleMinutes).keyboardType(.numberPad)
                    Text("min").foregroundColor(.secondary)
                }
            }

            NavigationLink {
                ProfileView(store: store, writer: writer)
            } label: {
                Text("Profile")
            }

            if #available(iOS 16.1, *) {
                Section {
                    Toggle(String(localized: "settings.live_activity"), isOn: $liveActivityOn)
                        .onChange(of: liveActivityOn) { on in store.setLiveActivityEnabled(on) }
                } footer: {
                    Text(String(localized: "settings.live_activity_caption"))
                }
            }
        }
        .navigationTitle("settings.title")
        .onAppear { loadSettings() }
        .onDisappear { saveThresholds() }
    }

    private func loadSettings() {
        nsUrl = (try? keychain.get(.nsUrl)) ?? ""
        accessToken = (try? keychain.get(.nsAccessToken)) ?? ""
    }

    private func saveThresholds() {
        let isMmol = store.displayUnits == .mmol
        let toMgdl: (String, Int) -> Int = { str, fallback in
            guard let v = Double(str) else { return fallback }
            return isMmol ? Int((v * glucoseMmolFactor).rounded()) : Int(v)
        }
        let d = UserDefaults.standard
        let ulVal = toMgdl(urgentLow, 55)
        let loVal = toMgdl(low, 70)
        let hiVal = toMgdl(high, 180)
        let uhiVal = toMgdl(urgentHigh, 250)
        let staleVal = Int(staleMinutes) ?? 15
        d.set(ulVal, forKey: "threshold.urgentLow")
        d.set(loVal, forKey: "threshold.low")
        d.set(hiVal, forKey: "threshold.high")
        d.set(uhiVal, forKey: "threshold.urgentHigh")
        d.set(staleVal, forKey: "threshold.staleMinutes")
        store.updateThresholds(AlarmThresholds(
            urgentLow: ulVal,
            low: loVal,
            high: hiVal,
            urgentHigh: uhiVal,
            staleMinutes: staleVal
        ))
    }

    private func testConnection() {
        testingConnection = true
        connectionResult = nil

        guard let url = AppStore.normalizedURL(nsUrl) else {
            connectionResult = String(localized: "settings.invalid_url")
            testingConnection = false
            return
        }
        // keychain is already the shared-group store, so the widget sees these.
        try? keychain.set(url.absoluteString, for: .nsUrl)
        try? keychain.set(accessToken.trimmingCharacters(in: .whitespacesAndNewlines), for: .nsAccessToken)
        WidgetCenter.shared.reloadAllTimelines()

        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let transport = URLSessionTransport()
            let client = NightscoutClientLive(baseURL: url, accessToken: token, transport: transport)
            do {
                try await client.authorize()
                _ = try await client.fetchEntries(limit: 1)
                await MainActor.run {
                    connectionResult = String(localized: "settings.ok_connected")
                    store.reconnect(baseURL: url, accessToken: token)
                }
                try? await store.refresh()
            } catch {
                await MainActor.run { connectionResult = error.localizedDescription }
            }
            await MainActor.run { testingConnection = false }
        }
    }
}
