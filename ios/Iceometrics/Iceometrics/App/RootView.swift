import SwiftUI

struct RootView: View {
    @ObservedObject var homeViewModel: HomeViewModel
    @EnvironmentObject private var settings: AppSettingsStore

    @State private var showingSettings = false
    @State private var selectedTab: AppTab = .scoreboard

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ScoreboardView(viewModel: homeViewModel)
                    .toolbar {
                        settingsToolbarItem
                    }
            }
            .tabItem {
                Label(
                    "Scoreboard",
                    systemImage: "hockey.puck.fill"
                )
            }
            .tag(AppTab.scoreboard)

            NavigationStack {
                StatsView()
                    .toolbar {
                        settingsToolbarItem
                    }
            }
            .tabItem {
                Label(
                    "Stats",
                    systemImage: "chart.bar.xaxis"
                )
            }
            .tag(AppTab.stats)

            NavigationStack {
                PredictionsView()
                    .toolbar {
                        settingsToolbarItem
                    }
            }
            .tabItem {
                Label(
                    "Predictions",
                    systemImage: "chart.line.uptrend.xyaxis"
                )
            }
            .tag(AppTab.predictions)

            NavigationStack {
                ModelsView()
                    .toolbar {
                        settingsToolbarItem
                    }
            }
            .tabItem {
                Label(
                    "Models",
                    systemImage: "function"
                )
            }
            .tag(AppTab.models)
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView(
                    settings: settings,
                    teams: availableTeams,
                    competitions: availableCompetitions
                )
            }
            #if os(macOS)
            .frame(
                minWidth: 520,
                idealWidth: 620,
                minHeight: 500,
                idealHeight: 620
            )
            #endif
        }
    }

    private func handleDeepLink(
        _ url: URL
    ) {
        guard url.scheme?.lowercased()
            == "iceometrics"
        else {
            return
        }

        let host =
            url.host?
                .lowercased()
            ?? ""

        let path =
            url.path
                .lowercased()

        switch host {
        case "scoreboard":
            selectedTab = .scoreboard

        case "predictions":
            selectedTab = .predictions

            // /pie is intentionally recognized here.
            // Once PredictionsView exposes its internal selection,
            // we can route directly to the pie subsection as well.
            if path == "/pie" {
                NotificationCenter.default.post(
                    name: .iceometricsOpenPredictionPie,
                    object: nil
                )
            }

        case "stats":
            selectedTab = .stats

        case "models":
            selectedTab = .models

        default:
            break
        }
    }

    @ToolbarContentBuilder
    private var settingsToolbarItem:
        some ToolbarContent {
        #if os(iOS)
        ToolbarItem(
            placement: .topBarLeading
        ) {
            settingsButton
        }
        #else
        ToolbarItem(
            placement: .primaryAction
        ) {
            settingsButton
        }
        #endif
    }

    private var settingsButton:
        some View {
        Button {
            showingSettings = true
        } label: {
            Image(
                systemName: "gearshape"
            )
        }
        .help("Settings")
        .accessibilityLabel(
            "Settings"
        )
    }

    private var availableCompetitions:
        [ScoreboardCompetitionOption] {
        var options:
            [String:
                ScoreboardCompetitionOption] = [:]

        for game in homeViewModel.games {
            let option =
                ScoreboardCompetitionCatalog
                    .option(
                        for: game
                    )

            options[option.id] =
                option
        }

        return options.values.sorted {
            if $0.id == "NHL" {
                return true
            }

            if $1.id == "NHL" {
                return false
            }

            return $0.name
                < $1.name
        }
    }

    private var availableTeams:
        [Team] {
        var byID:
            [String: Team] = [:]

        for game in homeViewModel.games {
            byID[
                game.awayTeam.id
            ] = game.awayTeam

            byID[
                game.homeTeam.id
            ] = game.homeTeam
        }

        return byID.values.sorted {
            if $0.leagueCode
                == $1.leagueCode {
                return $0.name
                    < $1.name
            }

            return $0.leagueCode
                < $1.leagueCode
        }
    }
}

private enum AppTab:
    Hashable {
    case scoreboard
    case stats
    case predictions
    case models
}

extension Notification.Name {
    static let iceometricsOpenPredictionPie =
        Notification.Name(
            "iceometrics.openPredictionPie"
        )
}

#Preview {
    RootView(
        homeViewModel:
            HomeViewModel(
                repository:
                    PreviewRepository()
            )
    )
    .environmentObject(
        AppSettingsStore()
    )
}

private actor PreviewRepository:
    HockeyRepositoryProtocol {
    func loadSnapshot(
        forceRefresh: Bool
    ) async throws -> LoadedSnapshot {
        LoadedSnapshot(
            snapshot:
                SampleData.snapshot,
            origin: .fixture
        )
    }
}
