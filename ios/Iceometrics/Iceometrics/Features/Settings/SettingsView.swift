import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettingsStore
    let teams: [Team]
    let competitions: [ScoreboardCompetitionOption]

    @Environment(\.dismiss) private var dismiss
    @State private var customColor: Color

    init(
        settings: AppSettingsStore,
        teams: [Team],
        competitions: [ScoreboardCompetitionOption]
    ) {
        self.settings = settings
        self.teams = teams
        self.competitions = competitions
        _customColor = State(
            initialValue: Color(
                hex: settings.customAccentHex,
                fallback: .blue
            )
        )
    }

    var body: some View {
        Form {
            Section("Favorite Team") {
                Picker(
                    "Team",
                    selection: Binding(
                        get: { settings.favoriteTeamID ?? "" },
                        set: {
                            settings.favoriteTeamID = $0.isEmpty ? nil : $0
                        }
                    )
                ) {
                    Text("None").tag("")

                    ForEach(teams) { team in
                        Text(
                            team.leagueCode == "NHL"
                                ? team.name
                                : "\(team.name) · \(team.leagueCode)"
                        )
                        .tag(team.id)
                    }
                }

                Text("Your favorite team's game is shown first on the scoreboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Highlight Color") {
                Picker("Use", selection: $settings.accentMode) {
                    ForEach(AppAccentMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if settings.accentMode == .custom {
                    ColorPicker(
                        "Custom highlight",
                        selection: Binding(
                            get: { customColor },
                            set: { newValue in
                                customColor = newValue
                                if let hex = newValue.hexString {
                                    settings.customAccentHex = hex
                                }
                            }
                        ),
                        supportsOpacity: false
                    )
                } else if settings.accentMode == .favorite,
                          settings.favoriteTeamID == nil {
                    Text("Choose a favorite team to use its primary color.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Appearance") {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)

                Text("Dark mode is the default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Scoreboard") {
                Toggle(
                    "Show pregame MoneyPuck probabilities",
                    isOn: $settings.showPregamePredictions
                )
            }

            if !competitions.isEmpty {
                Section("Leagues & Events") {
                    ForEach(competitions) { competition in
                        Toggle(
                            competition.name,
                            isOn: Binding(
                                get: {
                                    settings.isCompetitionVisible(
                                        competition.id
                                    )
                                },
                                set: { visible in
                                    settings.setCompetitionVisible(
                                        competition.id,
                                        visible: visible
                                    )
                                }
                            )
                        )
                    }

                    Text(
                        "Only leagues and events available in the current season appear here. NHL events such as the All-Star Game remain part of NHL."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Reset Settings", role: .destructive) {
                    settings.reset()
                    customColor = Color(
                        hex: settings.customAccentHex,
                        fallback: .blue
                    )
                }
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}
