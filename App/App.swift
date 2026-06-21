import SwiftUI
import BackgroundTasks
import UserNotifications
import AVFoundation

@main
struct AAPSClientApp: App {
    @StateObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    private let writer: NsTreatmentWriter
    private let bgScheduler: BackgroundScheduler
    private let keepAlive = AudioKeepAlive()

    init() {
        // Credentials live on the shared keychain group so the widget can read
        // them. Seed it once from the legacy default-group location (copy-only).
        let keychain = SharedConstants.credentialKeychain()
        try? SharedConstants.legacyKeychain().migrate(to: keychain)
        let nsUrl = ((try? keychain.get(.nsUrl)) ?? nil).flatMap(AppStore.normalizedURL)
        let accessToken = (try? keychain.get(.nsAccessToken)) ?? ""

        let client: NightscoutClient
        if let url = nsUrl, !accessToken.isEmpty {
            client = NightscoutClientLive(baseURL: url, accessToken: accessToken, transport: URLSessionTransport())
        } else {
            client = UnconfiguredClient()
        }

        let alarmEngine = AlarmEngineLive(notifier: UNNotifier())
        let store = AppStore(client: client, alarmEngine: alarmEngine)
        _store = StateObject(wrappedValue: store)
        writer = NsTreatmentWriterLive(client: client)
        bgScheduler = BackgroundScheduler(store: store)
        // BGTaskScheduler launch handlers MUST be registered before the app finishes
        // launching. Registering from a SwiftUI `.task` (post-launch) throws an
        // uncaught NSException ("All launch handlers must be registered before
        // application finishes launching") on iOS 16/18 and Mac alike.
        bgScheduler.register()
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack {
                    HomeView(store: store, writer: writer)
                }
                .tabItem { Label("tab.home", systemImage: "house") }

                NavigationStack {
                    HistoryView(store: store)
                }
                .tabItem { Label("tab.history", systemImage: "clock") }

                NavigationStack {
                    SettingsView(store: store, writer: writer)
                }
                .tabItem { Label("tab.settings", systemImage: "gear") }

                NavigationStack {
                    StatisticsView(store: store)
                }
                .tabItem { Label("Statistics", systemImage: "chart.bar") }
            }
            .task {
                bgScheduler.schedule()
                try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                // Initial data refresh is owned by HomeView (.task) so errors surface there.
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    keepAlive.start { Task { try? await store.refresh() } }
                }
            }
        }
    }
}

final class UnconfiguredClient: NightscoutClient {
    func authorize() async throws { throw NsError.badURL }
    func fetchEntries(limit: Int) async throws -> [GlucoseReading] { throw NsError.badURL }
    func fetchTreatments(since: Date?) async throws -> [Treatment] { throw NsError.badURL }
    func fetchDeviceStatus() async throws -> LoopStatus? { throw NsError.badURL }
    func fetchProfile() async throws -> NsProfile { throw NsError.badURL }
    func fetchProfileStore() async throws -> NsProfileStore { throw NsError.badURL }
    func postTreatment(_ payload: [String: Any]) async throws { throw NsError.badURL }
}
