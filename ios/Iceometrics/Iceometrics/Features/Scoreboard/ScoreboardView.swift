import SwiftUI

private struct ScoreboardCompetitionSection:
    Identifiable
{
    let id: String
    let title: String
    let games: [HockeyGame]

    var gameCountText: String {
        "\(games.count) \(games.count == 1 ? "game": "games")"
    }
}

struct ScoreboardView: View {
    @ObservedObject var viewModel: HomeViewModel
    @EnvironmentObject private var settings: AppSettingsStore

    @State private var selectedDate = Date()
    @State private var showingCalendar = false
    @State private var selectedInitialDate = false
    @State private var moneyPuckPredictions: [String: MoneyPuckGamePrediction] = [:]
    @State private var selectedGame: HockeyGame?
    @State private var smartFillViewportHeight: CGFloat = 700
    @AppStorage("iceometrics.scoreboard.smartFill.alpha") private var smartFillEnabled = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let calendar = Calendar.autoupdatingCurrent
    private let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 520), spacing: 16)
    ]

    private var gamesForSelectedDate: [HockeyGame] {
        viewModel.games(
            on: selectedDate,
            calendar: calendar
        )
        .filter {
            settings.isCompetitionVisible(
                ScoreboardCompetitionCatalog.id(
                    for: $0
                )
            )
        }
    }

    private var nhlGamesForSelectedDate: [HockeyGame] {
        gamesForSelectedDate.filter {
            ScoreboardCompetitionCatalog.id(
                for: $0
            ) == "NHL"
        }
    }

    private var competitionSections:
        [ScoreboardCompetitionSection]
    {
        let grouped = Dictionary(
            grouping: gamesForSelectedDate
        ) {
            ScoreboardCompetitionCatalog.id(
                for: $0
            )
        }

        return grouped.map { competitionID, games in
            ScoreboardCompetitionSection(
                id: competitionID,
                title:
                    ScoreboardCompetitionCatalog
                    .displayName(
                        for: competitionID
                    ),
                games: sortGamesWithinCompetition(
                    games
                )
            )
        }
        .sorted { lhs, rhs in
            competitionRank(lhs.id)
                < competitionRank(rhs.id)
        }
    }

    private var favoriteCompetitionID: String? {
        guard let favoriteTeamID =
                settings.favoriteTeamID else {
            return nil
        }

        // Only the selected day's games can affect section ordering here.
        // Avoid materializing the full-season merged game array on every
        // scoreboard body update (especially during live polling).
        for game in gamesForSelectedDate where isFavoriteGame(
            game, favoriteTeamID: favoriteTeamID
        ) {
            return ScoreboardCompetitionCatalog.id(for: game)
        }

        return nil
    }

    private var availableRange: ClosedRange<Date> {
        guard let first = viewModel.availableGameDates.first,
              let last = viewModel.availableGameDates.last else {
            let day = calendar.startOfDay(for: selectedDate)
            return day...day
        }

        return first...last
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    dateHeader

                    HStack {
                        Spacer(minLength: 0)
                        Picker("Layout", selection: $smartFillEnabled) {
                            Text("Standard").tag(false)
                            Text("Smart Fill").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 280)
                        .accessibilityLabel("Scoreboard layout")
                        Spacer(minLength: 0)
                    }

                    if gamesForSelectedDate.isEmpty {
                        emptyState
                    } else if smartFillEnabled {
                        smartFillContent
                    } else {
                        ForEach(
                            competitionSections
                        ) { section in
                            VStack(
                                alignment: .leading,
                                spacing: 10
                            ) {
                                HStack(
                                    alignment:
                                        .firstTextBaseline
                                ) {
                                    Text(section.title)
                                        .font(.headline)

                                    Spacer()

                                    Text(
                                        section.gameCountText
                                    )
                                    .font(.subheadline)
                                    .foregroundStyle(
                                        .secondary
                                    )
                                }

                                LazyVGrid(
                                    columns: columns,
                                    spacing: 16
                                ) {
                                    ForEach(
                                        section.games
                                    ) { game in
                                        Button {
                                            selectedGame =
                                                game
                                        } label: {
                                            ScoreboardCardView(
                                                game: game,
                                                prediction:
                                                    displayedPrediction(
                                                        for: game
                                                    )
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityHint(
                                            "Open game details"
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                .id("\(calendar.startOfDay(for: selectedDate).timeIntervalSince1970)-\(smartFillEnabled)")
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.height
            } action: { viewport in
                if abs(viewport - smartFillViewportHeight) > 1 {
                    smartFillViewportHeight = viewport
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )

            scoreboardFooter
        }
        .scoreboardDateSwipe { amount in
            if canMoveDay(by: amount) {
                moveDay(by: amount)
            }
        }
        .navigationTitle("Scoreboard")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task(priority: .userInitiated) {
                        await viewModel.refresh()
                        await loadMoneyPuckPredictions()
                    }
                } label: {
                    Label(
                        "Refresh",
                        systemImage: "arrow.clockwise"
                    )
                }
                .disabled(viewModel.loadState == .loading)
            }
        }
        .task(priority: .userInitiated) {
            await viewModel.loadIfNeeded()
            selectInitialDateIfNeeded()
            // selectedDatePredictionKey owns prediction loading. Keeping it in
            // one task avoids two identical MoneyPuck requests on first paint.
        }
        .task(id: pollingDateKey) {
            await runAdaptiveLivePolling()
        }
        .task(id: selectedDatePredictionKey) {
            await loadMoneyPuckPredictions()
        }
        .task(id: livePredictionRefreshKey) {
            guard nhlGamesForSelectedDate.contains(
                where: { $0.status == .live }
            ) else {
                return
            }

            while !Task.isCancelled {
                await loadMoneyPuckPredictions()

                do {
                    try await Task.sleep(
                        for: .seconds(20)
                    )
                } catch {
                    return
                }
            }
        }
        .onChange(of: viewModel.snapshot?.generatedAt) { _, _ in
            selectInitialDateIfNeeded()
        }
        .onChange(
            of: settings.showPregamePredictions
        ) { _, enabled in
            if enabled {
                Task(priority: .utility) {
                    await loadMoneyPuckPredictions()
                }
            } else {
                moneyPuckPredictions = [:]
            }
        }
        .refreshable {
            await viewModel.refresh()
            await loadMoneyPuckPredictions()
        }
        .popover(isPresented: $showingCalendar) {
            ScoreboardCalendarPicker(
                selectedDate: $selectedDate,
                availableRange: availableRange
            )
        }
        #if os(macOS)
        .popover(item: $selectedGame, arrowEdge: .trailing) { game in
            NavigationStack {
                GameDetailView(
                    game: game,
                    prediction: displayedPrediction(for: game),
                    allGames: viewModel.games
                )
            }
            .frame(width: 760, height: 660)
        }
        #else
        .sheet(item: $selectedGame) { game in
            NavigationStack {
                GameDetailView(
                    game: game,
                    prediction: displayedPrediction(for: game),
                    allGames: viewModel.games
                )
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        #endif
    }



    private var smartFillContent: some View {
        ForEach(competitionSections) { section in
            IceometricsDocSmartSection(
                section: section,
                viewportHeight: smartFillViewportHeight,
                sectionGameCounts: competitionSections.map { $0.games.count },
                sectionFavoriteFlags: competitionSections.map { section in
                    section.games.contains { game in
                        game.awayTeam.id == settings.favoriteTeamID
                            || game.homeTeam.id == settings.favoriteTeamID
                    }
                },
                favoriteTeamID: settings.favoriteTeamID,
                allGames: viewModel.games,
                onSelect: { game in selectedGame = game },
                predictionForGame: { game in displayedPrediction(for: game) }
            )
        }
    }

    private var scoreboardFooter: some View {
        HStack(spacing: 8) {
            DataStatusView(
                state: viewModel.loadState,
                origin: viewModel.origin
            )

            Text("•")
                .foregroundStyle(.tertiary)

            Text(viewModel.lastUpdatedText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var dateHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Button {
                    moveDay(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(!canMoveDay(by: -1))
                .accessibilityLabel("Previous day")

                Button {
                    showingCalendar = true
                } label: {
                    VStack(spacing: 3) {
                        ViewThatFits(in: .horizontal) {
                            dateHeaderText(
                                format: "EEEE d MMMM yyyy",
                                fixedWidth: true
                            )
                            dateHeaderText(
                                format: "EEE d MMMM yyyy",
                                fixedWidth: true
                            )
                            dateHeaderText(
                                format: "EEE d MMM yyyy",
                                fixedWidth: false
                            )
                        }
                        .frame(maxWidth: .infinity)

                        if calendar.isDateInToday(selectedDate) {
                            Text("Today")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Choose date")

                Button {
                    moveDay(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(!canMoveDay(by: 1))
                .accessibilityLabel("Next day")
            }

            if !calendar.isDateInToday(selectedDate),
               isTodayInsideSchedule {
                Button("Today") {
                    selectedDate = calendar.startOfDay(for: Date())
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Games",
            systemImage: "hockey.puck",
            description: Text("There are no hockey games scheduled for this date.")
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    private func competitionRank(
        _ competitionID: String
    ) -> String {
        if let favoriteCompetitionID,
           competitionID == favoriteCompetitionID {
            return "0-\(competitionID)"
        }

        if competitionID == "NHL" {
            return "1-NHL"
        }

        return "2-\(ScoreboardCompetitionCatalog.displayName(for: competitionID))"
    }

    private func sortGamesWithinCompetition(
        _ games: [HockeyGame]
    ) -> [HockeyGame] {
        let favoriteTeamID = settings.favoriteTeamID

        return games.enumerated()
            .sorted { lhs, rhs in
                if let favoriteTeamID {
                    let leftFavorite = isFavoriteGame(
                        lhs.element,
                        favoriteTeamID: favoriteTeamID
                    )

                    let rightFavorite = isFavoriteGame(
                        rhs.element,
                        favoriteTeamID: favoriteTeamID
                    )

                    if leftFavorite != rightFavorite {
                        return leftFavorite
                    }
                }

                let leftFinal = lhs.element.status == .final
                let rightFinal = rhs.element.status == .final

                if leftFinal != rightFinal {
                    return !leftFinal
                }

                if lhs.element.startTime != rhs.element.startTime {
                    return lhs.element.startTime < rhs.element.startTime
                }

                return lhs.offset < rhs.offset
            }
            .map { $0.element }
    }

    private func isFavoriteGame(
        _ game: HockeyGame,
        favoriteTeamID: String
    ) -> Bool {
        let selected = favoriteTeamID.uppercased()
        return game.awayTeam.id == favoriteTeamID
            || game.homeTeam.id == favoriteTeamID
            || game.awayTeam.abbreviation.uppercased() == selected
            || game.homeTeam.abbreviation.uppercased() == selected
    }

    private func displayedPrediction(
        for game: HockeyGame
    ) -> MoneyPuckGamePrediction? {
        guard settings.showPregamePredictions,
              game.leagueCode == "NHL" else {
            return nil
        }

        return moneyPuckPredictions[game.id]
    }

    private var isTodayInsideSchedule: Bool {
        let today = calendar.startOfDay(for: Date())
        return availableRange.contains(today)
    }

    private func moveDay(by amount: Int) {
        guard let date = calendar.date(
            byAdding: .day,
            value: amount,
            to: selectedDate
        ) else { return }

        selectedDate = calendar.startOfDay(for: date)
    }

    private func canMoveDay(by amount: Int) -> Bool {
        guard let date = calendar.date(
            byAdding: .day,
            value: amount,
            to: selectedDate
        ) else { return false }

        return availableRange.contains(calendar.startOfDay(for: date))
    }

    private var pollingDateKey: String {
        "poll-\(selectedDatePredictionKey)"
    }

    private func dateHeaderText(
        format: String,
        fixedWidth: Bool
    ) -> some View {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.calendar = calendar
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = format

        return Text(formatter.string(from: selectedDate))
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(fixedWidth ? 1.0 : 0.75)
            .fixedSize(horizontal: fixedWidth, vertical: false)
    }

    private var selectedDatePredictionKey: String {
        let parts = calendar.dateComponents(
            [.year, .month, .day],
            from: selectedDate
        )
        let dateKey = String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
        let snapshotKey = viewModel.snapshot?.generatedAt.timeIntervalSince1970 ?? 0
        return "\(dateKey)-\(snapshotKey)"
    }

    private var livePredictionRefreshKey: String {
        let liveIDs = nhlGamesForSelectedDate
            .filter { $0.status == .live }
            .map(\.id)
            .sorted()
            .joined(separator: ",")
        return "\(selectedDatePredictionKey)-\(liveIDs)"
    }

    private func loadMoneyPuckPredictions() async {
        guard settings.showPregamePredictions else {
            moneyPuckPredictions = [:]
            return
        }

        let games = nhlGamesForSelectedDate.filter {
            $0.status == .scheduled || $0.status == .live
        }
        guard !games.isEmpty else {
            moneyPuckPredictions = [:]
            return
        }

        do {
            moneyPuckPredictions = try await MoneyPuckPredictionService()
                .fetchPredictions(
                    for: selectedDate,
                    games: games
                )
        } catch {
            moneyPuckPredictions = [:]
        }
    }

    private func selectInitialDateIfNeeded() {
        guard !selectedInitialDate,
              let nearest = viewModel.nearestGameDate(
                to: Date(),
                calendar: calendar
              ) else { return }

        selectedDate = nearest
        selectedInitialDate = true
    }
    private enum LiveRefreshCadence {
        case fiveSeconds
        case thirtySeconds
        case nextMinute
        case nextTenMinutes
        case nextHour
        case stopped
    }

    private func runAdaptiveLivePolling() async {
        guard calendar.isDateInToday(
            selectedDate
        ) else {
            return
        }

        while !Task.isCancelled {
            guard calendar.isDateInToday(
                selectedDate
            ) else {
                return
            }

            // Poll immediately instead of sleeping first. This keeps the
            // visible score/state moving even if the user never presses
            // the manual refresh button.
            await viewModel.refreshLiveGames()

            let now = Date()

            let cadence = liveRefreshCadence(
                for: gamesForSelectedDate,
                now: now
            )

            guard let delay =
                    delayForCadence(
                        cadence,
                        from: now
                    )
            else {
                return
            }

            switch cadence {
            case .nextMinute,
                 .nextTenMinutes,
                 .nextHour:
                await loadMoneyPuckPredictions()

            case .fiveSeconds,
                 .thirtySeconds,
                 .stopped:
                break
            }

            do {
                try await Task.sleep(
                    for: .seconds(delay)
                )
            } catch {
                return
            }
        }
    }

    private func liveRefreshCadence(
        for games: [HockeyGame],
        now: Date
    ) -> LiveRefreshCadence {
        guard calendar.isDateInToday(selectedDate) else {
            return .stopped
        }

        // True off-day.
        guard !games.isEmpty else {
            return .nextHour
        }

        let liveGames = games.filter {
            $0.status == .live
        }

        // A game counts as actively playing only after the puck has actually
        // dropped. This avoids treating "1st · 20:00" as active play.
        let activelyPlayingGames = liveGames.filter { game in
            hasPuckDropped(in: game) &&
            game.isIntermission != true
        }

        // If even one game is actively being played, use the fastest cadence.
        if !activelyPlayingGames.isEmpty {
            return .fiveSeconds
        }

        // Games that have genuinely started, but are currently between periods.
        let startedLiveGames = liveGames.filter {
            hasPuckDropped(in: $0)
        }

        if !startedLiveGames.isEmpty,
           startedLiveGames.allSatisfy({ $0.isIntermission == true }) {
            return .thirtySeconds
        }

        // Scheduled time has arrived/passed, but NHL has not shown an actual
        // puck drop yet. Check on each minute boundary.
        let waitingForPuckDrop = games.contains { game in
            let hasNotDropped =
                game.status == .scheduled ||
                (game.status == .live && !hasPuckDropped(in: game))

            return hasNotDropped &&
                game.startTime <= now
        }

        if waitingForPuckDrop {
            return .nextMinute
        }

        // Find the next game that has not begun.
        let nextGameStart = games
            .filter { game in
                game.status == .scheduled ||
                (game.status == .live && !hasPuckDropped(in: game))
            }
            .map(\.startTime)
            .filter { $0 > now }
            .min()

        if let nextGameStart {
            let timeUntilGame = nextGameStart.timeIntervalSince(now)

            // Within one hour of scheduled start, check every ten minutes.
            if timeUntilGame <= 60 * 60 {
                return .nextTenMinutes
            }

            // Game is still more than an hour away.
            return .nextHour
        }

        // Everything for today is final/postponed, so there is nothing left
        // that needs live polling.
        let dayIsFinished = games.allSatisfy { game in
            game.status == .final ||
            game.status == .postponed
        }

        if dayIsFinished {
            return .stopped
        }

        return .nextHour
    }

    private func hasPuckDropped(
        in game: HockeyGame
    ) -> Bool {
        guard game.status == .live else {
            return false
        }

        // If we're in an intermission, the game obviously started already.
        if game.isIntermission == true {
            return true
        }

        guard let period = game.periodNumber else {
            return false
        }

        // Any period after the first means play has unquestionably started.
        if period > 1 {
            return true
        }

        guard period == 1,
              let remainingSeconds = clockSeconds(
                from: game.timeRemaining
              ) else {
            return false
        }

        // NHL can mark a game live before the opening faceoff while the
        // scoreboard still reads 20:00. Only switch to five-second polling
        // once the first-period clock actually moves.
        return remainingSeconds < 20 * 60
    }

    private func clockSeconds(
        from clock: String?
    ) -> Int? {
        guard let clock else {
            return nil
        }

        let parts = clock
            .split(separator: ":")
            .compactMap { Int($0) }

        guard parts.count == 2 else {
            return nil
        }

        return (parts[0] * 60) + parts[1]
    }

    private func delayForCadence(
        _ cadence: LiveRefreshCadence,
        from now: Date
    ) -> TimeInterval? {
        switch cadence {
        case .fiveSeconds:
            return 5

        case .thirtySeconds:
            return 30

        case .nextMinute:
            return delayUntilNextMinute(from: now)

        case .nextTenMinutes:
            return delayUntilNextTenMinuteBoundary(from: now)

        case .nextHour:
            return delayUntilNextHour(from: now)

        case .stopped:
            return nil
        }
    }

    private func delayUntilNextMinute(
        from date: Date
    ) -> TimeInterval {
        let second = calendar.component(
            .second,
            from: date
        )

        return TimeInterval(
            max(1, 60 - second)
        )
    }

    private func delayUntilNextTenMinuteBoundary(
        from date: Date
    ) -> TimeInterval {
        let minute = calendar.component(
            .minute,
            from: date
        )

        let second = calendar.component(
            .second,
            from: date
        )

        let minutesIntoBlock = minute % 10
        let minutesRemaining = 9 - minutesIntoBlock

        return TimeInterval(
            max(
                1,
                (minutesRemaining * 60) +
                (60 - second)
            )
        )
    }

    private func delayUntilNextHour(
        from date: Date
    ) -> TimeInterval {
        let minute = calendar.component(
            .minute,
            from: date
        )

        let second = calendar.component(
            .second,
            from: date
        )

        return TimeInterval(
            max(
                1,
                ((59 - minute) * 60) +
                (60 - second)
            )
        )
    }
}


// ICEOMETRICS_SCOREBOARD_SMART_FILL_ALPHA_V1_HELPERS
// Signals are soft contributions, not binary "important game" rules.
// Standings proximity is NOT a simulated playoff-odds change.
private enum ScoreboardSmartFillRanker {
    struct Ranked: Identifiable {
        let game: HockeyGame
        let score: Double
        let note: String
        var id: String { game.id }
    }

    private static let east: Set<String> = [
        "BOS", "BUF", "CAR", "CBJ", "DET", "FLA", "MTL", "NJD",
        "NYI", "NYR", "OTT", "PHI", "PIT", "TBL", "TOR", "WSH"
    ]
    private static let west: Set<String> = [
        "ANA", "CHI", "COL", "DAL", "EDM", "LAK", "MIN", "NSH",
        "SEA", "SJS", "STL", "UTA", "VAN", "VGK", "WPG", "CGY"
    ]

    static func rank(
        games: [HockeyGame],
        favoriteTeamID: String?,
        standings: [Standing],
        selectedDate: Date,
        predictions: [String: MoneyPuckGamePrediction]
    ) -> [Ranked] {
        let nhlStandings = standings.filter { $0.team.leagueCode == "NHL" }
        var lookup: [String: Standing] = [:]
        for row in nhlStandings {
            lookup[row.team.abbreviation.uppercased()] = row
        }
        let favoriteCode = nhlStandings.first(where: {
            $0.team.id == favoriteTeamID
        })?.team.abbreviation.uppercased()
        let favorite = favoriteCode.flatMap { lookup[$0] }
        let maxGamesPlayed = nhlStandings.map(\.gamesPlayed).max() ?? 0
        let seasonMaturity = min(1.0, max(0.0, (Double(maxGamesPlayed) - 30) / 48))
        // Current standings must never be used to "explain" an old game date.
        let useCurrentStandings = abs(selectedDate.timeIntervalSince(Date())) < 2 * 86400

        var results: [Ranked] = []
        results.reserveCapacity(games.count)
        for game in games {
            let isFavorite = favoriteTeamID.map {
                game.awayTeam.id == $0 || game.homeTeam.id == $0
            } ?? false
            var score = 0.08
            var reasons: [(Double, String)] = []
            if isFavorite {
                score += 0.62
                reasons.append((0.62, "Your favorite team"))
            }

            let drama = liveDrama(game)
            if game.status == .live {
                score += 0.16
                reasons.append((0.16, "Live game"))
            }
            score += drama
            if drama >= 0.12 {
                reasons.append((drama, "Close game in a decisive stretch"))
            }

            if game.status == .scheduled,
               let prediction = predictions[game.id] {
                let p = min(1.0, max(0.0, prediction.awayWinProbability))
                let evenness = 1 - abs(p - 0.5) * 2
                score += 0.05 * evenness
            }

            if useCurrentStandings,
               game.leagueCode == "NHL",
               let favorite,
               let favoriteCode,
               !isFavorite,
               seasonMaturity > 0 {
                let favoritePct = pointPct(favorite)
                let codes = [game.awayTeam.abbreviation.uppercased(),
                             game.homeTeam.abbreviation.uppercased()]
                let relevances = codes.compactMap { code -> Double? in
                    guard let other = lookup[code] else { return nil }
                    let gap = abs(pointPct(other) - favoritePct)
                    // Compare expected point pace, with softer tails so a
                    // team 5-10 points away can still affect a playoff race.
                    let bandwidth = 0.065 + (1 - seasonMaturity) * 0.075
                    let proximity = exp(-gap / bandwidth)
                    let sameConference: Bool =
                        (east.contains(code) && east.contains(favoriteCode)) ||
                        (west.contains(code) && west.contains(favoriteCode))
                    return proximity * (sameConference ? 1.0 : 0.20)
                }
                if !relevances.isEmpty {
                    let combined = 1 - relevances.reduce(1.0) {
                        $0 * (1 - min(1, max(0, $1)))
                    }
                    let leverage = 0.76 * seasonMaturity * combined
                    score += leverage
                    if leverage >= 0.10 {
                        reasons.append((leverage, "Nearby in your team's standings race"))
                    }
                }
            }

            if reasons.isEmpty {
                reasons.append((0, game.status == .scheduled
                    ? "Upcoming matchup" : "Today's matchup"))
            }
            reasons.sort { $0.0 > $1.0 }
            let note = reasons.prefix(2).map(\.1).joined(separator: " · ")
            results.append(Ranked(game: game, score: score, note: note))
        }

        // Rank bands discourage small probability/clock fluctuations from
        // constantly shuffling live tiles. Within a band, use start time.
        return results.sorted { left, right in
            let a = Int((left.score * 10).rounded(.down))
            let b = Int((right.score * 10).rounded(.down))
            if a != b { return a > b }
            if left.game.startTime != right.game.startTime {
                return left.game.startTime < right.game.startTime
            }
            return left.id < right.id
        }
    }

    private static func pointPct(_ standing: Standing) -> Double {
        Double(standing.points) / Double(max(1, standing.gamesPlayed * 2))
    }

    private static func liveDrama(_ game: HockeyGame) -> Double {
        guard game.status == .live,
              let away = game.awayScore,
              let home = game.homeScore else { return 0 }
        let margin = abs(away - home)
        let closeness = exp(-Double(margin) * 0.85)
        let period = max(1, game.periodNumber ?? 1)
        let periodType = (game.periodType ?? "").uppercased()
        let elapsedFraction: Double
        if periodType == "OT" || periodType == "SO" || period > 3 {
            elapsedFraction = 1
        } else if let clock = game.timeRemaining,
                  let seconds = clockSeconds(clock) {
            let elapsed = min(1200, max(0, 1200 - seconds))
            elapsedFraction = min(1, (Double(period - 1) + Double(elapsed) / 1200) / 3)
        } else {
            elapsedFraction = min(1, Double(period - 1) / 3)
        }
        let lateWeight = elapsedFraction * elapsedFraction
        let overtimeBonus = (periodType == "OT" || periodType == "SO") ? 0.13 : 0
        return 0.57 * closeness * lateWeight + overtimeBonus * closeness
    }

    private static func clockSeconds(_ raw: String) -> Int? {
        let pieces = raw.split(separator: ":")
        guard pieces.count == 2,
              let minutes = Int(pieces[0]),
              let seconds = Int(pieces[1]), seconds < 60 else { return nil }
        return minutes * 60 + seconds
    }
}

// ICEOMETRICS_SCOREBOARD_SMART_FILL_LAYOUT_V2_TILE
// Center the game content vertically, avoid duplicate scores beside logos,
// and scale iconography with card density instead of stretching empty cards.
// ICEOMETRICS_NOTES_BATCH02_SMART_COMPOSITION_V1
// Game importance controls layout, but does not add a misleading "featured"
// label. Width AND height determine the logo size, never width alone.
// ICEOMETRICS_NOTES_BIGPASS08_SMART_RESPONSIVE
private struct SmartFillGameTile: View {
    let item: ScoreboardSmartFillRanker.Ranked
    let featured: Bool
    let condensed: Bool
    let spacious: Bool
    let prediction: MoneyPuckGamePrediction?
    @EnvironmentObject private var settings: AppSettingsStore

    private var game: HockeyGame { item.game }

    private var usefulDetail: String? {
        let reason = item.note
        if reason.contains("Close game") || reason.contains("standings race") {
            return reason
        }
        return nil
    }

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = max(1, proxy.size.width)
            let availableHeight = max(1, proxy.size.height)
            let relativeWidth: CGFloat = condensed ? 0.13 : (featured ? 0.18 : 0.17)
            let relativeHeight: CGFloat = condensed ? 0.30 : 0.41
            let logoCap: CGFloat = featured ? 132 : (spacious ? 125 : (condensed ? 48 : 92))
            let logoSize = min(logoCap, max(24, min(
                availableWidth * relativeWidth,
                availableHeight * relativeHeight
            )))
            let scoreSize = min(featured ? 56 : (spacious ? 50 : 42),
                                max(19, min(availableWidth * 0.110,
                                            availableHeight * 0.27)))
            let metricSize: CGFloat = condensed ? 9 : min(16, max(10, availableHeight * 0.045))

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    cornerProbability(isAway: true, metricSize: metricSize)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if game.status != .scheduled {
                        Text(statusText)
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }

                    cornerProbability(isAway: false, metricSize: metricSize)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Spacer(minLength: condensed ? 2 : 5)

                HStack(alignment: .center, spacing: condensed ? 3 : 8) {
                    teamColumn(game.awayTeam, isAway: true,
                               logoSize: logoSize, metricSize: metricSize)
                    Spacer(minLength: 0)
                    VStack(spacing: 4) {
                        if game.status == .live || game.status == .final {
                            Text("\(game.awayScore ?? 0) – \(game.homeScore ?? 0)")
                                .font(.system(size: scoreSize,
                                              weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.60)
                        } else if game.status == .scheduled {
                            Text("@")
                                .font(.system(size: max(16, scoreSize * 0.65),
                                              weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text(game.startTime.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: max(condensed ? 17 : 21, scoreSize * 0.72),
                                              weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        } else {
                            Text("@")
                                .font(.system(size: max(15, scoreSize * 0.55),
                                              weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minWidth: condensed ? 52 : 70)
                    Spacer(minLength: 0)
                    teamColumn(game.homeTeam, isAway: false,
                               logoSize: logoSize, metricSize: metricSize)
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: condensed ? 2 : 5)

                // Venue stays visible whenever the card is tall enough.
                if let venue = game.venue,
                   !venue.isEmpty,
                   availableHeight >= 195,
                   !condensed {
                    Label(venue, systemImage: "mappin.and.ellipse")
                        .font(.system(size: min(14, max(10, availableHeight * 0.047))))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 4)
                }

                if let usefulDetail, !condensed {
                    Text(usefulDetail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(condensed ? 9 : (featured || spacious ? 15 : 12))
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.thinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(featured ? 0.17 : 0.09), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func cornerProbability(
        isAway: Bool,
        metricSize: CGFloat
    ) -> some View {
        let value = isAway ? prediction?.awayWinProbability : prediction?.homeWinProbability
        if (game.status == .scheduled || game.status == .live),
           let value {
            Text(value, format: .percent.precision(.fractionLength(1)))
                .font(.system(size: max(metricSize, 11), weight: .semibold,
                              design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        } else {
            Text(" ")
                .font(.system(size: max(metricSize, 11)))
                .accessibilityHidden(true)
        }
    }

    private func teamColumn(
        _ team: Team,
        isAway: Bool,
        logoSize: CGFloat,
        metricSize: CGFloat
    ) -> some View {
        let shots = isAway ? game.awayShots : game.homeShots

        return VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                TeamLogoView(team: team, size: logoSize)
                if team.id == settings.favoriteTeamID {
                    Image(systemName: "star.fill")
                        .font(.system(size: max(9, logoSize * 0.22)))
                        .foregroundStyle(Color.accentColor)
                        .offset(x: 3, y: -3)
                        .accessibilityLabel("Favorite team")
                }
            }

            Text(team.abbreviation)
                .font(.system(size: max(10, metricSize + 2),
                              weight: .semibold, design: .rounded))
                .lineLimit(1)

            if (game.status == .live || game.status == .final),
               let shots {
                Text("\(shots) SOG")
                    .font(.system(size: metricSize, weight: .medium,
                                  design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var statusText: String {
        switch game.status {
        case .scheduled:
            return game.startTime.formatted(date: .omitted, time: .shortened)
        case .live:
            return game.scoreboardLiveText
        case .final: return "FINAL"
        case .postponed: return "POSTPONED"
        case .unknown: return "STATUS PENDING"
        }
    }
}


private struct ScoreboardSmartFillSection: View {
    let section: ScoreboardCompetitionSection
    let onSelect: (HockeyGame) -> Void
    let predictionForGame: (HockeyGame) -> MoneyPuckGamePrediction?

    @State private var availableWidth: CGFloat = 320

    private var columnsPerRow: Int {
        let gameCount = max(1, section.games.count)

        let maxColumns = max(
            1,
            Int((availableWidth + 16) / 316)
        )

        let rowCount = max(
            1,
            (gameCount + maxColumns - 1) / maxColumns
        )

        return max(
            1,
            (gameCount + rowCount - 1) / rowCount
        )
    }

    private var numberOfRows: Int {
        (section.games.count + columnsPerRow - 1)
            / columnsPerRow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.title)
                    .font(.headline)

                Spacer()

                Text(section.gameCountText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            LazyVStack(spacing: 16) {
                ForEach(0..<numberOfRows, id: \.self) { row in
                    let start = row * columnsPerRow
                    let end = min(
                        start + columnsPerRow,
                        section.games.count
                    )

                    HStack(alignment: .top, spacing: 16) {
                        ForEach(start..<end, id: \.self) { index in
                            let game = section.games[index]

                            Button {
                                onSelect(game)
                            } label: {
                                ScoreboardCardView(
                                    game: game,
                                    prediction: predictionForGame(game)
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                            .accessibilityHint(
                                "Open game details"
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { width in
            if abs(width - availableWidth) > 1 {
                availableWidth = width
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func scoreboardDateSwipe(
        _ onSwipe: @escaping (Int) -> Void
    ) -> some View {
        #if os(iOS)
        simultaneousGesture(
            DragGesture(minimumDistance: 48)
                .onEnded { value in
                    let width = value.translation.width
                    let height = value.translation.height

                    guard abs(width) > abs(height) * 1.25,
                          abs(width) >= 55 else {
                        return
                    }

                    onSwipe(width < 0 ? 1 : -1)
                }
        )
        #else
        self
        #endif
    }
}

private struct ScoreboardCalendarPicker: View {
    @Binding var selectedDate: Date
    let availableRange: ClosedRange<Date>

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose a Date")
                .font(.headline)

            DatePicker(
                "Game date",
                selection: $selectedDate,
                in: availableRange,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}


// ICEOMETRICS_UNIFIED_SMART_20261016_V1
// One responsive Smart Fill layout for iPhone, iPad and Mac. Game relevance
// changes weights; actual measured width decides columns. No device forks.
private struct IceometricsDocSmartSection: View {
    let section: ScoreboardCompetitionSection
    let viewportHeight: CGFloat
    let sectionGameCounts: [Int]
    let sectionFavoriteFlags: [Bool]
    let favoriteTeamID: String?
    let allGames: [HockeyGame]
    let onSelect: (HockeyGame) -> Void
    let predictionForGame: (HockeyGame) -> MoneyPuckGamePrediction?

    @State private var availableWidth: CGFloat = 740
    private let gap: CGFloat = 12

    // A readable cell is never narrower than this, including on iPhone.
    private var maxColumns: Int {
        max(1, Int((max(1, availableWidth) + gap) / (184 + gap)))
    }

    private var favoriteCode: String? {
        guard let favoriteTeamID else { return nil }
        // Usually the preference is already an NHL abbreviation. Avoid
        // scanning the entire schedule on every live-score refresh.
        let known = Set([
            "BOS", "BUF", "DET", "FLA", "MTL", "OTT", "TBL", "TOR",
            "CAR", "CBJ", "NJD", "NYI", "NYR", "PHI", "PIT", "WSH",
            "CHI", "COL", "DAL", "MIN", "NSH", "STL", "UTA", "WPG",
            "ANA", "CGY", "EDM", "LAK", "SJS", "SEA", "VAN", "VGK"
        ])
        let direct = favoriteTeamID.uppercased()
        if known.contains(direct) { return direct }
        let favorite = allGames.lazy.compactMap { game -> Team? in
            if game.awayTeam.id == favoriteTeamID { return game.awayTeam }
            if game.homeTeam.id == favoriteTeamID { return game.homeTeam }
            return nil
        }.first
        return favorite?.abbreviation.uppercased()
    }

    private var divisionCodes: Set<String> {
        guard let favoriteCode else { return [] }
        let divisions: [[String]] = [
            ["BOS", "BUF", "DET", "FLA", "MTL", "OTT", "TBL", "TOR"],
            ["CAR", "CBJ", "NJD", "NYI", "NYR", "PHI", "PIT", "WSH"],
            ["CHI", "COL", "DAL", "MIN", "NSH", "STL", "UTA", "WPG"],
            ["ANA", "CGY", "EDM", "LAK", "SJS", "SEA", "VAN", "VGK"]
        ]
        return Set(divisions.first(where: { $0.contains(favoriteCode) }) ?? [])
    }

    private func isFavorite(_ game: HockeyGame) -> Bool {
        guard let favoriteTeamID else { return false }
        let code = favoriteCode
        return game.awayTeam.id == favoriteTeamID
            || game.homeTeam.id == favoriteTeamID
            || (code != nil && (
                game.awayTeam.abbreviation.uppercased() == code
                || game.homeTeam.abbreviation.uppercased() == code
            ))
    }

    private func lateClose(_ game: HockeyGame) -> Bool {
        guard game.status == .live, let away = game.awayScore,
              let home = game.homeScore, abs(away - home) <= 1 else { return false }
        return (game.periodNumber ?? 0) >= 3
    }

    private func overtime(_ game: HockeyGame) -> Bool {
        guard game.status == .live else { return false }
        let period = game.periodType?.uppercased() ?? ""
        return period == "OT" || period == "SO" || (game.periodNumber ?? 0) >= 4
    }

    private func rank(_ game: HockeyGame, rivals: Set<String>) -> Int {
        var rank = 0
        if isFavorite(game) { rank += 100 }
        if !rivals.isEmpty {
            if rivals.contains(game.awayTeam.abbreviation.uppercased()) { rank += 22 }
            if rivals.contains(game.homeTeam.abbreviation.uppercased()) { rank += 22 }
        }
        if overtime(game) { rank += 48 }
        else if lateClose(game) { rank += 38 }
        return rank
    }

    private var orderedGames: [HockeyGame] {
        let rivals = divisionCodes
        return section.games.enumerated().sorted { lhs, rhs in
            let a = rank(lhs.element, rivals: rivals)
            let b = rank(rhs.element, rivals: rivals)
            if a != b { return a > b }
            if lhs.element.startTime != rhs.element.startTime {
                return lhs.element.startTime < rhs.element.startTime
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    // Balanced row counts avoid a lonely card consuming an entire last row.
    private func rowIndices(_ row: Int, gameCount: Int, rows: Int) -> Range<Int> {
        let base = gameCount / rows
        let extras = gameCount % rows
        let start = row * base + min(row, extras)
        return start..<(start + base + (row < extras ? 1 : 0))
    }

    // All competitions share the same viewport-height budget and column rule.
    private var totalRows: Int {
        max(1, sectionGameCounts.reduce(0) { total, count in
            total + (count + maxColumns - 1) / maxColumns
        })
    }

    private var cardHeight: CGFloat {
        let headings = CGFloat(sectionGameCounts.count) * 45
        let gaps = CGFloat(max(0, totalRows - 1)) * gap
        let budget = (viewportHeight - 129 - headings - gaps) / CGFloat(totalRows)
        // Sparse slates use the available height instead of leaving a dead
        // lower half on Mac/iPad. Busy slates retain compact, scrollable rows.
        let sparse = sectionGameCounts.reduce(0, +) <= 4
        return max(126, min(sparse ? 920 : 550, budget))
    }

    private func weight(_ game: HockeyGame, rivals: Set<String>) -> CGFloat {
        let numberOfGames = sectionGameCounts.reduce(0, +)
        let crowding = min(1.0, CGFloat(max(0, numberOfGames - 2)) / 12.0)
        var value: CGFloat = 1
        // Favorite is visibly larger on a busy slate (not a full-width row).
        // Weight tapers moderately with crowding but never disappears.
        if isFavorite(game) { value += 1.08 * (1 - crowding * 0.23) }
        if !isFavorite(game)
            && (rivals.contains(game.awayTeam.abbreviation.uppercased())
                || rivals.contains(game.homeTeam.abbreviation.uppercased())) {
            value += 0.27 * (1 - crowding * 0.45)
        }
        if overtime(game) || lateClose(game) { value += 0.45 * (1 - crowding * 0.30) }
        return min(2.30, value)
    }

    // Only facts available in the loaded schedule are shown. Missing prior games
    // are not counted as losses or assumed to exist.
    private func seasonSeries(for game: HockeyGame) -> String? {
        guard game.leagueCode == "NHL", game.gameTypeId != 1 else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.dateComponents([.year, .month], from: game.startTime)
        let seasonYear = (date.month ?? 10) >= 7 ? (date.year ?? 2026) : (date.year ?? 2026) - 1
        let seasonStart = calendar.date(from: DateComponents(year: seasonYear, month: 7, day: 1))
            ?? game.startTime
        var awayWins = 0
        var homeWins = 0
        for past in allGames where past.id != game.id && past.status == .final
            && past.gameTypeId == 2 && past.startTime >= seasonStart
            && past.startTime < game.startTime {
            let samePair = (past.awayTeam.id == game.awayTeam.id && past.homeTeam.id == game.homeTeam.id)
                || (past.awayTeam.id == game.homeTeam.id && past.homeTeam.id == game.awayTeam.id)
            guard samePair, let a = past.awayScore, let h = past.homeScore, a != h else { continue }
            let winner = a > h ? past.awayTeam.id : past.homeTeam.id
            if winner == game.awayTeam.id { awayWins += 1 } else { homeWins += 1 }
        }
        guard awayWins + homeWins > 0 else { return nil }
        return "Loaded season series · \(game.awayTeam.abbreviation) \(awayWins)–\(homeWins) \(game.homeTeam.abbreviation)"
    }

    var body: some View {
        let rivals = divisionCodes
        let sorted = orderedGames
        let rows = max(1, (sorted.count + maxColumns - 1) / maxColumns)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(section.title).font(.headline)
                Spacer(minLength: 0)
                Text(section.gameCountText)
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            LazyVStack(spacing: gap) {
                ForEach(0..<rows, id: \.self) { row in
                    let indices = Array(rowIndices(row, gameCount: sorted.count, rows: rows))
                    let rowGames = indices.map { sorted[$0] }
                    let totalWeight = rowGames.reduce(CGFloat.zero) { $0 + weight($1, rivals: rivals) }
                    let usableWidth = max(1, availableWidth - CGFloat(max(0, rowGames.count - 1)) * gap)
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(rowGames) { game in
                            Button { onSelect(game) } label: {
                                IceometricsDocSmartCard(
                                    game: game,
                                    prediction: predictionForGame(game),
                                    cardHeight: cardHeight,
                                    seasonSeriesText: cardHeight >= 295 ? seasonSeries(for: game) : nil,
                                    emphasis: isFavorite(game) ? .favorite :
                                        (overtime(game) || lateClose(game) ? .close :
                                            (rivals.contains(game.awayTeam.abbreviation.uppercased())
                                             || rivals.contains(game.homeTeam.abbreviation.uppercased())
                                             ? .rival : .normal)),
                                    // Limit network requests during large slates:
                                    // only unusually important roomy cards load rich detail.
                                    loadRichDetail: sectionGameCounts.reduce(0, +) <= 4
                                        || (cardHeight >= 270 && (
                                            isFavorite(game) || overtime(game) || lateClose(game)
                                        ))
                                )
                            }
                            .buttonStyle(.plain)
                            .frame(width: usableWidth * weight(game, rivals: rivals) / max(0.01, totalWeight))
                            .accessibilityHint("Open game details")
                        }
                    }
                    .frame(width: availableWidth, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { width in
            if abs(width - availableWidth) > 1 { availableWidth = width }
        }
    }
}

private enum IceometricsSmartEmphasis {
    case normal, rival, close, favorite
}

private struct IceometricsDocSmartCard: View {
    let game: HockeyGame
    let prediction: MoneyPuckGamePrediction?
    let cardHeight: CGFloat
    let seasonSeriesText: String?
    let emphasis: IceometricsSmartEmphasis
    let loadRichDetail: Bool

    @State private var expandedDetail: NHLGameDetail?

    private var showPrediction: Bool {
        game.status == .scheduled || game.status == .live
    }

    private var isOvertime: Bool {
        let type = game.periodType?.uppercased() ?? ""
        return game.status == .live
            && (type == "OT" || type == "SO" || (game.periodNumber ?? 0) >= 4)
    }

    private var isClose: Bool {
        guard game.status == .live, let a = game.awayScore,
              let h = game.homeScore else { return false }
        return (game.periodNumber ?? 0) >= 3 && abs(a - h) <= 1
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let compact = cardHeight < 205 || width < 230
            let logoSize = min(176, max(30, min(width * 0.28, cardHeight * 0.32)))
            let scoreSize = min(82, max(18, min(width * 0.15, cardHeight * 0.23)))
            let supportingSize = min(21, max(10, min(width * 0.051, cardHeight * 0.055)))
            let detailFontSize = min(19, max(12, min(width * 0.028, cardHeight * 0.035)))
            let expanded = cardHeight >= 295 && width >= 265

            VStack(spacing: compact ? 4 : 11) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if showPrediction, let probability = prediction?.awayWinProbability {
                        Text(probability, format: .percent.precision(.fractionLength(1)))
                            .font(.system(size: supportingSize, weight: .semibold))
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    Spacer(minLength: 0)
                    if showPrediction, let probability = prediction?.homeWinProbability {
                        Text(probability, format: .percent.precision(.fractionLength(1)))
                            .font(.system(size: supportingSize, weight: .semibold))
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(.secondary)

                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    teamColumn(game.awayTeam, shots: game.awayShots, logoSize: logoSize,
                               supportingSize: supportingSize)
                    Spacer(minLength: 0)
                    VStack(spacing: 3) {
                        Text(scoreText)
                            .font(.system(size: scoreSize, weight: .heavy, design: .rounded))
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.55)
                        Text(statusText)
                            .font(.system(size: supportingSize, weight: .bold))
                            .foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                    teamColumn(game.homeTeam, shots: game.homeShots, logoSize: logoSize,
                               supportingSize: supportingSize)
                }
                // Keep verified context directly beneath the matchup instead of
                // pinning microscopic player names to the card's bottom edge.
                if game.status == .live, game.isIntermission != true,
                   let situation = expandedDetail?.specialTeams.state,
                   situation.contains("Power Play") {
                    Label(situation, systemImage: "bolt.fill")
                        .font(.system(size: max(11, supportingSize * 0.8), weight: .semibold))
                        .foregroundStyle(.orange).lineLimit(1)
                }

                if expanded {
                    VStack(spacing: min(18, max(8, cardHeight * 0.022))) {
                        if game.status == .scheduled, let detail = expandedDetail {
                            let awayLeader = detail.awayLeaders.points ?? detail.awayLeaders.goals
                            let homeLeader = detail.homeLeaders.points ?? detail.homeLeaders.goals
                            if awayLeader != nil || homeLeader != nil {
                                comparisonDetail(
                                    title: "TEAM LEADERS",
                                    away: awayLeader ?? "—",
                                    home: homeLeader ?? "—",
                                    fontSize: detailFontSize
                                )
                            }
                        }
                        if (game.status == .live || game.status == .final),
                           let scorers = expandedDetail?.goalScorers, !scorers.isEmpty {
                            let away = scorers.filter {
                                $0.team.uppercased() == game.awayTeam.abbreviation.uppercased()
                            }.suffix(3)
                            let home = scorers.filter {
                                $0.team.uppercased() == game.homeTeam.abbreviation.uppercased()
                            }.suffix(3)
                            comparisonDetail(
                                title: "GOAL SCORERS",
                                away: away.isEmpty ? "—" : away.map { $0.player }.joined(separator: " · "),
                                home: home.isEmpty ? "—" : home.map { $0.player }.joined(separator: " · "),
                                fontSize: detailFontSize
                            )
                        }
                        if (game.status == .live || game.status == .final),
                           cardHeight >= 405, width >= 350,
                           let lines = expandedDetail?.stats {
                            ForEach(lines.filter { stat in
                                ["Face-off %", "Power Play"].contains(stat.label)
                                    && stat.awayValue != NHLGameDetailService.missingText
                                    && stat.homeValue != NHLGameDetailService.missingText
                            }) { stat in
                                comparisonDetail(
                                    title: stat.label.uppercased(),
                                    away: stat.awayValue,
                                    home: stat.homeValue,
                                    fontSize: detailFontSize * 0.85
                                )
                            }
                        }
                        if let seasonSeriesText {
                            Text(seasonSeriesText)
                                .font(.system(size: detailFontSize * 0.80, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(2).minimumScaleFactor(0.75)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                Spacer(minLength: 0)

                Label(
                    game.venue?.isEmpty == false ? (game.venue ?? "") : "Venue TBD",
                    systemImage: "mappin.and.ellipse"
                )
                .font(.system(size: max(10, supportingSize * 0.8)))
                .foregroundStyle(.secondary)
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, compact ? 9 : 16)
            .padding(.vertical, compact ? 8 : 13)
            .frame(width: width, height: geometry.size.height)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.quaternary, lineWidth: 1)
            }
            .task(id: "\(game.id)-\(game.status)-\(expanded)-\(loadRichDetail)") {
                guard expanded, loadRichDetail, game.leagueCode == "NHL" else {
                    expandedDetail = nil
                    return
                }
                // Max four large cards can request extra NHL data. The current
                // scoreboard source retains its normal live-score polling.
                expandedDetail = try? await NHLGameDetailService().fetchDetail(for: game)
            }
        }
        .frame(height: cardHeight)
        .accessibilityElement(children: .combine)
    }

    private func comparisonDetail(
        title: String,
        away: String,
        home: String,
        fontSize: CGFloat
    ) -> some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(game.awayTeam.abbreviation)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(title)
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: true, vertical: false)
                Text(game.homeTeam.abbreviation)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: fontSize * 0.76, weight: .medium))
            .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 14) {
                Text(away)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(home)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: fontSize, weight: .medium))
            .lineLimit(2)
            .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func teamColumn(_ team: Team, shots: Int?, logoSize: CGFloat,
                            supportingSize: CGFloat) -> some View {
        VStack(spacing: 3) {
            TeamLogoView(team: team, size: logoSize)
            if game.status == .live || game.status == .final {
                Text("SOG \(shots.map(String.init) ?? "–")")
                    .font(.system(size: supportingSize, weight: .medium))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var scoreText: String {
        switch game.status {
        case .scheduled, .unknown, .postponed: return "@"
        case .live, .final:
            return "\(game.awayScore.map(String.init) ?? "–") – \(game.homeScore.map(String.init) ?? "–")"
        }
    }

    private var statusText: String {
        switch game.status {
        case .scheduled, .unknown:
            return game.startTime.formatted(date: .omitted, time: .shortened)
        case .live:
            return game.scoreboardLiveText
        case .final:
            let type = game.periodType?.uppercased() ?? ""
            return (type == "OT" || type == "SO" || (game.periodNumber ?? 0) >= 4)
                ? "FINAL · OT/SO" : "FINAL"
        case .postponed: return "PPD"
        }
    }
}

