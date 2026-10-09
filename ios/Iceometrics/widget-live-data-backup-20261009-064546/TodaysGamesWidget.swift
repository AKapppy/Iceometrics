import SwiftUI
import WidgetKit

struct TodaysGamesEntry: TimelineEntry {
    let date: Date
    let games: [WidgetGame]
}

struct TodaysGamesProvider: TimelineProvider {
    func placeholder(in context: Context)
        -> TodaysGamesEntry {
        TodaysGamesEntry(
            date: Date(),
            games: WidgetSampleData.games
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (TodaysGamesEntry) -> Void
    ) {
        completion(
            TodaysGamesEntry(
                date: Date(),
                games: WidgetSampleData.games
            )
        )
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (
            Timeline<TodaysGamesEntry>
        ) -> Void
    ) {
        let entry = TodaysGamesEntry(
            date: Date(),
            games: WidgetSampleData.games
        )

        completion(
            Timeline(
                entries: [entry],
                policy: .after(
                    Date().addingTimeInterval(15 * 60)
                )
            )
        )
    }
}

struct TodaysGameTile: View {
    let game: WidgetGame
    var featured = false

    var body: some View {
        ZStack {
            background

            VStack(spacing: featured ? 7 : 4) {
                HStack {
                    Text(game.awayTeam.abbreviation)
                    Spacer()
                    Text(game.homeTeam.abbreviation)
                }
                .font(
                    .system(
                        size: featured ? 14 : 11,
                        weight: .black,
                        design: .rounded
                    )
                )

                Spacer(minLength: 0)

                centerContent

                Spacer(minLength: 0)

                HStack {
                    Text(
                        percent(game.awayProbability)
                    )

                    Spacer()

                    Text(
                        percent(game.homeProbability)
                    )
                }
                .font(
                    .system(
                        size: featured ? 12 : 9,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .opacity(0.78)
            }
            .padding(featured ? 12 : 8)
        }
        .foregroundStyle(.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: featured ? 18 : 14,
                style: .continuous
            )
        )
    }

    @ViewBuilder
    private var centerContent: some View {
        switch game.phase {
        case .live, .intermission, .final:
            Text(
                "\(game.awayScore) – \(game.homeScore)"
            )
            .font(
                .system(
                    size: featured ? 28 : 18,
                    weight: .black,
                    design: .rounded
                )
            )
            .monospacedDigit()

            Text(game.detail)
                .font(
                    .system(
                        size: featured ? 10 : 8,
                        weight: .bold
                    )
                )
                .opacity(0.72)

        case .starting, .scheduled:
            Text(game.detail)
                .font(
                    .system(
                        size: featured ? 15 : 11,
                        weight: .black,
                        design: .rounded
                    )
                )
        }
    }

    private var background: some View {
        ZStack {
            Color.black.opacity(0.11)

            stateColor
                .opacity(stateOpacity)

            LinearGradient(
                colors: [
                    .white.opacity(0.05),
                    .clear,
                    .black.opacity(0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var stateColor: Color {
        switch game.phase {
        case .scheduled, .final:
            return Color(white: 0.22)

        case .starting, .intermission:
            return Color(white: 0.50)

        case .live:
            if game.awayScore == game.homeScore {
                return .white
            }

            if game.awayScore > game.homeScore {
                return Color(
                    widgetHex:
                        game.awayTeam.accentHex
                )
            }

            return Color(
                widgetHex:
                    game.homeTeam.accentHex
            )
        }
    }

    private var stateOpacity: Double {
        switch game.phase {
        case .live:
            return game.awayScore == game.homeScore
                ? 0.17
                : 0.58

        case .starting, .intermission:
            return 0.25

        case .scheduled, .final:
            return 0.12
        }
    }

    private func percent(
        _ value: Double
    ) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

struct TodaysGamesWidgetView: View {
    let entry: TodaysGamesEntry

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 9
        ) {
            HStack(alignment: .firstTextBaseline) {
                Text("TODAY'S GAMES")
                    .font(
                        .system(
                            size: 13,
                            weight: .black,
                            design: .rounded
                        )
                    )

                Spacer()

                Text("ICEOMETRICS")
                    .font(
                        .system(
                            size: 8,
                            weight: .bold
                        )
                    )
                    .tracking(0.7)
                    .opacity(0.42)
            }

            smartLayout
        }
        .padding(13)
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
    private var smartLayout: some View {
        let games = Array(entry.games.prefix(9))

        switch games.count {
        case 0:
            emptyState

        case 1:
            TodaysGameTile(
                game: games[0],
                featured: true
            )

        case 2:
            HStack(spacing: 7) {
                ForEach(games) { game in
                    TodaysGameTile(
                        game: game,
                        featured: true
                    )
                }
            }

        case 3:
            if let favorite = favoriteGame(
                in: games
            ) {
                HStack(spacing: 7) {
                    TodaysGameTile(
                        game: favorite,
                        featured: true
                    )
                    .frame(
                        maxWidth: .infinity
                    )

                    VStack(spacing: 7) {
                        ForEach(
                            games.filter {
                                $0.id != favorite.id
                            }
                        ) { game in
                            TodaysGameTile(
                                game: game
                            )
                        }
                    }
                }
            } else {
                threeColumnGrid(games)
            }

        case 4:
            twoByTwo(games)

        case 5:
            featuredPlusGrid(
                games,
                smallColumns: 2
            )

        case 6:
            threeColumnGrid(games)

        case 7:
            featuredPlusGrid(
                games,
                smallColumns: 3
            )

        case 8, 9:
            threeColumnGrid(games)

        default:
            threeColumnGrid(games)
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()

            Text("NO GAMES TODAY")
                .font(.caption.weight(.bold))
                .opacity(0.55)

            Spacer()
        }
        .frame(maxWidth: .infinity)
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
        smallColumns: Int
    ) -> some View {
        let favorite =
            favoriteGame(in: games)
            ?? games[0]

        let others = games.filter {
            $0.id != favorite.id
        }

        VStack(spacing: 7) {
            TodaysGameTile(
                game: favorite,
                featured: true
            )
            .frame(height: 105)

            compactGrid(
                others,
                columns: smallColumns
            )
        }
    }

    private func twoByTwo(
        _ games: [WidgetGame]
    ) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                TodaysGameTile(game: games[0])
                TodaysGameTile(game: games[1])
            }

            HStack(spacing: 7) {
                TodaysGameTile(game: games[2])
                TodaysGameTile(game: games[3])
            }
        }
    }

    private func threeColumnGrid(
        _ games: [WidgetGame]
    ) -> some View {
        compactGrid(
            games,
            columns: 3
        )
    }

    private func compactGrid(
        _ games: [WidgetGame],
        columns: Int
    ) -> some View {
        let gridItems = Array(
            repeating:
                GridItem(
                    .flexible(),
                    spacing: 7
                ),
            count: columns
        )

        return LazyVGrid(
            columns: gridItems,
            spacing: 7
        ) {
            ForEach(games) { game in
                TodaysGameTile(game: game)
                    .frame(minHeight: 72)
            }
        }
    }
}

struct TodaysGamesWidget: Widget {
    let kind = "TodaysGamesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: TodaysGamesProvider()
        ) { entry in
            TodaysGamesWidgetView(
                entry: entry
            )
        }
        .configurationDisplayName(
            "Today's Games"
        )
        .description(
            "Scores, predictions, and game states for today's slate."
        )
        .supportedFamilies([
            .systemLarge
        ])
    }
}
