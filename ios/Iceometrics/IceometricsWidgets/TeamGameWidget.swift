import SwiftUI
import WidgetKit
import AppIntents
#if canImport(UIKit)
import UIKit
#endif

struct TeamGameEntry: TimelineEntry {
    let date: Date
    let game: WidgetGame?
    let hasSnapshot: Bool
    let selectedTeam: String
}

// This must be an AppIntentTimelineProvider; StaticConfiguration never
// exposes the 'Edit Widget' team picker on the iPhone Home Screen.
struct TeamGameProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TeamGameEntry {
        TeamGameEntry(
            date: Date(),
            game: nil,
            hasSnapshot: false,
            selectedTeam: "NYR"
        )
    }

    func snapshot(
        for configuration: TeamGameIntent,
        in context: Context
    ) async -> TeamGameEntry {
        makeEntry(for: configuration)
    }

    func timeline(
        for configuration: TeamGameIntent,
        in context: Context
    ) async -> Timeline<TeamGameEntry> {
        // A widget timeline can refresh without the host app being open.
        // Use the saved values immediately; replace them only with a
        // validated MoneyPuck forecast for this exact NHL matchup.
        var entry = makeEntry(for: configuration)
        if let game = entry.game,
           let odds = await WidgetMoneyPuckForecast.fetch(for: game) {
            entry = TeamGameEntry(
                date: Date(),
                game: game.withForecast(
                    away: odds.away, home: odds.home
                ),
                hasSnapshot: entry.hasSnapshot,
                selectedTeam: entry.selectedTeam
            )
        }

        let seconds: TimeInterval
        if let game = entry.game {
            switch game.phase {
            case .live, .intermission, .starting:
                seconds = 5 * 60
            case .scheduled:
                seconds = game.startTime.timeIntervalSinceNow < 60 * 60
                    ? 5 * 60
                    : 15 * 60
            case .final, .postponed, .unknown:
                seconds = 30 * 60
            }
        } else {
            seconds = 30 * 60
        }

        // WidgetKit controls the actual cadence. The host app additionally
        // requests timeline reloads when the shared snapshot changes.
        return Timeline(
            entries: [entry],
            policy: .after(Date().addingTimeInterval(seconds))
        )
    }

    private func makeEntry(for configuration: TeamGameIntent) -> TeamGameEntry {
        let teamCode = configuration.team.rawValue
        guard let snapshot = WidgetSnapshotStore.load() else {
            return TeamGameEntry(
                date: Date(),
                game: nil,
                hasSnapshot: false,
                selectedTeam: teamCode
            )
        }

        let teamGames = snapshot.games
            .filter { $0.containsTeam(teamCode) }
            .sorted { $0.startTime < $1.startTime }

        // Prefer a live game to a scheduled duplicate or stale schedule
        // entry for the same calendar day. Final games outrank pending ones.
        let todaysGame = teamGames
            .filter(\.isToday)
            .sorted { first, second in
                let firstRank = priority(first.phase)
                let secondRank = priority(second.phase)
                if firstRank != secondRank {
                    return firstRank > secondRank
                }
                return first.startTime < second.startTime
            }
            .first

        let nextGame = teamGames.first {
            $0.startTime > Date()
                && $0.phase != .final
                && $0.phase != .postponed
        }

        return TeamGameEntry(
            date: Date(),
            game: todaysGame ?? nextGame,
            hasSnapshot: true,
            selectedTeam: teamCode
        )
    }

    private func priority(_ phase: WidgetGamePhase) -> Int {
        switch phase {
        case .live, .intermission: return 4
        case .final: return 3
        case .starting: return 2
        case .scheduled: return 1
        case .postponed, .unknown: return 0
        }
    }
}

// Self-contained because the widget extension runs even when Iceometrics
// is closed. Do not show invented 50/50 chances if MoneyPuck is unavailable.
private extension WidgetGame {
    func withForecast(away: Double, home: Double) -> WidgetGame {
        WidgetGame(
            id: id, startTime: startTime, isToday: isToday,
            awayTeam: awayTeam, homeTeam: homeTeam,
            awayScore: awayScore, homeScore: homeScore,
            awayProbability: away, homeProbability: home,
            phase: phase, detail: detail,
            isFavoriteTeamGame: isFavoriteTeamGame
        )
    }
}

private enum WidgetMoneyPuckForecast {
    static func fetch(for game: WidgetGame) async -> (away: Double, home: Double)? {
        guard Int(game.id) != nil else { return nil }
        let url: URL?
        switch game.phase {
        case .scheduled, .starting:
            url = URL(string:
                "https://moneypuck.com/moneypuck/predictions/\(game.id).csv")
        case .live, .intermission:
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(secondsFromGMT: 0)!
            let components = cal.dateComponents([.year, .month], from: game.startTime)
            guard let year = components.year, let month = components.month else {
                return nil
            }
            let start = month >= 7 ? year : year - 1
            url = URL(string:
                "https://moneypuck.com/moneypuck/gameData/\(start)\(start + 1)/\(game.id).csv")
        case .final, .postponed, .unknown:
            return nil
        }
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 7
        request.setValue("text/csv,*/*", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode,
              let csv = String(data: data, encoding: .utf8),
              let firstLine = csv.split(whereSeparator: \.isNewline).first else {
            return nil
        }
        let rows = csv.split(whereSeparator: \.isNewline)
        let headers = csvLine(String(firstLine))
        let target = game.phase == .live || game.phase == .intermission
            ? rows.last : rows.dropFirst().first
        guard let target else { return nil }
        let dataCells = csvLine(String(target))
        var record: [String: String] = [:]
        for (index, header) in headers.enumerated()
            where dataCells.indices.contains(index) {
            record[header] = dataCells[index]
        }
        if game.phase == .scheduled || game.phase == .starting {
            if let id = record["gameID"], id != game.id { return nil }
            if let home = record["homeTeamCode"],
               home.uppercased() != game.homeTeam.abbreviation.uppercased() {
                return nil
            }
            if let away = record["roadTeamCode"],
               away.uppercased() != game.awayTeam.abbreviation.uppercased() {
                return nil
            }
        }
        let away: Double?
        let home: Double?
        if game.phase == .scheduled || game.phase == .starting {
            away = probability(record["preGameAwayTeamWinOverallScore"])
            home = probability(record["preGameHomeTeamWinOverallScore"])
        } else {
            away = probability(record["liveAwayTeamWinOverallScore"])
                ?? probability(record["awayWinProbability"])
            home = probability(record["liveHomeTeamWinOverallScore"])
                ?? probability(record["homeWinProbability"])
        }
        guard let away, let home, away + home > 0 else { return nil }
        return (away / (away + home), home / (away + home))
    }

    private static func probability(_ raw: String?) -> Double? {
        guard let raw,
              let n = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              n.isFinite, n >= 0, n <= 100 else { return nil }
        return n <= 1 ? n : n / 100
    }

    private static func csvLine(_ line: String) -> [String] {
        var values: [String] = []
        var value = ""
        var quoted = false
        var cursor = line.startIndex
        while cursor < line.endIndex {
            let char = line[cursor]
            if char == "\"" {
                let next = line.index(after: cursor)
                if quoted, next < line.endIndex, line[next] == "\"" {
                    value.append("\"")
                    cursor = line.index(after: next)
                    continue
                }
                quoted.toggle()
            } else if char == "," && !quoted {
                values.append(value)
                value = ""
            } else {
                value.append(char)
            }
            cursor = line.index(after: cursor)
        }
        values.append(value)
        return values
    }
}

struct TeamGameWidgetView: View {
    let entry: TeamGameEntry
    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        Group {
            if widgetFamily == .systemMedium {
                TeamGameMediumView(entry: entry)
            } else if let game = entry.game {
                gameCard(game)
            } else {
                emptyState
            }
        }
        .widgetURL(
            IceometricsWidgetLinks.scoreboard
        )
        .containerBackground(
            Color.clear,
            for: .widget
        )
    }

    private func gameCard(
        _ game: WidgetGame
    ) -> some View {
        ZStack {
            splitBackground(game)

            VStack(spacing: 0) {
                HStack {
                    teamLogo(
                        game.awayTeam
                    )

                    Spacer()

                    teamLogo(
                        game.homeTeam
                    )
                }
                .padding(.top, 8)
                .padding(.horizontal, 12)

                Spacer(minLength: 0)

                if game.phase == .live
                    || game.phase == .intermission
                    || game.phase == .final {
                    if let away = game.awayScore,
                       let home = game.homeScore {
                        Text("\(away) – \(home)")
                            .font(
                                .system(
                                    size: 34,
                                    weight: .black,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(.white)
                            .monospacedDigit()
                    } else {
                        Text(game.phase == .final ? "FINAL" : "LIVE")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                } else if game.phase == .starting {
                    Text("STARTING")
                        .font(.system(size: 21, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                } else {
                    Text("VS")
                        .font(
                            .system(
                                size: 31,
                                weight: .black,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(.white)
                }

                // Live: period/clock. Scheduled: puck-drop time.
                // Scheduled games need a real calendar date, not just the
                // time of puck drop. Date.formatted uses the device locale.
                if game.phase == .scheduled {
                    Text(
                        game.startTime.formatted(
                            .dateTime
                                .weekday(.abbreviated)
                                .month(.abbreviated)
                                .day()
                        )
                    )
                    .font(
                        .system(size: 10, weight: .bold, design: .rounded)
                    )
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 3)
                }

                Text(game.detail)
                    .font(
                        .system(
                            size: 11,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.top, 4)

                Spacer(minLength: 0)

                HStack {
                    probabilityText(
                        game.awayProbability
                    )

                    Spacer()

                    probabilityText(
                        game.homeProbability
                    )
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
    }

    private func splitBackground(
        _ game: WidgetGame
    ) -> some View {
        GeometryReader { proxy in
            let awayShare = max(
                0,
                min(
                    1,
                    game.awayProbability ?? 0.5
                )
            )

            let split =
                proxy.size.width * awayShare

            ZStack {
                HStack(spacing: 0) {
                    Color(
                        widgetHex:
                            game.awayTeam.accentHex
                    )
                    .frame(width: split)

                    Color(
                        widgetHex:
                            game.homeTeam.accentHex
                    )
                    .frame(maxWidth: .infinity)
                }
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height
                )

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                .white.opacity(0.08),
                                .black.opacity(0.18),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: 26,
                        height: proxy.size.height
                    )
                    .position(
                        x: split,
                        y: proxy.size.height / 2
                    )

                LinearGradient(
                    colors: [
                        .white.opacity(0.07),
                        .clear,
                        .black.opacity(0.16)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private func teamLogo(
        _ team: WidgetTeam
    ) -> some View {
        // Same cached-image/fallback rendering as Today's Games.
        WidgetTeamLogoView(team: team, size: 38)
    }

    private func probabilityText(
        _ value: Double?
    ) -> some View {
        Text(percent(value))
            .font(
                .system(
                    size: 18,
                    weight: .black,
                    design: .rounded
                )
            )
            .foregroundStyle(.white)
            .monospacedDigit()
    }

    private func percent(
        _ value: Double?
    ) -> String {
        guard let value else {
            return "—"
        }

        return "\(Int((value * 100).rounded()))%"
    }

    private var emptyState: some View {
        ZStack {
            Color(
                red: 0.07,
                green: 0.08,
                blue: 0.10
            )

            VStack(spacing: 6) {
                Image(systemName: "hockey.puck.fill")
                    .font(.title2)

                Text(
                    entry.hasSnapshot
                    ? "NO \(entry.selectedTeam) GAME"
                    : "OPEN ICEOMETRICS"
                )
                .font(.caption.bold())
            }
            .foregroundStyle(.white)
        }
    }
}

// ICEOMETRICS_TEAM_GAME_MEDIUM_V1
// Reuses the same AppIntent team choice and timeline entry as the small widget.
// WidgetTeamLogoView reads the existing downsampled App Group logo cache.
private struct TeamGameMediumView: View {
    let entry: TeamGameEntry

    var body: some View {
        Group {
            if let game = entry.game {
                matchup(game)
            } else {
                ZStack {
                    Color(red: 0.07, green: 0.08, blue: 0.10)
                    VStack(spacing: 8) {
                        Image(systemName: "hockey.puck.fill")
                            .font(.title2)
                        Text(entry.hasSnapshot
                            ? "NO \(entry.selectedTeam) GAME"
                            : "OPEN ICEOMETRICS")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }

    private func matchup(_ game: WidgetGame) -> some View {
        GeometryReader { geometry in
            let awayShare = max(0.12, min(0.88, game.awayProbability ?? 0.5))

            ZStack {
                HStack(spacing: 0) {
                    Color(widgetHex: game.awayTeam.accentHex)
                        .frame(width: geometry.size.width * awayShare)
                    Color(widgetHex: game.homeTeam.accentHex)
                        .frame(maxWidth: .infinity)
                }

                LinearGradient(
                    colors: [.white.opacity(0.10), .clear, .black.opacity(0.20)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(spacing: 0) {
                    HStack {
                        Text("TEAM GAME")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                        Spacer(minLength: 4)
                        Text(status(game))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .opacity(0.90)
                    .padding(.horizontal, 14)
                    .padding(.top, 9)

                    Spacer(minLength: 1)

                    HStack(alignment: .center, spacing: 3) {
                        teamColumn(game.awayTeam, probability: game.awayProbability)
                            .frame(maxWidth: .infinity)

                        VStack(spacing: 3) {
                            if game.phase == .live
                                || game.phase == .intermission
                                || game.phase == .final {
                                Text("\(game.awayScore ?? 0)–\(game.homeScore ?? 0)")
                                    .font(.system(size: 27, weight: .black, design: .rounded))
                                    .monospacedDigit()
                            } else {
                                Text("VS")
                                    .font(.system(size: 28, weight: .black, design: .rounded))
                            }

                            Text(game.detail)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .opacity(0.95)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)

                            if game.phase == .scheduled || game.phase == .starting {
                                Text(game.startTime.formatted(
                                    .dateTime.weekday(.abbreviated).month(.abbreviated).day()
                                ))
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .opacity(0.85)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            }
                        }
                        .frame(width: 106)

                        teamColumn(game.homeTeam, probability: game.homeProbability)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 9)

                    Spacer(minLength: 1)
                }
                .padding(.bottom, 10)
                .foregroundStyle(.white)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func teamColumn(
        _ team: WidgetTeam,
        probability: Double?
    ) -> some View {
        VStack(spacing: 2) {
            WidgetTeamLogoView(team: team, size: 46)
            Text(team.abbreviation)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .lineLimit(1)
            Text(probability.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                .font(.system(size: 19, weight: .black, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func status(_ game: WidgetGame) -> String {
        switch game.phase {
        case .live: return "LIVE"
        case .intermission: return "INTERMISSION"
        case .final: return "FINAL"
        case .scheduled: return "UP NEXT"
        case .starting: return "STARTING"
        case .postponed: return "POSTPONED"
        case .unknown: return "GAME"
        }
    }
}

struct TeamGameWidget: Widget {
    // New kind ensures iOS registers the editable configuration rather than
    // reusing a previously installed StaticConfiguration timeline.
    let kind = "IceometricsTeamGameEditableV1"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: TeamGameIntent.self,
            provider: TeamGameProvider()
        ) { entry in
            TeamGameWidgetView(entry: entry)
        }
        .configurationDisplayName("Team Game")
        .description("Live score or next matchup for your selected NHL team.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
