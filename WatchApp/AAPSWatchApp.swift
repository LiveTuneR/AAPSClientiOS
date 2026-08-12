import SwiftUI

@main
struct AAPSWatchApp: App {
    @StateObject private var model = WatchGlucoseViewModel()

    init() {
        WatchConnectivityReceiver.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView(model: model)
        }
    }
}
