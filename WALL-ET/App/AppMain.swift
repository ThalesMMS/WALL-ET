import SwiftUI

@main
struct WalletApp: App {
    @AppStorage("darkMode") private var darkMode = false
    @StateObject private var coordinator = AppCoordinator()
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(coordinator)
                .preferredColorScheme(darkMode ? .dark : .light)
        }
    }
}
