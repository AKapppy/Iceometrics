import SwiftUI

struct GameDetailView: View {
    let game: HockeyGame
    let prediction: MoneyPuckGamePrediction?
    let allGames: [HockeyGame]

    @Environment(\.dismiss) private var dismiss

    @State private var detail: NHLGameDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let missing = NHLGameDetailService.missingText

    // Keep Back at the leading edge of the popup, not with primary actions.
    private var gameDetailsBackPlacement: ToolbarItemPlacement {
        #if os(macOS)
        .navigation
        #else
        .topBarLeading
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                scoreHeader
                if let detail,
                   game.status == .live,
                   game.isIntermission != true,
                   let situation = detail.specialTeams.state,
                   situation.contains("Power Play") {
                    lastReportedSpecialTeamsBadge(situation)
                }


                if isLoading {
                    ProgressView("Loading game information…")
                        .padding(.vertical, 24)
                }

                if let detail {
                    if shouldShowGoalies(detail) {
                        goaliesSection(detail)
                    }

                    if shouldShowGoalScorers(detail) {
                        goalScorersSection(detail)
                    }

                    if shouldShowShots(detail) {
                        shotsSection(detail)
                    }

                    if shouldShowStats(detail) {
                        statsSection(detail)
                    }

                    if shouldShowScratches(detail) {
                        scratchesSection(detail)
                    }

                    if shouldShowLeaders(detail) {
                        leadersSection(detail)
                    }

                    if shouldShowSpecialTeams(detail) {
                        specialTeamsSection(detail)
                    }

                    if shouldShowPenalties(detail) {
                        penaltiesSection(detail)
                    }
                } else if !isLoading,
                          supportsRichDetail,
                          !isPregame {
                    missingDetailSection
                }

                seasonSeriesSection

                if let errorMessage {
                    Label(
                        errorMessage,
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .navigationTitle("")
        // ICEOMETRICS_UNIFIED_SMART_20261016_V1_VISIBLE_BACK
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .accessibilityLabel("Back")
                .keyboardShortcut(.cancelAction)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .task {
            await loadDetail()
        }
    }

    private var scoreHeader: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 18) {
                teamHeader(
                    team: game.awayTeam,
                    score: game.awayScore,
                    probability: prediction?.awayWinProbability
                )

                Text("@")
                    .font(
                        .system(
                            size: 24,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.secondary)

                teamHeader(
                    team: game.homeTeam,
                    score: game.homeScore,
                    probability: prediction?.homeWinProbability
                )
            }

            if game.status == .live,
               let state = detail?.specialTeams.state,
               state.contains("Power Play") {
                Label(state, systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.10), in: Capsule())
                    .accessibilityLabel(state)
            }

            HStack(spacing: 12) {
                if let venue = game.venue, !venue.isEmpty {
                    Label(venue, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(missing)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(statusBadgeText)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            .thinMaterial,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private func teamHeader(
        team: Team,
        score: Int?,
        probability: Double?
    ) -> some View {
        VStack(spacing: 7) {
            TeamLogoView(team: team, size: 62)

            Text(team.abbreviation)
                .font(.headline)

            if game.status == .live || game.status == .final {
                Text(score.map(String.init) ?? "–")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
            } else if let probability {
                Text(
                    probability,
                    format: .percent.precision(.fractionLength(1))
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func lastReportedSpecialTeamsBadge(_ situation: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(.orange)
            Text(situation)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            Text("Last reported")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func goaliesSection(_ detail: NHLGameDetail) -> some View {
        detailCard(title: "Goalies") {
            twoTeamHeader
            Divider()
            threeColumnRow(
                away: goalieText(detail.awayGoalie),
                label: "Starter",
                home: goalieText(detail.homeGoalie),
                emphasize: false
            )
        }
    }

    // ICEOMETRICS_NOTES_BIGPASS08_GOAL_COLUMNS
    private func goalScorersSection(_ detail: NHLGameDetail) -> some View {
        let awayGoals = detail.goalScorers.filter {
            $0.team == game.awayTeam.abbreviation
        }
        let homeGoals = detail.goalScorers.filter {
            $0.team == game.homeTeam.abbreviation
        }

        return detailCard(title: "Goal Scorers") {
            if detail.goalScorers.isEmpty {
                emptySemanticRow("No goals")
            } else {
                // Each team's scoring list has its own length: don't introduce
                // empty goal rows merely to align unrelated events.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        goalScorerColumn(team: game.awayTeam.abbreviation,
                                         goals: awayGoals)
                        goalScorerColumn(team: game.homeTeam.abbreviation,
                                         goals: homeGoals)
                    }
                    .frame(minWidth: 580)

                    VStack(alignment: .leading, spacing: 14) {
                        goalScorerColumn(team: game.awayTeam.abbreviation,
                                         goals: awayGoals)
                        goalScorerColumn(team: game.homeTeam.abbreviation,
                                         goals: homeGoals)
                    }
                }
            }
        }
    }

    private func goalScorerColumn(
        team: String,
        goals: [NHLGoalScorer]
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(team)
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.055))

            if goals.isEmpty {
                Text("No goals")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
            }

            ForEach(goals) { goal in
                Divider()
                HStack(alignment: .center, spacing: 10) {
                    Text("\(goal.period) · \(goal.time)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 78, alignment: .leading)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(goal.player)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        if !goal.assists.isEmpty {
                            Text(goal.assists.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.thinMaterial,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func shotsSection(_ detail: NHLGameDetail) -> some View {
        detailCard(title: "Shots On Goal") {
            if detail.shotsByPeriod.isEmpty {
                missingRow
            } else {
                VStack(spacing: 0) {
                    twoTeamHeader

                    ForEach(detail.shotsByPeriod) { row in
                        Divider()
                        threeColumnRow(
                            away: String(row.away),
                            label: row.label,
                            home: String(row.home),
                            emphasize: false
                        )
                    }

                    if detail.shotsByPeriod.first?.period != 0 {
                        Divider()
                        threeColumnRow(
                            away: String(
                                detail.shotsByPeriod.reduce(0) { $0 + $1.away }
                            ),
                            label: "Total",
                            home: String(
                                detail.shotsByPeriod.reduce(0) { $0 + $1.home }
                            ),
                            emphasize: true
                        )
                    }
                }
            }
        }
    }

    private func statsSection(_ detail: NHLGameDetail) -> some View {
        let rows = visibleStatRows(detail)

        return detailCard(title: "Game Stats") {
            VStack(spacing: 0) {
                twoTeamHeader

                ForEach(rows) { row in
                    Divider()
                    threeColumnRow(
                        away: row.awayValue,
                        label: row.label,
                        home: row.homeValue,
                        emphasize: false
                    )
                }
            }
        }
    }

    private func scratchesSection(_ detail: NHLGameDetail) -> some View {
        detailCard(title: "Scratched Players") {
            VStack(spacing: 0) {
                twoTeamHeader
                Divider()
                HStack(alignment: .top, spacing: 18) {
                    textList(detail.awayScratches)
                    Divider()
                    textList(detail.homeScratches)
                }
                .padding(12)
            }
        }
    }

    private func leadersSection(_ detail: NHLGameDetail) -> some View {
        detailCard(title: "Team Leaders") {
            VStack(spacing: 0) {
                twoTeamHeader
                Divider()
                leaderRow(
                    label: "Goals",
                    away: detail.awayLeaders.goals,
                    home: detail.homeLeaders.goals
                )
                Divider()
                leaderRow(
                    label: "Assists",
                    away: detail.awayLeaders.assists,
                    home: detail.homeLeaders.assists
                )
                Divider()
                leaderRow(
                    label: "Points",
                    away: detail.awayLeaders.points,
                    home: detail.homeLeaders.points
                )
            }
        }
    }

    private func specialTeamsSection(_ detail: NHLGameDetail) -> some View {
        detailCard(title: "Special Teams Context") {
            VStack(spacing: 10) {
                Text(detail.specialTeams.state ?? missing)
                    .font(.headline)
                    .frame(maxWidth: .infinity)

                threeColumnRow(
                    away: numberOrMissing(detail.specialTeams.awayPenaltiesTaken),
                    label: "Penalties Taken",
                    home: numberOrMissing(detail.specialTeams.homePenaltiesTaken),
                    emphasize: false
                )

                Divider()

                threeColumnRow(
                    away: numberOrMissing(detail.specialTeams.awayPenaltiesDrawn),
                    label: "Penalties Drawn",
                    home: numberOrMissing(detail.specialTeams.homePenaltiesDrawn),
                    emphasize: false
                )
            }
        }
    }

    private func penaltiesSection(_ detail: NHLGameDetail) -> some View {
        detailCard(title: "Penalty Summary") {
            if detail.penalties.isEmpty {
                missingRow
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(detail.penalties.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider() }
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(row.team)
                                .font(.caption.weight(.bold))
                                .frame(width: 42, alignment: .leading)
                            Text(row.description)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(row.period) · \(row.time)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                    }
                }
            }
        }
    }

    private var seasonSeriesSection: some View {
        detailCard(title: "Season Series · \(gameTypeTitle)") {
            if seasonSeriesGames.isEmpty {
                missingRow
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(seasonSeriesGames.enumerated()), id: \.element.id) { index, seriesGame in
                        if index > 0 { Divider() }
                        HStack(spacing: 10) {
                            Text(
                                seriesGame.startTime.formatted(
                                    .dateTime.month(.abbreviated).day()
                                )
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 54, alignment: .leading)

                            Text(
                                "\(seriesGame.awayTeam.abbreviation) @ \(seriesGame.homeTeam.abbreviation)"
                            )
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Text(seriesResultText(seriesGame))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                    }
                }
            }
        }
    }

    private var missingDetailSection: some View {
        detailCard(title: "Game Information") {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                Text(missing)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(14)
        }
    }

    private var twoTeamHeader: some View {
        HStack {
            Text(game.awayTeam.abbreviation)
                .frame(maxWidth: .infinity)

            Text("STAT")
                .frame(maxWidth: .infinity)
                .foregroundStyle(.secondary)

            Text(game.homeTeam.abbreviation)
                .frame(maxWidth: .infinity)
        }
        .font(.caption.weight(.bold))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func detailCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.bold())

            content()
                .frame(maxWidth: .infinity)
                .background(
                    .thinMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        }
    }

    private var missingRow: some View {
        Text(missing)
            .font(.body.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(14)
    }

    private func textList(_ values: [String]) -> some View {
        Text(values.isEmpty ? missing : values.joined(separator: "\n"))
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .foregroundStyle(values.isEmpty ? .secondary : .primary)
    }

    private func leaderRow(
        label: String,
        away: String?,
        home: String?
    ) -> some View {
        threeColumnRow(
            away: away ?? missing,
            label: label,
            home: home ?? missing,
            emphasize: false
        )
    }

    private func threeColumnRow(
        away: String,
        label: String,
        home: String,
        emphasize: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(away)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            Text(label)
                .frame(maxWidth: .infinity)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(home)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .font(emphasize ? .body.bold() : .body)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func goalieText(_ slot: NHLGoalieSlot?) -> String {
        guard let slot else {
            return missing
        }

        if slot.label == "Predicted" {
            return missing
        }

        if slot.label == "Confirmed" {
            return slot.name
        }

        return "\(slot.label): \(slot.name)"
    }

    private func numberOrMissing(_ value: Int?) -> String {
        value.map(String.init) ?? missing
    }

    private var supportsRichDetail: Bool {
        game.leagueCode == "NHL"
    }

    private var isPregame: Bool {
        game.status == .scheduled || game.status == .unknown
    }

    private func hasValue(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return !trimmed.isEmpty && trimmed != missing
    }

    private func shouldShowGoalies(
        _ detail: NHLGameDetail
    ) -> Bool {
        !isPregame
            || detail.awayGoalie != nil
            || detail.homeGoalie != nil
    }

    private func shouldShowGoalScorers(
        _ detail: NHLGameDetail
    ) -> Bool {
        !isPregame || !detail.goalScorers.isEmpty
    }

    private func shouldShowShots(
        _ detail: NHLGameDetail
    ) -> Bool {
        !isPregame || !detail.shotsByPeriod.isEmpty
    }

    private func visibleStatRows(
        _ detail: NHLGameDetail
    ) -> [NHLGameStatLine] {
        if game.status == .final {
            return detail.stats
        }

        return detail.stats.filter {
            hasValue($0.awayValue)
                || hasValue($0.homeValue)
        }
    }

    private func shouldShowStats(
        _ detail: NHLGameDetail
    ) -> Bool {
        game.status == .final
            || !visibleStatRows(detail).isEmpty
    }

    private func shouldShowScratches(
        _ detail: NHLGameDetail
    ) -> Bool {
        !isPregame
            || !detail.awayScratches.isEmpty
            || !detail.homeScratches.isEmpty
    }

    private func shouldShowLeaders(
        _ detail: NHLGameDetail
    ) -> Bool {
        if !isPregame {
            return true
        }

        return [
            detail.awayLeaders.goals,
            detail.awayLeaders.assists,
            detail.awayLeaders.points,
            detail.homeLeaders.goals,
            detail.homeLeaders.assists,
            detail.homeLeaders.points,
        ]
        .compactMap { $0 }
        .contains { hasValue($0) }
    }

    private func shouldShowSpecialTeams(
        _ detail: NHLGameDetail
    ) -> Bool {
        !isPregame
            || detail.specialTeams.state != nil
            || detail.specialTeams.awayPenaltiesTaken != nil
            || detail.specialTeams.homePenaltiesTaken != nil
    }

    private func shouldShowPenalties(
        _ detail: NHLGameDetail
    ) -> Bool {
        !isPregame || !detail.penalties.isEmpty
    }

    private func emptySemanticRow(
        _ text: String
    ) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(14)
    }

    private var seasonSeriesGames: [HockeyGame] {
        let targetTeams = Set([
            game.awayTeam.abbreviation.uppercased(),
            game.homeTeam.abbreviation.uppercased()
        ])
        let targetType = game.gameTypeId

        return allGames
            .filter { candidate in
                let candidateTeams = Set([
                    candidate.awayTeam.abbreviation.uppercased(),
                    candidate.homeTeam.abbreviation.uppercased()
                ])
                return candidateTeams == targetTeams
                    && candidate.gameTypeId == targetType
                    && candidate.leagueCode == game.leagueCode
            }
            .sorted { $0.startTime < $1.startTime }
    }

    private var gameTypeTitle: String {
        switch game.gameTypeId {
        case 1: "Preseason"
        case 2: "Regular Season"
        case 3: "Postseason"
        default: "Same Game Type"
        }
    }

    private func seriesResultText(_ game: HockeyGame) -> String {
        switch game.status {
        case .final, .live:
            if let away = game.awayScore, let home = game.homeScore {
                return "\(away)–\(home)"
            }
            return missing
        case .scheduled, .unknown:
            return game.startTime.formatted(date: .omitted, time: .shortened)
        case .postponed:
            return "PPD"
        }
    }

    private var statusBadgeText: String {
        switch game.status {
        case .scheduled:
            return game.startTime.formatted(date: .omitted, time: .shortened)
        case .live:
            if game.isIntermission == true {
                return "\(periodLabel ?? "") Int"
                    .trimmingCharacters(in: .whitespaces)
            }
            if let periodLabel,
               let time = game.timeRemaining,
               !time.isEmpty {
                return "\(periodLabel) · \(time)"
            }
            return periodLabel ?? "LIVE"
        case .final:
            return "FINAL"
        case .postponed:
            return "PPD"
        case .unknown:
            return game.startTime.formatted(date: .omitted, time: .shortened)
        }
    }

    private var periodLabel: String? {
        if game.periodType?.uppercased() == "OT" { return "OT" }
        if game.periodType?.uppercased() == "SO" { return "SO" }
        guard let period = game.periodNumber, period > 0 else { return nil }
        switch period {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(period)th"
        }
    }

    @MainActor
    private func loadDetail() async {
        guard supportsRichDetail else {
            detail = nil
            errorMessage = nil
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            detail = try await NHLGameDetailService().fetchDetail(for: game)
        } catch {
            detail = nil
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }

        isLoading = false
    }
}
