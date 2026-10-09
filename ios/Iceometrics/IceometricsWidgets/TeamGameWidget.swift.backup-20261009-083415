import SwiftUI
import WidgetKit
import AppIntents

struct TeamGameEntry:
    TimelineEntry {
    let date: Date
    let game: WidgetGame?
    let selectedTeam: WidgetTeamChoice
    let hasSnapshot: Bool
}

struct TeamGameProvider:
    AppIntentTimelineProvider {
    func placeholder(
        in context: Context
    ) -> TeamGameEntry {
        TeamGameEntry(
            date: Date(),
            game: nil,
            selectedTeam: .NYR,
            hasSnapshot: false
        )
    }

    func snapshot(
        for configuration: TeamGameIntent,
        in context: Context
    ) async -> TeamGameEntry {
        makeEntry(
            configuration:
                configuration
        )
    }

    func timeline(
        for configuration: TeamGameIntent,
        in context: Context
    ) async -> Timeline<TeamGameEntry> {
        let entry =
            makeEntry(
                configuration:
                    configuration
            )

        let seconds:
            TimeInterval =
            entry.game?.isActive == true
            ? 5 * 60
            : 30 * 60

        return Timeline(
            entries: [entry],
            policy: .after(
                Date()
                    .addingTimeInterval(
                        seconds
                    )
            )
        )
    }

    private func makeEntry(
        configuration:
            TeamGameIntent
    ) -> TeamGameEntry {
        let snapshot =
            WidgetSnapshotStore.load()

        let teamCode =
            configuration.team.rawValue

        let game =
            snapshot.flatMap {
                selectGame(
                    for: teamCode,
                    from: $0.games
                )
            }

        return TeamGameEntry(
            date: Date(),
            game: game,
            selectedTeam:
                configuration.team,
            hasSnapshot:
                snapshot != nil
        )
    }

    private func selectGame(
        for teamCode: String,
        from games: [WidgetGame]
    ) -> WidgetGame? {
        let teamGames =
            games
                .filter {
                    $0.containsTeam(
                        teamCode
                    )
                }
                .sorted {
                    $0.startTime
                        < $1.startTime
                }

        // First priority: the selected team's game today.
        if let today =
            teamGames.first(
                where: {
                    $0.isToday
                }
            ) {
            return today
        }

        // Otherwise show the next genuinely future game.
        if let next =
            teamGames.first(
                where: {
                    $0.startTime > Date()
                    &&
                    (
                        $0.phase == .scheduled
                        || $0.phase == .starting
                    )
                }
            ) {
            return next
        }

        // Last resort: most recent completed game.
        return teamGames
            .filter {
                $0.phase == .final
            }
            .sorted {
                $0.startTime
                    > $1.startTime
            }
            .first
    }
}

struct ProbabilitySplitBackground:
    View {
    let game: WidgetGame

    private var awayShare:
        Double {
        if game.phase == .final,
           let awayScore =
            game.awayScore,
           let homeScore =
            game.homeScore,
           awayScore != homeScore {
            return awayScore > homeScore
                ? 1
                : 0
        }

        return max(
            0,
            min(
                1,
                game.awayProbability
                    ?? 0.5
            )
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let width =
                geometry.size.width

            let split =
                width * awayShare

            ZStack {
                HStack(spacing: 0) {
                    Color(
                        widgetHex:
                            game.awayTeam
                                .accentHex
                    )
                    .frame(
                        width: split
                    )

                    Color(
                        widgetHex:
                            game.homeTeam
                                .accentHex
                    )
                    .frame(
                        maxWidth:
                            .infinity
                    )
                }

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                .black
                                    .opacity(
                                        0.24
                                    ),
                                .clear,
                            ],
                            startPoint:
                                .leading,
                            endPoint:
                                .trailing
                        )
                    )
                    .frame(width: 34)
                    .offset(
                        x:
                            split
                            - width / 2
                    )

                LinearGradient(
                    colors: [
                        .black
                            .opacity(0.06),
                        .black
                            .opacity(0.30),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipped()
        }
    }
}

struct TeamGameWidgetView:
    View {
    @Environment(
        \.widgetFamily
    )
    private var family

    let entry: TeamGameEntry

    var body: some View {
        Group {
            if let game = entry.game {
                gameView(game)
            } else {
                emptyView
            }
        }
        .widgetURL(
            URL(string: "iceometrics://scoreboard")
        )
        .containerBackground(
            Color(
                red: 0.035,
                green: 0.040,
                blue: 0.050
            ),
            for: .widget
        )
    }

    private func gameView(
        _ game: WidgetGame
    ) -> some View {
        ZStack {
            ProbabilitySplitBackground(
                game: game
            )

            if family
                == .systemSmall {
                smallView(game)
            } else {
                mediumView(game)
            }
        }
    }

    private func smallView(
        _ game: WidgetGame
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                teamLabel(
                    game.awayTeam
                )

                Spacer()

                teamLabel(
                    game.homeTeam
                )
            }

            Spacer()

            if showsScore(game) {
                Text(
                    "\(game.awayScore ?? 0)  \(game.homeScore ?? 0)"
                )
                .font(
                    .system(
                        size: 34,
                        weight: .black,
                        design: .rounded
                    )
                )
                .monospacedDigit()
            } else {
                Text("VS")
                    .font(
                        .system(
                            size: 24,
                            weight: .black,
                            design: .rounded
                        )
                    )
            }

            Text(game.detail)
                .font(
                    .caption2
                        .weight(
                            .bold
                        )
                )
                .opacity(0.82)
                .padding(.top, 2)

            Spacer()

            HStack {
                probability(
                    game.awayProbability
                )

                Spacer()

                probability(
                    game.homeProbability
                )
            }
        }
        .foregroundStyle(.white)
        .padding(12)
    }

    private func mediumView(
        _ game: WidgetGame
    ) -> some View {
        HStack(spacing: 0) {
            VStack(
                alignment: .leading,
                spacing: 8
            ) {
                teamLabel(
                    game.awayTeam,
                    large: true
                )

                probability(
                    game.awayProbability,
                    large: true
                )
            }

            Spacer(minLength: 8)

            VStack(spacing: 5) {
                Text(
                    statusText(game)
                )
                .font(
                    .system(
                        size: 9,
                        weight: .black
                    )
                )
                .tracking(0.8)
                .padding(
                    .horizontal,
                    7
                )
                .padding(
                    .vertical,
                    4
                )
                .background(
                    Capsule()
                        .fill(
                            .black
                                .opacity(
                                    0.22
                                )
                        )
                )

                if showsScore(game) {
                    Text(
                        "\(game.awayScore ?? 0) – \(game.homeScore ?? 0)"
                    )
                    .font(
                        .system(
                            size: 38,
                            weight: .black,
                            design:
                                .rounded
                        )
                    )
                    .monospacedDigit()
                } else {
                    Text("VS")
                        .font(
                            .system(
                                size: 28,
                                weight:
                                    .black,
                                design:
                                    .rounded
                            )
                        )
                }

                Text(game.detail)
                    .font(
                        .caption
                            .weight(
                                .bold
                            )
                    )
                    .opacity(0.82)
            }

            Spacer(minLength: 8)

            VStack(
                alignment: .trailing,
                spacing: 8
            ) {
                teamLabel(
                    game.homeTeam,
                    large: true
                )

                probability(
                    game.homeProbability,
                    large: true
                )
            }
        }
        .foregroundStyle(.white)
        .padding(
            .horizontal,
            18
        )
        .padding(
            .vertical,
            14
        )
    }

    private var emptyView:
        some View {
        VStack(spacing: 7) {
            Image(
                systemName:
                    entry.hasSnapshot
                    ? "calendar.badge.clock"
                    : "arrow.clockwise.circle"
            )
            .font(.title2)
            .opacity(0.70)

            Text(
                entry.hasSnapshot
                ? "NO GAME FOUND"
                : "OPEN ICEOMETRICS"
            )
            .font(
                .caption
                    .weight(.black)
            )

            Text(
                entry.hasSnapshot
                ? entry.selectedTeam
                    .rawValue
                : "to update"
            )
            .font(.caption2)
            .opacity(0.55)
        }
        .foregroundStyle(.white)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }

    private func teamLabel(
        _ team: WidgetTeam,
        large: Bool = false
    ) -> some View {
        WidgetTeamLogoView(
            team: team,
            size: large ? 54 : 42
        )
    }

    private func probability(
        _ value: Double?,
        large: Bool = false
    ) -> some View {
        Text(
            value.map {
                "\(Int(($0 * 100).rounded()))%"
            } ?? "—"
        )
        .font(
            .system(
                size:
                    large
                    ? 24
                    : 15,
                weight: .black,
                design: .rounded
            )
        )
        .monospacedDigit()
    }

    private func showsScore(
        _ game: WidgetGame
    ) -> Bool {
        game.phase == .live
            || game.phase
                == .intermission
            || game.phase
                == .final
    }

    private func statusText(
        _ game: WidgetGame
    ) -> String {
        switch game.phase {
        case .live:
            return "LIVE"
        case .intermission:
            return "INTERMISSION"
        case .starting:
            return "STARTING"
        case .final:
            return "FINAL"
        case .postponed:
            return "POSTPONED"
        case .scheduled:
            return "PREGAME"
        case .unknown:
            return "GAME"
        }
    }
}

struct TeamGameWidget: Widget {
    let kind =
        "TeamGameWidget"

    var body:
        some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent:
                TeamGameIntent.self,
            provider:
                TeamGameProvider()
        ) { entry in
            TeamGameWidgetView(
                entry: entry
            )
        }
        .configurationDisplayName(
            "Team Game"
        )
        .description(
            "Follow the current or next game for any NHL team."
        )
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
        ])
    }
}
