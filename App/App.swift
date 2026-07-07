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
        let rawUrl = (try? keychain.get(.nsUrl)) ?? nil
        let nsUrl = rawUrl.flatMap(AppStore.normalizedURL)
        let accessToken = (try? keychain.get(.nsAccessToken)) ?? ""

        // Self-heal accessibility for installs whose credentials were written by an
        // earlier build with the default WhenUnlocked class: re-set the values we just
        // read so they're rewritten as AfterFirstUnlock. Only runs when the device is
        // unlocked (otherwise the reads above already returned nil); harmless and
        // idempotent thereafter.
        if let rawUrl { try? keychain.set(rawUrl, for: .nsUrl) }
        if !accessToken.isEmpty { try? keychain.set(accessToken, for: .nsAccessToken) }

        let client: NightscoutClient
        if let url = nsUrl, !accessToken.isEmpty {
            client = NightscoutClientLive(baseURL: url, accessToken: accessToken, transport: URLSessionTransport())
        } else {
            client = UnconfiguredClient()
        }

        let alarmEngine = AlarmEngineLive(notifier: UNNotifier())
        let store = AppStore(
            client: client,
            alarmEngine: alarmEngine,
            glucoseNotificationPublisher: GlucoseNotificationController()
        )
        _store = StateObject(wrappedValue: store)
        writer = NsTreatmentWriterLive(clientProvider: { [store] in store.client })
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
                _ = try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                // Initial data refresh is owned by HomeView (.task) so errors surface there.
                // Start foreground polling here too: `.onChange(of: scenePhase)` only fires on
                // a transition observed *after* this view mounts, and on a cold launch the
                // scene is already `.active` by the time it mounts — so that handler's
                // `.active` case never fires and the 60 s timer never starts until the user
                // backgrounds/foregrounds the app at least once.
                keepAlive.enterForeground { Task { await store.refreshIfStale() } }
            }
            .onChange(of: scenePhase) { phase in
                switch phase {
                case .active:
                    // Fast foreground polling; refreshIfStale() no-ops within 60 s
                    // so this stays cheap while keeping the open app + Live Activity live.
                    keepAlive.enterForeground { Task { await store.refreshIfStale() } }
                case .background:
                    keepAlive.enterBackground { Task { try? await store.refresh() } }
                default:
                    break
                }
            }
        }
    }
}

final class UnconfiguredClient: NightscoutClient, @unchecked Sendable {
    func authorize() async throws { throw NsError.badURL }
    func fetchEntries(limit: Int) async throws -> [GlucoseReading] { throw NsError.badURL }
    func fetchTreatments(since: Date?) async throws -> [Treatment] { throw NsError.badURL }
    func fetchDeviceStatus() async throws -> LoopStatus? { throw NsError.badURL }
    func fetchProfile() async throws -> NsProfile { throw NsError.badURL }
    func fetchProfileStore() async throws -> NsProfileStore { throw NsError.badURL }
    func fetchSettings(identifier: String) async throws -> NsSettingsDocument? { throw NsError.badURL }
    func fetchRunningConfigCold() async throws -> NsRunningConfigCold? { throw NsError.badURL }
    func fetchRunningConfigHot() async throws -> NsRunningConfigHot? { throw NsError.badURL }
    func postTreatment(_ payload: [String: Any]) async throws { throw NsError.badURL }
}
