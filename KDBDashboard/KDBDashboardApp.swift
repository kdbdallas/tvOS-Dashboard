import SwiftUI

@main
struct KDBDashboardApp: App {
    init() {
        KeychainStore.removeAllIfFreshInstall()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
