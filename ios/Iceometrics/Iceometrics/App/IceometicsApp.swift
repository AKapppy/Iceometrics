import SwiftUI
import WidgetKit

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
                .environment(
                    \.iceometricsFavoritePaletteTeamCode,
                    settings.favoritePaletteTeamCode(
                        for: homeViewModel.accentTeams
                    )
                )
                .environment(\.iceometricsAccentForegroundColor,
                    settings.accentForegroundColor(for: homeViewModel.accentTeams)
                )
                .tint(
                    settings.accentColor(
                        for: homeViewModel.accentTeams
                    )
                )
                .preferredColorScheme(
                    settings.preferredColorScheme
                )
                .background(MacWindowInitialSizeView())
                .task {
                    // Make sure the schedule has actually loaded before the
                    // first widget snapshot is written.
                    await homeViewModel.loadIfNeeded()

                    WidgetSnapshotCoordinator.shared.schedule(
                        games: homeViewModel.games,
                        favoriteTeamID: settings.favoriteTeamID
                    )
                }
                .onChange(
                    of: homeViewModel.snapshot?.generatedAt
                ) { _, _ in
                    // snapshot is @Published and changes after the repository
                    // has rebuilt HomeViewModel's full season game index.
                    WidgetSnapshotCoordinator.shared.schedule(
                        games: homeViewModel.games,
                        favoriteTeamID: settings.favoriteTeamID
                    )
                }
                .onChange(
                    of: homeViewModel.liveUpdatedAt
                ) { _, _ in
                    // Push live score/state overlays into the widget snapshot.
                    WidgetSnapshotCoordinator.shared.schedule(
                        games: homeViewModel.games,
                        favoriteTeamID: settings.favoriteTeamID
                    )
                }
                .onChange(
                    of: settings.favoriteTeamID
                ) { _, favoriteTeamID in
                    WidgetSnapshotCoordinator.shared.schedule(
                        games: homeViewModel.games,
                        favoriteTeamID: favoriteTeamID
                    )
                }
        }
    }
}

// MARK: - Widget snapshot bridge

private nonisolated struct AppWidgetSnapshot: Codable, Sendable {
    let generatedAt: Date
    let favoriteTeamID: String?
    let games: [AppWidgetGame]
    let pie: AppWidgetPie?
}

private nonisolated struct AppWidgetGame: Codable, Sendable {
    let id: String

    let startTime: Date
    let isToday: Bool

    let awayTeam: AppWidgetTeam
    let homeTeam: AppWidgetTeam

    let awayScore: Int?
    let homeScore: Int?

    let awayProbability: Double?
    let homeProbability: Double?

    let phase: String
    let detail: String

    let isFavoriteTeamGame: Bool
}

private nonisolated struct AppWidgetTeam: Codable, Sendable {
    let id: String
    let abbreviation: String
    let name: String
    let accentHex: String
    let logoURL: URL?
}

private nonisolated struct AppWidgetPie: Codable, Sendable {
    let dataDate: Date
    let label: String
    let rings: [AppWidgetPieRing]
}

private nonisolated struct AppWidgetPieRing: Codable, Sendable {
    let key: String
    let label: String
    let slices: [AppWidgetPieSlice]
}

private nonisolated struct AppWidgetPieSlice: Codable, Sendable {
    let teamCode: String
    let teamName: String
    let colorHex: String
    let value: Double
}

@MainActor
final class WidgetSnapshotCoordinator {
    static let shared = WidgetSnapshotCoordinator()

    private let predictionService = MoneyPuckPredictionService()
    private let seasonPredictionService = PredictionDataService()

    private var pendingTask: Task<Void, Never>?
    private var cachedGamePredictions: [String: MoneyPuckGamePrediction] = [:]
    private var lastPredictionFetch: [String: Date] = [:]

    private init() {}

    func schedule(
        games: [HockeyGame]
    ) {
        let favoriteTeamID = UserDefaults.standard.string(
            forKey: "settings.favoriteTeamID"
        )

        schedule(
            games: games,
            favoriteTeamID: favoriteTeamID
        )
    }

    func schedule(
        games: [HockeyGame],
        favoriteTeamID: String?
    ) {
        pendingTask?.cancel()

        pendingTask = Task { [weak self] in
            try? await Task.sleep(
                for: .milliseconds(600)
            )

            guard !Task.isCancelled else {
                return
            }

            await self?.refresh(
                games: games,
                favoriteTeamID: favoriteTeamID
            )
        }
    }

    private func refresh(
        games: [HockeyGame],
        favoriteTeamID: String?
    ) async {
        let nhlGames = games
            .filter { $0.leagueCode == "NHL" }
            .sorted { $0.startTime < $1.startTime }

        async let predictionSnapshotTask =
            fetchPredictionSnapshot()

        // The Team Game widget may show a club's NEXT matchup rather
        // than today's slate. Include the nearest upcoming matchup for
        // each NHL club, but not the entire season's predictions.
        let todaysGames = nhlGames.filter {
            Self.isToday($0.startTime)
        }
        let futureGames = nhlGames.filter {
            $0.status == .scheduled && $0.startTime > Date()
        }
        var coveredTeams = Set<String>()
        var nextTeamGames: [HockeyGame] = []
        for game in futureGames {
            let away = game.awayTeam.abbreviation.uppercased()
            let home = game.homeTeam.abbreviation.uppercased()
            if !coveredTeams.contains(away) || !coveredTeams.contains(home) {
                nextTeamGames.append(game)
            }
            coveredTeams.insert(away)
            coveredTeams.insert(home)
            if coveredTeams.count >= 32 { break }
        }
        var selectedIDs = Set<String>()
        let predictionGames = (todaysGames + nextTeamGames).filter {
            selectedIDs.insert($0.id).inserted
        }

        let gamePredictions = await fetchGamePredictions(
            games: predictionGames
        )

        let predictionSnapshot =
            await predictionSnapshotTask

        let widgetGames = nhlGames.map { game in
            makeWidgetGame(
                game,
                prediction: gamePredictions[game.id],
                favoriteTeamID: favoriteTeamID
            )
        }

        // ICEOMETRICS_PIE_PERSISTED_FALLBACK_V1
        // If a transient network/export failure returns no usable wheel,
        // preserve the last working pie already stored for WidgetKit.
        let pie = predictionSnapshot.flatMap(makePieSnapshot) ?? cachedPie()

        let snapshot = AppWidgetSnapshot(
            generatedAt: Date(),
            favoriteTeamID: favoriteTeamID,
            games: widgetGames,
            pie: pie
        )

        write(snapshot)

        // Populate the shared logo cache in the background.
        // Missing logos are downloaded once and then reused by WidgetKit.
        let logoGames = nhlGames
        Task.detached(priority: .utility) {
            await WidgetLogoCache.populate(
                games: logoGames
            )
        }
    }

    private func cachedPie() -> AppWidgetPie? {
        guard let root = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.akappy.Iceometrics"
        ), let data = try? Data(contentsOf: root.appendingPathComponent("widget-snapshot.json")) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let cached = (try? decoder.decode(AppWidgetSnapshot.self, from: data))?.pie else {
            return nil
        }
        // Recompute the label. A wheel saved yesterday as TODAY is no
        // longer today's data when the app opens the following morning.
        return AppWidgetPie(
            dataDate: cached.dataDate,
            label: Self.pieDateLabel(for: cached.dataDate),
            rings: cached.rings
        )
    }

    private static func pieDateLabel(for dataDate: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let sourceDay = calendar.startOfDay(for: dataDate)
        let today = calendar.startOfDay(for: Date())
        let daysOld = calendar.dateComponents([.day], from: sourceDay, to: today).day ?? 0
        if daysOld <= 0 { return "TODAY" }
        if daysOld == 1 { return "YESTERDAY" }
        return dataDate.formatted(.dateTime.month(.abbreviated).day())
    }

    private func fetchPredictionSnapshot()
        async -> PredictionSnapshot? {
        do {
            return try await seasonPredictionService
                .fetchSnapshot(
                    forceRefresh: false
                )
        } catch {
            return await seasonPredictionService
                .cachedSnapshot()
        }
    }

    private func fetchGamePredictions(
        games: [HockeyGame]
    ) async -> [String: MoneyPuckGamePrediction] {
        let candidates = games.filter {
            $0.status == .scheduled || $0.status == .live
        }
        let now = Date()
        var result: [String: MoneyPuckGamePrediction] = [:]
        let due = candidates.filter { game in
            let cacheAge = lastPredictionFetch[game.id].map {
                now.timeIntervalSince($0)
            } ?? Double.infinity
            let refreshWindow: TimeInterval =
                game.status == .live ? 60 : 30 * 60
            if cacheAge < refreshWindow,
               let cached = cachedGamePredictions[game.id] {
                result[game.id] = cached
                return false
            }
            return true
        }
        let grouped = Dictionary(grouping: due) {
            Self.dayKey($0.startTime)
        }
        for (_, dayGames) in grouped {
            guard let date = dayGames.first?.startTime else { continue }
            do {
                let values = try await predictionService.fetchPredictions(
                    for: date, games: dayGames
                )
                for (id, prediction) in values {
                    cachedGamePredictions[id] = prediction
                    lastPredictionFetch[id] = now
                }
                result.merge(values) { _, newer in newer }
            } catch {
                // Keep a previous legitimate MoneyPuck result if available.
                for game in dayGames {
                    if let cached = cachedGamePredictions[game.id] {
                        result[game.id] = cached
                    }
                }
            }
        }
        return result
    }

    private func makeWidgetGame(
        _ game: HockeyGame,
        prediction: MoneyPuckGamePrediction?,
        favoriteTeamID: String?
    ) -> AppWidgetGame {
        let probabilities =
            resolvedProbabilities(
                game: game,
                prediction: prediction
            )

        return AppWidgetGame(
            id: game.id,
            startTime: game.startTime,
            isToday: Self.isToday(game.startTime),
            awayTeam: makeWidgetTeam(game.awayTeam),
            homeTeam: makeWidgetTeam(game.homeTeam),
            awayScore: game.awayScore,
            homeScore: game.homeScore,
            awayProbability: probabilities.away,
            homeProbability: probabilities.home,
            phase: phase(for: game),
            detail: detail(for: game),
            isFavoriteTeamGame:
                game.awayTeam.id == favoriteTeamID
                || game.homeTeam.id == favoriteTeamID
        )
    }

    private func makeWidgetTeam(
        _ team: Team
    ) -> AppWidgetTeam {
        AppWidgetTeam(
            id: team.id,
            abbreviation:
                team.abbreviation.uppercased(),
            name: team.name,
            accentHex:
                WidgetAccentPalette.hex(
                    for: team.abbreviation
                ),
            logoURL: team.logoURL
        )
    }

    private func resolvedProbabilities(
        game: HockeyGame,
        prediction: MoneyPuckGamePrediction?
    ) -> (
        away: Double?,
        home: Double?
    ) {
        if game.status == .final,
           let away = game.awayScore,
           let home = game.homeScore,
           away != home {
            return away > home
                ? (1, 0)
                : (0, 1)
        }

        if let prediction {
            return (
                prediction.awayWinProbability,
                prediction.homeWinProbability
            )
        }

        return (nil, nil)
    }

    private func phase(
        for game: HockeyGame
    ) -> String {
        if game.status == .final {
            return "final"
        }

        if game.status == .live {
            if game.isIntermission == true {
                return "intermission"
            }

            return "live"
        }

        if game.status == .scheduled {
            if Self.isToday(game.startTime),
               game.startTime <= Date() {
                return "starting"
            }

            return "scheduled"
        }

        if game.status == .postponed {
            return "postponed"
        }

        return "unknown"
    }

    private func detail(
        for game: HockeyGame
    ) -> String {
        if game.status == .final {
            return "FINAL"
        }

        if game.status == .postponed {
            return "PPD"
        }

        if game.status == .live {
            if game.isIntermission == true {
                if let period = game.periodNumber {
                    return "INT · \(ordinal(period))"
                }

                return "INTERMISSION"
            }

            let period =
                game.periodNumber.map(ordinal)
                ?? "LIVE"

            if let time = game.timeRemaining,
               !time.isEmpty {
                return "\(period) · \(time)"
            }

            return period
        }

        if game.startTime <= Date() {
            return "STARTING"
        }

        return game.startTime.formatted(
            date: .omitted,
            time: .shortened
        )
    }

    private func ordinal(
        _ period: Int
    ) -> String {
        switch period {
        case 1:
            return "1st"
        case 2:
            return "2nd"
        case 3:
            return "3rd"
        default:
            return "\(period)th"
        }
    }

    private func makePieSnapshot(
        _ snapshot: PredictionSnapshot
    ) -> AppWidgetPie? {
        let metricOrder = [
            "madeplayoffs",
            "round2",
            "round3",
            "round4",
            "woncup",
        ]

        guard let referenceTable =
            snapshot.tables["madeplayoffs"]
                ?? snapshot.tables.values.first,
              !referenceTable.columns.isEmpty
        else {
            return nil
        }

        // ICEOMETRICS_PIE_LAST_VALID_DATE_V1
        // An exported date may exist before MoneyPuck has populated it.
        // Fall back to the newest fully populated outer ring with actual
        // data in the other published rounds. Do not fabricate today's odds.
        guard let columnIndex = referenceTable.columns.indices.reversed().first(where: { index in
            guard let dataDate = Self.dateForPredictionColumn(
                referenceTable.columns[index],
                season: snapshot.season
            ), Self.startOfEasternDay(dataDate) <= Self.startOfEasternDay(Date()) else {
                return false
            }

            let availableCount = referenceTable.rows.values.reduce(into: 0) { count, values in
                if values.indices.contains(index), values[index] != nil {
                    count += 1
                }
            }
            // NHL simulations normally contain 32 teams; a nearly empty
            // current-day file must not replace yesterday's complete wheel.
            guard availableCount >= min(24, max(1, referenceTable.rows.count)) else {
                return false
            }

            return metricOrder.allSatisfy { key in
                guard let table = snapshot.tables[key],
                      table.columns.indices.contains(index),
                      table.columns[index] == referenceTable.columns[index] else {
                    return false
                }
                return table.rows.values.contains { values in
                    values.indices.contains(index) && (values[index] ?? 0) > 0
                }
            }
        }) else {
            return nil
        }

        let rawColumn =
            referenceTable.columns[columnIndex]

        guard let dataDate = Self.dateForPredictionColumn(
            rawColumn,
            season: snapshot.season
        ) else {
            return nil
        }

        let teamLookup = Dictionary(
            uniqueKeysWithValues:
                snapshot.teams.map {
                    ($0.code.uppercased(), $0)
                }
        )

        // Same explicit team ordering used by PredictionPieChartView.
        let teamOrder = [
            "NYR", "CAR", "CBJ", "NJD", "NYI", "PHI", "PIT", "WSH",
            "BOS", "BUF", "DET", "FLA", "MTL", "OTT", "TBL", "TOR",
            "ANA", "CGY", "EDM", "LAK", "SEA", "SJS", "VAN", "VGK",
            "CHI", "COL", "DAL", "MIN", "NSH", "STL", "WPG", "UTA",
        ]

        let orderedTeams: [PredictionTeam] = {
            let ordered = teamOrder.compactMap {
                teamLookup[$0]
            }

            let used = Set(
                ordered.map {
                    $0.code.uppercased()
                }
            )

            return ordered
                + snapshot.teams
                    .filter {
                        !used.contains(
                            $0.code.uppercased()
                        )
                    }
                    .sorted {
                        $0.name < $1.name
                    }
        }()

        let rings: [AppWidgetPieRing] =
            metricOrder.compactMap { key in
                guard let table =
                    snapshot.tables[key],
                      table.columns.indices
                        .contains(columnIndex)
                else {
                    return nil
                }

                let values:
                    [(PredictionTeam, Double)] =
                    orderedTeams.compactMap {
                        team in

                        guard let row =
                            table.rows[team.code],
                              row.indices.contains(
                                columnIndex
                              ),
                              let value =
                                row[columnIndex],
                              value > 0
                        else {
                            return nil
                        }

                        return (team, value)
                    }

                let total = values.reduce(0) {
                    $0 + $1.1
                }

                guard total > 0 else {
                    return nil
                }

                let slices = values
                    .map { team, value in
                        AppWidgetPieSlice(
                            teamCode:
                                team.code,
                            teamName:
                                team.name,
                            colorHex:
                                team.colorHex
                                    .isEmpty
                                ? WidgetAccentPalette
                                    .hex(
                                        for:
                                            team.code
                                    )
                                : team.colorHex,
                            value:
                                value / total
                        )
                    }

                let label =
                    snapshot.metrics
                        .first {
                            $0.key == key
                        }?
                        .label
                    ?? key

                return AppWidgetPieRing(
                    key: key,
                    label: label,
                    slices: slices
                )
            }

        guard !rings.isEmpty else {
            return nil
        }

        let label = Self.pieDateLabel(for: dataDate)

        return AppWidgetPie(
            dataDate: dataDate,
            label: label,
            rings: rings
        )
    }

    private func write(
        _ snapshot: AppWidgetSnapshot
    ) {
        guard let containerURL =
            FileManager.default
                .containerURL(
                    forSecurityApplicationGroupIdentifier:
                        "group.com.akappy.Iceometrics"
                )
        else {
            print(
                "Widget snapshot: App Group container unavailable"
            )
            return
        }

        let destination =
            containerURL.appendingPathComponent(
                "widget-snapshot.json"
            )

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [
                .sortedKeys
            ]

            let data = try encoder.encode(
                snapshot
            )

            try data.write(
                to: destination,
                options: .atomic
            )

            WidgetCenter.shared.reloadAllTimelines()

            print(
                "Widget snapshot wrote "
                + "\(snapshot.games.count) games"
            )

            print(
                "Widget snapshot favoriteTeamID: "
                + String(describing: snapshot.favoriteTeamID)
            )

        } catch {
            print(
                "Widget snapshot write failed: "
                + error.localizedDescription
            )
        }
    }

    private static func dayKey(
        _ date: Date
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(
            identifier: .gregorian
        )
        formatter.locale = Locale(
            identifier: "en_US_POSIX"
        )
        formatter.timeZone =
            TimeZone(
                identifier:
                    "America/New_York"
            )
        formatter.dateFormat = "yyyy-MM-dd"

        return formatter.string(
            from: date
        )
    }

    private static func isToday(
        _ date: Date
    ) -> Bool {
        startOfEasternDay(date)
            == startOfEasternDay(Date())
    }

    private static func startOfEasternDay(
        _ date: Date
    ) -> Date {
        var calendar = Calendar(
            identifier: .gregorian
        )

        calendar.timeZone =
            TimeZone(
                identifier:
                    "America/New_York"
            )
            ?? .current

        return calendar.startOfDay(
            for: date
        )
    }

    private static func dateForPredictionColumn(
        _ raw: String,
        season: String
    ) -> Date? {
        let parts =
            raw.split(separator: "/")

        guard parts.count == 2,
              let month = Int(parts[0]),
              let day = Int(parts[1]),
              let startYear =
                Int(season.prefix(4))
        else {
            return nil
        }

        let year =
            month >= 7
            ? startYear
            : startYear + 1

        var calendar = Calendar(
            identifier: .gregorian
        )

        calendar.timeZone =
            TimeZone(
                identifier:
                    "America/New_York"
            )
            ?? .current

        return calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day
            )
        )
    }
}

private enum WidgetAccentPalette {
    static func hex(
        for abbreviation: String
    ) -> String {
        let code =
            abbreviation.uppercased()

        return values[code]
            ?? "#61758A"
    }

    private static let values:
        [String: String] = [
            "ANA": "#E8732A",
            "BOS": "#D7A72E",
            "BUF": "#2864A5",
            "CGY": "#E34C32",
            "CAR": "#9F2940",
            "CHI": "#B84742",
            "COL": "#75435C",
            "CBJ": "#31527A",
            "DAL": "#238463",
            "DET": "#D43C4A",
            "EDM": "#DD6B2B",
            "FLA": "#3B618C",
            "LAK": "#87939D",
            "MIN": "#39705A",
            "MTL": "#B53552",
            "NSH": "#D9AD35",
            "NJD": "#D83643",
            "NYI": "#E97934",
            "NYR": "#2467BD",
            "OTT": "#C99838",
            "PHI": "#E85A24",
            "PIT": "#CBA536",
            "SJS": "#2E8790",
            "SEA": "#58A5B5",
            "STL": "#396FB7",
            "TBL": "#6C89B7",
            "TOR": "#4276B8",
            "UTA": "#68A9D2",
            "VAN": "#387E92",
            "VGK": "#AD9255",
            "WSH": "#5E79A7",
            "WPG": "#9B4053",
        ]
}


// MARK: - Shared widget logo cache

private nonisolated enum WidgetLogoCache {
    private static let appGroup =
        "group.com.akappy.Iceometrics"

    static func populate(
        games: [HockeyGame]
    ) async {
        guard let root =
            FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier:
                    appGroup
            )
        else {
            return
        }

        let directory =
            root.appendingPathComponent(
                "WidgetTeamLogos",
                isDirectory: true
            )

        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        var teamsByCode: [String: Team] = [:]

        for game in games {
            teamsByCode[
                game.awayTeam.abbreviation.uppercased()
            ] = game.awayTeam

            teamsByCode[
                game.homeTeam.abbreviation.uppercased()
            ] = game.homeTeam
        }

        await withTaskGroup(
            of: Void.self
        ) { group in
            for (code, team) in teamsByCode {
                guard let url = team.logoURL else {
                    continue
                }

                let destination =
                    directory.appendingPathComponent(
                        code + ".img"
                    )

                // Already cached successfully.
                if let attributes =
                    try? FileManager.default.attributesOfItem(
                        atPath: destination.path
                    ),
                   let size =
                    attributes[.size] as? NSNumber,
                   size.intValue > 100 {
                    continue
                }

                group.addTask {
                    do {
                        var request =
                            URLRequest(
                                url: url,
                                cachePolicy:
                                    .returnCacheDataElseLoad,
                                timeoutInterval: 15
                            )

                        request.setValue(
                            "image/*",
                            forHTTPHeaderField:
                                "Accept"
                        )

                        let (data, response) =
                            try await URLSession.shared.data(
                                for: request
                            )

                        guard let http =
                            response
                                as? HTTPURLResponse,
                              200..<300
                                ~= http.statusCode,
                              data.count > 100
                        else {
                            return
                        }

                        try data.write(
                            to: destination,
                            options: .atomic
                        )
                    } catch {
                        return
                    }
                }
            }
        }

        WidgetCenter.shared.reloadAllTimelines()
    }
}
