import SwiftUI

@main
struct IceometicsApp: App {
    @StateObject private var homeViewModel = HomeViewModel(
        repository: AppEnvironment.makeRepository()
    )
    @StateObject private var settings = AppSettingsStore()

    var body: some Scene {
        WindowGroup {
            RootView(homeViewModel: homeViewModel)
                .environmentObject(settings)
                .tint(
                    settings.accentColor(
                        for: homeViewModel.games
                            .flatMap { [$0.awayTeam, $0.homeTeam] }
                    )
                )
                .preferredColorScheme(
                    settings.preferredColorScheme
                )
                .background(MacWindowInitialSizeView())
        }
    }
}
