import SwiftUI
import WidgetKit

struct TodaysGamesEntry:
    TimelineEntry {
    let date: Date
    let games: [WidgetGame]
    let hasSnapshot: Bool
}

struct TodaysGamesProvider:
    TimelineProvider {
    func placeholder(
        in context: Context
    ) -> TodaysGamesEntry {
        TodaysGamesEntry(
            date: Date(),
            games: [],
            hasSnapshot: false
        )
    }

    func getSnapshot(
        in context: Context,
        completion:
            @escaping (
                TodaysGamesEntry
            ) -> Void
    ) {
        completion(makeEntry())
    }

    func getTimeline(
        in context: Context,
        completion:
            @escaping (
                Timeline<
                    TodaysGamesEntry
                >
            ) -> Void
    ) {
        let entry =
            makeEntry()

        let hasActive =
            entry.games.contains {
                $0.isActive
            }

        let seconds:
            TimeInterval =
            hasActive
            ? 5 * 60
            : 30 * 60

        completion(
            Timeline(
                entries: [entry],
                policy: .after(
                    Date()
                        .addingTimeInterval(
                            seconds
                        )
                )
            )
        )
    }

    private func makeEntry()
        -> TodaysGamesEntry {
        let snapshot =
            WidgetSnapshotStore.load()

        let games =
            snapshot?
                .games
                .filter(\.isToday)
                .sorted {
                    $0.startTime
                        < $1.startTime
                }
            ?? []

        return TodaysGamesEntry(
            date: Date(),
            games: games,
            hasSnapshot:
                snapshot != nil
        )
    }
}

struct TodaysGameTile:
    View {
    let game: WidgetGame
    var featured = false

    var body: some View {
        ZStack {
            background

            VStack(
                spacing:
                    featured
                    ? 7
                    : 4
            ) {
                HStack(alignment: .top) {
                    teamStamp(game.awayTeam)

                    Spacer()

                    teamStamp(game.homeTeam)
                }

                Spacer(
                    minLength: 0
                )

                centerContent

                Spacer(
                    minLength: 0
                )

                HStack {
                    probability(
                        game.awayProbability
                    )

                    Spacer()

                    probability(
                        game.homeProbability
                    )
                }
                .font(
                    .system(
                        size:
                            featured
                            ? 12
                            : 9,
                        weight: .bold,
                        design:
                            .rounded
                    )
                )
                .opacity(0.78)
            }
            .padding(
                featured
                ? 12
                : 8
            )
        }
        .foregroundStyle(.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius:
                    featured
                    ? 18
                    : 14,
                style:
                    .continuous
            )
        )
    }

    @ViewBuilder
    private var centerContent:
        some View {
        switch game.phase {
        case .live,
             .intermission,
             .final:
            Text(
                "\(game.awayScore ?? 0) – \(game.homeScore ?? 0)"
            )
            .font(
                .system(
                    size:
                        featured
                        ? 28
                        : 18,
                    weight: .black,
                    design: .rounded
                )
            )
            .monospacedDigit()

            Text(game.detail)
                .font(
                    .system(
                        size:
                            featured
                            ? 10
                            : 8,
                        weight: .bold
                    )
                )
                .opacity(0.72)

        case .scheduled,
             .starting,
             .postponed,
             .unknown:
            Text(game.detail)
                .font(
                    .system(
                        size:
                            featured
                            ? 15
                            : 11,
                        weight: .black,
                        design: .rounded
                    )
                )
        }
    }

    private var background:
        some View {
        ZStack {
            Color.black
                .opacity(0.11)

            stateColor
                .opacity(
                    stateOpacity
                )

            LinearGradient(
                colors: [
                    .white
                        .opacity(
                            0.04
                        ),
                    .clear,
                    .black
                        .opacity(
                            0.15
                        ),
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            )
        }
    }

    private var stateColor:
        Color {
        switch game.phase {
        case .scheduled,
             .final,
             .postponed,
             .unknown:
            return Color(
                white: 0.22
            )

        case .starting,
             .intermission:
            return Color(
                white: 0.50
            )

        case .live:
            let away =
                game.awayScore ?? 0

            let home =
                game.homeScore ?? 0

            if away == home {
                return .white
            }

            if away > home {
                return Color(
                    widgetHex:
                        game.awayTeam
                            .accentHex
                )
            }

            return Color(
                widgetHex:
                    game.homeTeam
                        .accentHex
            )
        }
    }

    private var stateOpacity:
        Double {
        switch game.phase {
        case .live:
            let away =
                game.awayScore ?? 0

            let home =
                game.homeScore ?? 0

            return away == home
                ? 0.17
                : 0.58

        case .starting,
             .intermission:
            return 0.25

        case .scheduled,
             .final,
             .postponed,
             .unknown:
            return 0.12
        }
    }

    private func teamStamp(
        _ team: WidgetTeam
    ) -> some View {
        VStack(spacing: featured ? 4 : 3) {
            WidgetTeamLogoView(
                team: team,
                size: featured ? 28 : 21
            )

            Text(team.abbreviation)
                .font(
                    .system(
                        size:
                            featured
                            ? 10
                            : 8,
                        weight: .black,
                        design: .rounded
                    )
                )
                .lineLimit(1)
        }
    }

    private func probability(
        _ value: Double?
    ) -> Text {
        Text(
            value.map {
                "\(Int(($0 * 100).rounded()))%"
            } ?? "—"
        )
    }
}

struct TodaysGamesWidgetView:
    View {
    let entry: TodaysGamesEntry

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 9
        ) {
            HStack {
                Text("TODAY'S GAMES")
                    .font(
                        .system(
                            size: 13,
                            weight:
                                .black,
                            design:
                                .rounded
                        )
                    )

                Spacer()

                Text("ICEOMETRICS")
                    .font(
                        .system(
                            size: 8,
                            weight:
                                .bold
                        )
                    )
                    .tracking(0.7)
                    .opacity(0.42)
            }

            if entry.games.isEmpty {
                emptyState
            } else {
                smartLayout
            }
        }
        .foregroundStyle(.white)
        .padding(13)
        .widgetURL(
            URL(string: "iceometrics://scoreboard")
        )
        .containerBackground(
            Color(
                red: 0.045,
                green: 0.050,
                blue: 0.060
            ),
            for: .widget
        )
    }

    @ViewBuilder
    private var smartLayout:
        some View {
        let games =
            Array(
                entry.games.prefix(9)
            )

        switch games.count {
        case 1:
            TodaysGameTile(
                game: games[0],
                featured: true
            )

        case 2:
            HStack(spacing: 7) {
                ForEach(games) {
                    game in
                    TodaysGameTile(
                        game: game,
                        featured: true
                    )
                }
            }

        case 3:
            if let favorite =
                favoriteGame(
                    in: games
                ) {
                HStack(spacing: 7) {
                    TodaysGameTile(
                        game:
                            favorite,
                        featured:
                            true
                    )

                    VStack(
                        spacing: 7
                    ) {
                        ForEach(
                            games.filter {
                                $0.id
                                    != favorite.id
                            }
                        ) { game in
                            TodaysGameTile(
                                game:
                                    game
                            )
                        }
                    }
                }
            } else {
                compactGrid(
                    games,
                    columns: 3
                )
            }

        case 4:
            twoByTwo(games)

        case 5:
            featuredPlusGrid(
                games,
                columns: 2
            )

        case 6:
            compactGrid(
                games,
                columns: 3
            )

        case 7:
            featuredPlusGrid(
                games,
                columns: 3
            )

        case 8, 9:
            compactGrid(
                games,
                columns: 3
            )

        default:
            compactGrid(
                games,
                columns: 3
            )
        }
    }

    private var emptyState:
        some View {
        VStack(spacing: 8) {
            Spacer()

            Image(
                systemName:
                    entry.hasSnapshot
                    ? "calendar"
                    : "arrow.clockwise.circle"
            )
            .font(.title2)
            .opacity(0.60)

            Text(
                entry.hasSnapshot
                ? "NO NHL GAMES TODAY"
                : "OPEN ICEOMETRICS TO UPDATE"
            )
            .font(
                .caption
                    .weight(.bold)
            )
            .opacity(0.70)

            Spacer()
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }

    private func favoriteGame(
        in games: [WidgetGame]
    ) -> WidgetGame? {
        games.first {
            $0.isFavoriteTeamGame
        }
    }

    @ViewBuilder
    private func featuredPlusGrid(
        _ games: [WidgetGame],
        columns: Int
    ) -> some View {
        let featured =
            favoriteGame(in: games)
            ?? games[0]

        let others =
            games.filter {
                $0.id
                    != featured.id
            }

        VStack(spacing: 7) {
            TodaysGameTile(
                game: featured,
                featured: true
            )
            .frame(height: 105)

            compactGrid(
                others,
                columns: columns
            )
        }
    }

    private func twoByTwo(
        _ games: [WidgetGame]
    ) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                TodaysGameTile(
                    game: games[0]
                )

                TodaysGameTile(
                    game: games[1]
                )
            }

            HStack(spacing: 7) {
                TodaysGameTile(
                    game: games[2]
                )

                TodaysGameTile(
                    game: games[3]
                )
            }
        }
    }

    private func compactGrid(
        _ games: [WidgetGame],
        columns: Int
    ) -> some View {
        let items =
            Array(
                repeating:
                    GridItem(
                        .flexible(),
                        spacing: 7
                    ),
                count: columns
            )

        return LazyVGrid(
            columns: items,
            spacing: 7
        ) {
            ForEach(games) {
                game in
                TodaysGameTile(
                    game: game
                )
                .frame(
                    minHeight: 72
                )
            }
        }
    }
}

struct TodaysGamesWidget:
    Widget {
    let kind =
        "TodaysGamesWidget"

    var body:
        some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider:
                TodaysGamesProvider()
        ) { entry in
            TodaysGamesWidgetView(
                entry: entry
            )
        }
        .configurationDisplayName(
            "Today's Games"
        )
        .description(
            "Today's real NHL scores and MoneyPuck probabilities."
        )
        .supportedFamilies([
            .systemLarge,
        ])
    }
}
