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
                        : 20,
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
                            ? 11
                            : 10,
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
        WidgetTeamLogoView(
            team: team,
            size: featured ? 38 : 30
        )
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

// MARK: - Full-slate tile (9-16 games)

private struct FullSlateGameTile: View {
    let game: WidgetGame
    let ultraCompact: Bool

    private var logoSize: CGFloat { ultraCompact ? 17 : 23 }
    private var innerPad: CGFloat { ultraCompact ? 4 : 6 }

    var body: some View {
        ZStack {
            Color(white: 0.19)
            tint.opacity(tintOpacity)
            LinearGradient(
                colors: [.white.opacity(0.05), .clear, .black.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    WidgetTeamLogoView(team: game.awayTeam, size: logoSize)
                    Spacer(minLength: 0)
                    WidgetTeamLogoView(team: game.homeTeam, size: logoSize)
                }

                Spacer(minLength: 1)

                if game.phase == .live || game.phase == .intermission || game.phase == .final {
                    Text("\(game.awayScore ?? 0) – \(game.homeScore ?? 0)")
                        .font(.system(size: ultraCompact ? 15 : 19,
                                      weight: .black, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(game.detail)
                        .font(.system(size: ultraCompact ? 7 : 9, weight: .semibold))
                        .opacity(0.75)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                } else {
                    Text(game.detail)
                        .font(.system(size: ultraCompact ? 10 : 12,
                                      weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                }

                Spacer(minLength: 1)

                HStack(spacing: 0) {
                    Text(percent(game.awayProbability))
                    Spacer(minLength: 1)
                    Text(percent(game.homeProbability))
                }
                .font(.system(size: ultraCompact ? 8 : 9,
                              weight: .semibold, design: .rounded))
                .monospacedDigit()
                .opacity(0.82)
            }
            .padding(.horizontal, innerPad)
            .padding(.vertical, ultraCompact ? 4 : 6)
        }
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: ultraCompact ? 9 : 12,
                                    style: .continuous))
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }

    private var tint: Color {
        switch game.phase {
        case .live:
            let away = game.awayScore ?? 0
            let home = game.homeScore ?? 0
            if away == home { return .white }
            return Color(widgetHex: away > home
                ? game.awayTeam.accentHex : game.homeTeam.accentHex)
        case .intermission, .starting:
            return .white
        case .final, .scheduled, .postponed, .unknown:
            return .clear
        }
    }

    private var tintOpacity: Double {
        switch game.phase {
        case .live:
            return game.awayScore == game.homeScore ? 0.15 : 0.47
        case .intermission, .starting:
            return 0.13
        case .final, .scheduled, .postponed, .unknown:
            return 0
        }
    }
}

struct TodaysGamesWidgetView:
    View {
    let entry: TodaysGamesEntry
    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        // ICEOMETRICS_FULL_SLATE_16_V1
        GeometryReader { geometry in
            let displayGames = Array(entry.games.prefix(16))
            let contentHeight = max(CGFloat(0), geometry.size.height - 36)

            VStack(spacing: 0) {
                Text("TODAY'S GAMES")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(height: 22)
                    .accessibilityAddTraits(.isHeader)

                Group {
                    if displayGames.isEmpty {
                        emptyState
                            .padding(.horizontal, 8)
                    } else if widgetFamily == .systemExtraLarge {
                        // Only advertised for macOS, so the iPhone large
                        // widget retains its current visual layout.
                        extraLargeLayout(displayGames, height: contentHeight)
                    } else if displayGames.count >= 9 {
                        // 9 = 3x3; 10-12 = 4x3; 13-16 = 4x4.
                        // Every tile is measured against the available height.
                        fullSlateLayout(displayGames, height: contentHeight)
                    } else {
                        // Preserve the existing 1-8 game layouts exactly.
                        smartLayout(aspectRatio: geometry.size.width / max(geometry.size.height, 1))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: contentHeight)

                Text("ICEOMETRICS")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.9)
                    .opacity(0.45)
                    .frame(maxWidth: .infinity)
                    .frame(height: 14)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .foregroundStyle(.white)
        .widgetURL(IceometricsWidgetLinks.scoreboard)
        .containerBackground(
            Color(red: 0.045, green: 0.050, blue: 0.060),
            for: .widget
        )
    }

    // ICEOMETRICS_TODAYS_GAMES_MAC_XL_V1
    // The Mac-only family is large enough to spread all 16 NHL games across
    // four columns without compressing the header or footer.
    private func extraLargeLayout(
        _ games: [WidgetGame],
        height: CGFloat
    ) -> some View {
        let columns = games.count <= 2 ? games.count : (games.count <= 6 ? 3 : 4)
        let rows = (games.count + columns - 1) / columns
        let gap: CGFloat = 7
        let inset: CGFloat = 6
        let tileHeight = max(
            CGFloat(1),
            (height - inset * 2 - CGFloat(rows - 1) * gap) / CGFloat(rows)
        )

        return LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(minimum: 0), spacing: gap),
                count: columns
            ),
            alignment: .center,
            spacing: gap
        ) {
            ForEach(games) { game in
                Group {
                    if tileHeight >= 105 {
                        TodaysGameTile(game: game, featured: tileHeight >= 155)
                    } else {
                        FullSlateGameTile(game: game, ultraCompact: tileHeight < 74)
                    }
                }
                .frame(height: tileHeight)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, inset)
        .frame(height: height, alignment: .top)
    }

    private func fullSlateLayout(
        _ games: [WidgetGame],
        height: CGFloat
    ) -> some View {
        let columnCount = games.count <= 9 ? 3 : 4
        let rowCount = (games.count + columnCount - 1) / columnCount
        let gap: CGFloat = games.count >= 13 ? 3 : 5
        let verticalInset: CGFloat = 3
        let tileHeight = max(
            CGFloat(1),
            (height - verticalInset * 2 - CGFloat(rowCount - 1) * gap)
                / CGFloat(rowCount)
        )

        return LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(minimum: 0), spacing: gap),
                count: columnCount
            ),
            alignment: .center,
            spacing: gap
        ) {
            ForEach(games) { game in
                FullSlateGameTile(
                    game: game,
                    ultraCompact: games.count >= 13
                )
                .frame(height: tileHeight)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, verticalInset)
        .frame(height: height, alignment: .top)
    }

    @ViewBuilder
    private func smartLayout(aspectRatio: CGFloat) -> some View {
        let games =
            Array(
                entry.games.prefix(16)
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
            // ICEOMETRICS_THREE_GAMES_ASPECT_V1
            if aspectRatio <= 1.32 && favoriteGame(in: games) == nil {
                threeGameSquareLayout(games)
            } else {
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

    // 3 non-favorite games on square-like canvases: three equal tiles,
    // one empty quadrant. On wide canvases the existing row layout remains.
    // This does not depend on iOS vs macOS or any hardcoded pixel dimensions.
    private func threeGameSquareLayout(_ games: [WidgetGame]) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                TodaysGameTile(game: games[0])
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                TodaysGameTile(game: games[1])
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 7) {
                TodaysGameTile(game: games[2])
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    private var supportedSizes: [WidgetFamily] {
        #if os(macOS)
        return [.systemLarge, .systemExtraLarge]
        #else
        return [.systemLarge]
        #endif
    }

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
        .supportedFamilies(supportedSizes)
        .contentMarginsDisabled()
    }
}
