import SwiftUI
import Charts
import Foundation

struct StatsView: View {
    @StateObject private var viewModel: StatsViewModel
    @State private var selectedSection: StatsSection = .teamStats
    @State private var selectedTeamCode: String?
    @State private var hasInitializedTeamSelection = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var settings: AppSettingsStore

    @MainActor
    init(viewModel: StatsViewModel? = nil) {
        _viewModel = StateObject(
            wrappedValue: viewModel ?? StatsViewModel()
        )
    }

    var body: some View {
        Group {
            if let snapshot = viewModel.snapshot {
                content(snapshot)
            } else if viewModel.isLoading {
                ProgressView("Loading NHL stats…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView(
                    "Stats unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ContentUnavailableView(
                    "No stats data",
                    systemImage: "chart.bar.xaxis",
                    description: Text("No NHL stats snapshot is available yet.")
                )
            }
        }
        .navigationTitle("Stats")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
                .help("Refresh stats")
            }
        }
        .task(priority: .utility) {
            await viewModel.loadIfNeeded()
            initializeFavoriteTeamSelectionIfNeeded()
        }
        .onChange(of: viewModel.snapshot?.generatedAt) { _, _ in
            initializeFavoriteTeamSelectionIfNeeded()
        }
        .onChange(of: settings.favoriteTeamID) { _, _ in
            hasInitializedTeamSelection = false
            initializeFavoriteTeamSelectionIfNeeded()
        }
    }

    private func content(_ snapshot: StatsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            statsTopBar(snapshot)

            Group {
                switch selectedSection {
                case .teamStats:
                    TeamStatsPanel(
                        snapshot: snapshot,
                        selectedTeamCode: $selectedTeamCode
                    )
                case .gameStats:
                    GameStatsPanel(
                        snapshot: snapshot,
                        selectedTeamCode: $selectedTeamCode
                    )
                case .playerStats:
                    PlayerStatsPanel(
                        snapshot: snapshot,
                        viewModel: viewModel
                    )
                case .goalDifferential:
                    GoalDifferentialPanel(
                        snapshot: snapshot,
                        selectedTeamCode: $selectedTeamCode
                    )
                case .points:
                    PointsPanel(
                        snapshot: snapshot,
                        selectedTeamCode: $selectedTeamCode
                    )
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )

            HStack(spacing: 6) {
                Text("NHL")
                Text("•")
                    .foregroundStyle(.tertiary)
                Text(viewModel.updatedText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func statsTopBar(_ snapshot: StatsSnapshot) -> some View {
        if horizontalSizeClass == .compact {
            statsSectionPicker
        } else {
            ZStack(alignment: .trailing) {
                statsSectionPicker

                if selectedSection == .teamStats,
                   let selectedTeamCode,
                   let form = snapshot.recentForm(
                        teamCode: selectedTeamCode
                   ) {
                    RecentFormCard(
                        form: form,
                        inline: true
                    )
                    .frame(maxWidth: 330)
                }
            }
            .frame(
                maxWidth: .infinity,
                alignment: .top
            )
        }
    }

    private func initializeFavoriteTeamSelectionIfNeeded() {
        guard !hasInitializedTeamSelection,
              let snapshot = viewModel.snapshot else {
            return
        }

        hasInitializedTeamSelection = true

        guard let favoriteTeamID = settings.favoriteTeamID else {
            selectedTeamCode = nil
            return
        }

        let normalizedFavorite = favoriteTeamID.uppercased()

        selectedTeamCode = snapshot.teams.first {
            normalizedFavorite == $0.code.uppercased()
                || normalizedFavorite.hasSuffix(
                    "-\($0.code.uppercased())"
                )
        }?.code
    }

    private var statsSectionPicker: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                statsSectionButtons
            }
            .frame(maxWidth: .infinity, alignment: .center)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    statsSectionButtons
                }
                .padding(.horizontal, 1)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var statsSectionButtons: some View {
        ForEach(StatsSection.allCases) { section in
            Button {
                selectedSection = section
            } label: {
                Text(
                    horizontalSizeClass == .compact
                        ? section.compactTitle
                        : section.title
                )
                    .font(
                        (horizontalSizeClass == .compact ? Font.caption : Font.subheadline)
                            .weight(.semibold)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .buttonStyle(
                StatsTabButtonStyle(
                    isSelected: selectedSection == section
                )
            )
        }
    }

}

private enum StatsSection: String, CaseIterable, Identifiable {
    case teamStats
    case gameStats
    case playerStats
    case goalDifferential
    case points

    var id: String { rawValue }

    var title: String {
        switch self {
        case .teamStats: "Team Stats"
        case .gameStats: "Game Stats"
        case .playerStats: "Player Stats"
        case .goalDifferential: "Goal Differential"
        case .points: "Points"
        }
    }

    var compactTitle: String {
        switch self {
        case .teamStats: "Team"
        case .gameStats: "Game"
        case .playerStats: "Player"
        case .goalDifferential: "Goal Δ"
        case .points: "Points"
        }
    }
}

private struct StatsTabButtonStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, horizontalSizeClass == .compact ? 8 : 12)
            .padding(.vertical, horizontalSizeClass == .compact ? 6 : 7)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                isSelected
                    ? Color.accentColor
                    : Color.primary.opacity(configuration.isPressed ? 0.10 : 0.055),
                in: Capsule()
            )
    }
}

private struct StatsPhasePicker: View {
    @Binding var selection: StatsPhase
    let phases: [StatsPhase]

    var body: some View {
        Picker("Phase", selection: $selection) {
            ForEach(phases) { phase in
                Text(phase.title).tag(phase)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 520)
    }
}

private struct StatsPanelHeader: View {
    let title: String
    @Binding var selection: StatsPhase
    let phases: [StatsPhase]

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .compact {
            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .center)

                StatsPhasePicker(
                    selection: $selection,
                    phases: phases
                )
            }
        } else {
            HStack(spacing: 14) {
                Text(title)
                    .font(.title2.bold())

                StatsPhasePicker(
                    selection: $selection,
                    phases: phases
                )
                .frame(maxWidth: 420)

                Spacer(minLength: 0)
            }
        }
    }
}

private struct TeamStatsPanel: View {
    let snapshot: StatsSnapshot
    @Binding var selectedTeamCode: String?
    @State private var phase: StatsPhase = .regular
    @State private var sortKey: TeamSortKey = .team
    @State private var descending = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var phases: [StatsPhase] {
        snapshot.availablePhases.isEmpty ? [.preseason] : snapshot.availablePhases
    }

    private var rows: [TeamStatsRow] {
        let source = snapshot.teamStats(for: phase)
        return source.sorted { lhs, rhs in
            descending
                ? isOrderedBefore(rhs, lhs)
                : isOrderedBefore(lhs, rhs)
        }
    }

    private func isOrderedBefore(
        _ lhs: TeamStatsRow,
        _ rhs: TeamStatsRow
    ) -> Bool {
        switch sortKey {
        case .team:
            return lhs.teamCode < rhs.teamCode
        case .record:
            let left = (lhs.pts, lhs.winPercentage, lhs.gd, lhs.gf)
            let right = (rhs.pts, rhs.winPercentage, rhs.gd, rhs.gf)
            return left == right ? lhs.teamCode < rhs.teamCode : left < right
        case .gp:
            return lhs.gp == rhs.gp ? lhs.teamCode < rhs.teamCode : lhs.gp < rhs.gp
        case .w:
            return lhs.w == rhs.w ? lhs.teamCode < rhs.teamCode : lhs.w < rhs.w
        case .l:
            return lhs.l == rhs.l ? lhs.teamCode < rhs.teamCode : lhs.l < rhs.l
        case .pts:
            return lhs.pts == rhs.pts ? lhs.teamCode < rhs.teamCode : lhs.pts < rhs.pts
        case .gf:
            return lhs.gf == rhs.gf ? lhs.teamCode < rhs.teamCode : lhs.gf < rhs.gf
        case .ga:
            return lhs.ga == rhs.ga ? lhs.teamCode < rhs.teamCode : lhs.ga < rhs.ga
        case .gd:
            return lhs.gd == rhs.gd ? lhs.teamCode < rhs.teamCode : lhs.gd < rhs.gd
        case .pointsPercentage:
            return lhs.pointsPercentage == rhs.pointsPercentage
                ? lhs.teamCode < rhs.teamCode
                : lhs.pointsPercentage < rhs.pointsPercentage
        case .winPercentage:
            return lhs.winPercentage == rhs.winPercentage
                ? lhs.teamCode < rhs.teamCode
                : lhs.winPercentage < rhs.winPercentage
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            teamHeader

            TeamStatsTable(
                snapshot: snapshot,
                rows: rows,
                sortKey: sortKey,
                descending: descending,
                compact: horizontalSizeClass == .compact,
                selectedTeamCode: $selectedTeamCode,
                onSort: sort
            )
        }
        .onAppear {
            normalizePhase()
        }
        .onChange(of: snapshot.generatedAt) { _, _ in
            normalizePhase()
        }
    }

    @ViewBuilder
    private var teamHeader: some View {
        let form = selectedTeamCode.flatMap {
            snapshot.recentForm(teamCode: $0)
        }

        VStack(spacing: 8) {
            StatsPanelHeader(
                title: "Team Stats",
                selection: $phase,
                phases: phases
            )

            if horizontalSizeClass == .compact,
               let form {
                RecentFormCard(form: form)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func normalizePhase() {
        if !phases.contains(phase) {
            phase = snapshot.defaultPhase
        }
    }

    private func sort(_ key: TeamSortKey) {
        if sortKey == key {
            descending.toggle()
        } else {
            sortKey = key
            descending = key != .team
        }
    }
}

private enum TeamSortKey: String, CaseIterable {
    case team
    case record
    case gp
    case w
    case l
    case pts
    case gf
    case ga
    case gd
    case pointsPercentage
    case winPercentage

    var label: String {
        switch self {
        case .team: "Team"
        case .record: "RECORD"
        case .gp: "GP"
        case .w: "W"
        case .l: "L"
        case .pts: "PTS"
        case .gf: "GF"
        case .ga: "GA"
        case .gd: "GD"
        case .pointsPercentage: "P%"
        case .winPercentage: "W%"
        }
    }
}

private struct TeamStatsTable: View {
    let snapshot: StatsSnapshot
    let rows: [TeamStatsRow]
    let sortKey: TeamSortKey
    let descending: Bool
    let compact: Bool
    @Binding var selectedTeamCode: String?
    let onSort: (TeamSortKey) -> Void

    private let rowHeight: CGFloat = 40
    private var teamWidth: CGFloat { compact ? 82 : 94 }

    private var columns: [FrozenGridColumn<TeamSortKey>] {
        if compact {
            // RECORD already contains W-L-OT, so omit the redundant W/L
            // columns on iPhone and size every remaining column to its text.
            return [
                // Keep the iPhone table dense, but never squeeze values into
                // each other. Horizontal scrolling is preferable to clipping.
                FrozenGridColumn(id: .record, width: 86),
                FrozenGridColumn(id: .gp, width: 42),
                FrozenGridColumn(id: .pts, width: 46),
                FrozenGridColumn(id: .gf, width: 42),
                FrozenGridColumn(id: .ga, width: 42),
                FrozenGridColumn(id: .gd, width: 46),
                FrozenGridColumn(id: .pointsPercentage, width: 62),
                FrozenGridColumn(id: .winPercentage, width: 62),
            ]
        }

        return [
            FrozenGridColumn(id: .record, width: 102),
            FrozenGridColumn(id: .gp, width: 60),
            FrozenGridColumn(id: .w, width: 60),
            FrozenGridColumn(id: .l, width: 60),
            FrozenGridColumn(id: .pts, width: 64),
            FrozenGridColumn(id: .gf, width: 60),
            FrozenGridColumn(id: .ga, width: 60),
            FrozenGridColumn(id: .gd, width: 60),
            FrozenGridColumn(id: .pointsPercentage, width: 72),
            FrozenGridColumn(id: .winPercentage, width: 72),
        ]
    }

    var body: some View {
        FrozenDataGrid(
            rows: rows,
            columns: columns,
            rowHeaderWidth: teamWidth,
            rowHeight: rowHeight,
            headerHeight: rowHeight
        ) {
            header(.team)
        } header: { column in
            header(column.id)
        } rowHeader: { row in
            Button {
                selectedTeamCode =
                    selectedTeamCode == row.teamCode
                    ? nil
                    : row.teamCode
            } label: {
                HStack(spacing: 5) {
                    StatsTeamLogo(
                        team: snapshot.team(for: row.teamCode),
                        size: 22
                    )
                    Text(row.teamCode)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
                .overlay {
                    selectedTeamCode == row.teamCode
                        ? Color.accentColor.opacity(0.12)
                        : Color.primary.opacity(0.025)
                }
                .overlay(alignment: .bottom) {
                    tableHorizontalHairline
                }
            }
            .buttonStyle(.plain)
        } cell: { row, column in
            statCell(row, key: column.id)
        }
        .clipShape(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private func header(_ key: TeamSortKey) -> some View {
        Button {
            onSort(key)
        } label: {
            HStack(spacing: 3) {
                Text(key.label)
                if sortKey == key {
                    Image(
                        systemName: descending
                            ? "chevron.down"
                            : "chevron.up"
                    )
                    .font(.system(size: 8, weight: .bold))
                }
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primary.opacity(0.055))
            .overlay(alignment: .leading) {
                if key != .team {
                    tableVerticalHairline
                }
            }
            .overlay(alignment: .bottom) {
                tableHorizontalHairline
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func statCell(
        _ row: TeamStatsRow,
        key: TeamSortKey
    ) -> some View {
        let values = rows.compactMap {
            numericValue($0, key: key)
        }
        let low = values.min() ?? 0
        let high = values.max() ?? low
        let inverse = key == .l || key == .ga

        Text(textValue(row, key: key))
            .font(.system(.caption, design: .monospaced).weight(.medium))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                heatColor(
                    value: numericValue(row, key: key),
                    low: low,
                    high: high,
                    inverse: inverse
                )
            )
            .overlay(alignment: .leading) {
                tableVerticalHairline
            }
            .overlay(alignment: .bottom) {
                tableHorizontalHairline
            }
    }

    private func textValue(
        _ row: TeamStatsRow,
        key: TeamSortKey
    ) -> String {
        switch key {
        case .team: row.teamCode
        case .record: row.record
        case .gp: String(row.gp)
        case .w: String(row.w)
        case .l: String(row.l)
        case .pts: String(row.pts)
        case .gf: String(row.gf)
        case .ga: String(row.ga)
        case .gd: String(row.gd)
        case .pointsPercentage:
            row.pointsPercentage.formatted(
                .percent.precision(.fractionLength(1))
            )
        case .winPercentage:
            row.winPercentage.formatted(
                .percent.precision(.fractionLength(1))
            )
        }
    }

    private func numericValue(
        _ row: TeamStatsRow,
        key: TeamSortKey
    ) -> Double? {
        switch key {
        case .team, .record: nil
        case .gp: Double(row.gp)
        case .w: Double(row.w)
        case .l: Double(row.l)
        case .pts: Double(row.pts)
        case .gf: Double(row.gf)
        case .ga: Double(row.ga)
        case .gd: Double(row.gd)
        case .pointsPercentage: row.pointsPercentage
        case .winPercentage: row.winPercentage
        }
    }

    private func heatColor(
        value: Double?,
        low: Double,
        high: Double,
        inverse: Bool
    ) -> Color {
        guard let value, high > low else {
            return Color.primary.opacity(0.018)
        }

        var rank = (value - low) / (high - low)
        if inverse {
            rank = 1 - rank
        }

        return Color.accentColor.opacity(
            0.025 + (0.14 * rank)
        )
    }
}

private struct RecentFormCard: View {
    let form: RecentForm
    var inline = false

    var body: some View {
        Group {
            if inline {
                HStack(spacing: 8) {
                    Text(form.title)
                        .font(.caption.weight(.bold))

                    Text(form.lines.joined(separator: "  •  "))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text(form.title)
                        .font(.subheadline.bold())

                    ForEach(form.lines, id: \.self) { line in
                        Text(line)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            .thinMaterial,
            in: RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
        )
    }
}

private struct GameStatsPanel: View {
    let snapshot: StatsSnapshot
    @Binding var selectedTeamCode: String?
    @State private var phase: StatsPhase = .regular

    private var phases: [StatsPhase] {
        snapshot.availablePhases.isEmpty ? [.preseason] : snapshot.availablePhases
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatsPanelHeader(
                title: "Game Stats",
                selection: $phase,
                phases: phases
            )

            if let table = snapshot.gameStats(for: phase) {
                GameStatsTableView(
                    snapshot: snapshot,
                    table: table,
                    selectedTeamCode: $selectedTeamCode
                )
            } else {
                ContentUnavailableView(
                    "Game stats unavailable",
                    systemImage: "calendar",
                    description: Text("There are no games in this phase yet.")
                )
            }
        }
        .onAppear { normalizePhase() }
        .onChange(of: snapshot.generatedAt) { _, _ in normalizePhase() }
    }

    private func normalizePhase() {
        if !phases.contains(phase) {
            phase = snapshot.defaultPhase
        }
    }
}

private struct GameStatsTableView: View {
    let snapshot: StatsSnapshot
    let table: GameStatsTable
    @Binding var selectedTeamCode: String?

    private let rowHeight: CGFloat = 40
    private let teamWidth: CGFloat = 94
    private let dateWidth: CGFloat = 64

    private var todayIndex: Int {
        statsTodayColumnIndex(table.columns)
    }

    private var teams: [StatsTeam] {
        snapshot.teams
            .filter { table.rows[$0.code] != nil }
            .sorted { lhs, rhs in
                let left = rankedOutcome(lhs.code)
                let right = rankedOutcome(rhs.code)
                return left == right ? lhs.name < rhs.name : left > right
            }
    }

    private var columns: [FrozenGridColumn<String>] {
        table.columns.map { FrozenGridColumn(id: $0, width: dateWidth) }
    }

    var body: some View {
        FrozenDataGrid(
            rows: teams,
            columns: columns,
            rowHeaderWidth: teamWidth,
            rowHeight: rowHeight,
            headerHeight: rowHeight,
            initialColumnID: table.columns.indices.contains(todayIndex)
                ? table.columns[todayIndex]
                : table.columns.last
        ) {
            Text("Team")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.primary.opacity(0.055))
                .overlay(alignment: .bottom) { tableHorizontalHairline }
        } header: { column in
            Text(displayDay(column.id))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.primary.opacity(0.055))
                .overlay(alignment: .leading) { tableVerticalHairline }
                .overlay(alignment: .bottom) { tableHorizontalHairline }
        } rowHeader: { team in
            Button {
                selectedTeamCode = selectedTeamCode == team.code ? nil : team.code
            } label: {
                HStack(spacing: 5) {
                    StatsTeamLogo(team: team, size: 22)
                    Text(team.code)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
                .overlay {
                    selectedTeamCode == team.code
                        ? Color.accentColor.opacity(0.12)
                        : Color.primary.opacity(0.025)
                }
                .overlay(alignment: .bottom) { tableHorizontalHairline }
            }
            .buttonStyle(.plain)
        } cell: { team, column in
            let result = table.result(teamCode: team.code, day: column.id) ?? ""

            Text(result)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(resultColor(result))
                .overlay(alignment: .leading) { tableVerticalHairline }
                .overlay(alignment: .bottom) { tableHorizontalHairline }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private func rankedOutcome(_ teamCode: String) -> Int {
        guard !table.columns.isEmpty else { return 0 }

        for index in stride(
            from: min(todayIndex, table.columns.count - 1),
            through: 0,
            by: -1
        ) {
            let result = table.result(
                teamCode: teamCode,
                day: table.columns[index]
            ) ?? ""

            let rank: Int
            switch result {
            case "W": rank = 6
            case "OTW": rank = 5
            case "SOW": rank = 4
            case "SOL": rank = 3
            case "OTL": rank = 2
            case "L": rank = 1
            default: rank = 0
            }

            if rank > 0 { return rank }
        }

        return 0
    }

    private func resultColor(_ result: String) -> Color {
        let rank: Double
        switch result {
        case "W": rank = 1.0
        case "OTW": rank = 0.84
        case "SOW": rank = 0.70
        case "SOL": rank = 0.52
        case "OTL": rank = 0.36
        case "L": rank = 0.18
        default: return Color.primary.opacity(0.015)
        }

        return Color.accentColor.opacity(0.035 + rank * 0.16)
    }
}

private struct PlayerStatsPanel: View {
    let snapshot: StatsSnapshot
    @ObservedObject var viewModel: StatsViewModel
    @State private var phase: StatsPhase = .regular
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var phases: [StatsPhase] {
        snapshot.availablePhases.isEmpty ? [snapshot.defaultPhase] : snapshot.availablePhases
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatsPanelHeader(
                title: "Player Stats",
                selection: $phase,
                phases: phases
            )

            if viewModel.loadingPlayerPhases.contains(phase) {
                ProgressView("Loading player leaders…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let data = viewModel.playerStats[phase],
                      !data.skaters.isEmpty || !data.goalies.isEmpty {
                if horizontalSizeClass == .compact {
                    ScrollView(.vertical) {
                        VStack(spacing: 14) {
                            PlayerCategoryPanel(
                                title: "Skaters",
                                players: data.skaters,
                                options: ["All", "Goals", "Assists", "Points", "Hits", "Blocks", "+/-", "PIM"],
                                allStats: ["Goals", "Assists", "Points"],
                                snapshot: snapshot
                            )
                            PlayerCategoryPanel(
                                title: "Goalies",
                                players: data.goalies,
                                options: ["All", "Wins", "Save %", "Shutouts", "Saves / GS", "GAA"],
                                allStats: ["Wins", "Save %", "Shutouts"],
                                snapshot: snapshot
                            )
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        PlayerCategoryPanel(
                            title: "Skaters",
                            players: data.skaters,
                            options: ["All", "Goals", "Assists", "Points", "Hits", "Blocks", "+/-", "PIM"],
                            allStats: ["Goals", "Assists", "Points"],
                            snapshot: snapshot
                        )
                        PlayerCategoryPanel(
                            title: "Goalies",
                            players: data.goalies,
                            options: ["All", "Wins", "Save %", "Shutouts", "Saves / GS", "GAA"],
                            allStats: ["Wins", "Save %", "Shutouts"],
                            snapshot: snapshot
                        )
                    }
                }
            } else if let message = viewModel.playerErrorMessage {
                ContentUnavailableView(
                    "Player stats unavailable",
                    systemImage: "person.crop.rectangle.stack",
                    description: Text(message)
                )
            } else {
                ContentUnavailableView(
                    "No player stats",
                    systemImage: "person.crop.rectangle.stack",
                    description: Text("No NHL player leaders are available for this phase yet.")
                )
            }
        }
        .onAppear {
            phase = phases.contains(.regular)
                ? .regular
                : (
                    phases.contains(snapshot.defaultPhase)
                        ? snapshot.defaultPhase
                        : (phases.first ?? .regular)
                )
            Task(priority: .utility) { await viewModel.loadPlayers(for: phase) }
        }
        .onChange(of: phase) { _, newPhase in
            Task { await viewModel.loadPlayers(for: newPhase) }
        }
    }
}

private struct PlayerCategoryPanel: View {
    let title: String
    let players: [PlayerStatLine]
    let options: [String]
    let allStats: [String]
    let snapshot: StatsSnapshot
    @State private var selectedStat = "All"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title3.bold())
                Spacer()
                Picker("Stat", selection: $selectedStat) {
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 170)
            }

            if selectedStat == "All" {
                ForEach(allStats, id: \.self) { stat in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(stat)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(topPlayers(for: stat, limit: 5)) { player in
                                    PlayerLeaderCard(
                                        player: player,
                                        stat: stat,
                                        snapshot: snapshot
                                    )
                                }
                            }
                        }
                    }
                }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(topPlayers(for: selectedStat, limit: 25)) { player in
                        PlayerLeaderRow(
                            player: player,
                            stat: selectedStat,
                            snapshot: snapshot
                        )
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func topPlayers(for stat: String, limit: Int) -> [PlayerStatLine] {
        Array(
            players.sorted {
                if $0.value(stat) == $1.value(stat) {
                    return $0.name < $1.name
                }
                return $0.value(stat) > $1.value(stat)
            }.prefix(limit)
        )
    }
}

private struct PlayerLeaderCard: View {
    let player: PlayerStatLine
    let stat: String
    let snapshot: StatsSnapshot

    var body: some View {
        VStack(spacing: 8) {
            PlayerPortrait(player: player, snapshot: snapshot, size: 94)

            Text(player.name)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 140)

            Text(formatPlayerValue(player.value(stat), stat: stat))
                .font(.title2.bold())
        }
        .padding(12)
        .frame(width: 160)
        .frame(minHeight: 186)
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
}

private struct PlayerLeaderRow: View {
    let player: PlayerStatLine
    let stat: String
    let snapshot: StatsSnapshot

    var body: some View {
        HStack(spacing: 10) {
            PlayerPortrait(player: player, snapshot: snapshot, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(.subheadline.weight(.semibold))
                Text(player.teamCode)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(formatPlayerValue(player.value(stat), stat: stat))
                .font(.system(.subheadline, design: .monospaced).weight(.bold))
        }
        .padding(.vertical, 7)
    }
}

private struct PlayerPortrait: View {
    let player: PlayerStatLine
    let snapshot: StatsSnapshot
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AsyncImage(url: headshotURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Image(systemName: "person.crop.square")
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.18)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))

            StatsTeamLogo(team: snapshot.team(for: player.teamCode), size: size * 0.36)
                .padding(2)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    private var headshotURL: URL? {
        guard player.playerID > 0, !player.teamCode.isEmpty else { return nil }
        let seasonID = snapshot.season.replacingOccurrences(of: "-", with: "")
        return URL(
            string: "https://assets.nhle.com/mugs/nhl/\(seasonID)/\(player.teamCode)/\(player.playerID).png"
        )
    }
}

private func formatPlayerValue(_ value: Double, stat: String) -> String {
    switch stat {
    case "Save %":
        return String(format: "%.3f", value)
    case "Saves / GS", "GAA":
        return String(format: "%.2f", value)
    default:
        return String(Int(value.rounded()))
    }
}

private struct PointsPanel: View {
    let snapshot: StatsSnapshot
    @Binding var selectedTeamCode: String?
    @State private var phase: StatsPhase = .regular

    private var phases: [StatsPhase] {
        snapshot.availablePhases.isEmpty
            ? [snapshot.defaultPhase]
            : snapshot.availablePhases
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatsPanelHeader(
                title: "Points",
                selection: $phase,
                phases: phases
            )

            if let table = snapshot.pointsHistory(for: phase) {
                HistoryStatsPanel(
                    title: "Points",
                    table: table,
                    teams: snapshot.teams,
                    selectedTeamCode: $selectedTeamCode,
                    allowNegative: false
                )
            } else {
                ContentUnavailableView(
                    "Points unavailable",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Points history is not available for this phase yet.")
                )
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .onAppear {
            phase = phases.contains(.regular)
                ? .regular
                : (
                    phases.contains(snapshot.defaultPhase)
                        ? snapshot.defaultPhase
                        : (phases.first ?? .regular)
                )
        }
        .onChange(of: snapshot.generatedAt) { _, _ in
            if !phases.contains(phase) {
                phase = phases.contains(.regular)
                    ? .regular
                    : (
                        phases.contains(snapshot.defaultPhase)
                            ? snapshot.defaultPhase
                            : (phases.first ?? .regular)
                    )
            }
        }
    }
}

private struct GoalDifferentialPanel: View {
    let snapshot: StatsSnapshot
    @Binding var selectedTeamCode: String?
    @State private var phase: StatsPhase = .regular

    private var phases: [StatsPhase] {
        snapshot.availablePhases.isEmpty ? [snapshot.defaultPhase] : snapshot.availablePhases
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatsPanelHeader(
                title: "Goal Differential",
                selection: $phase,
                phases: phases
            )

            if let table = snapshot.goalDifferentialHistory(for: phase) {
                HistoryStatsPanel(
                    title: "Goal Differential",
                    table: table,
                    teams: snapshot.teams,
                    selectedTeamCode: $selectedTeamCode,
                    allowNegative: true
                )
            } else {
                ContentUnavailableView(
                    "Goal differential unavailable",
                    systemImage: "chart.xyaxis.line",
                    description: Text("There are no games in this phase yet.")
                )
            }
        }
        .onAppear {
            phase = phases.contains(.regular)
                ? .regular
                : (
                    phases.contains(snapshot.defaultPhase)
                        ? snapshot.defaultPhase
                        : (phases.first ?? .regular)
                )
        }
    }
}

private struct HistoryStatsPanel: View {
    let title: String
    let table: StatsHistoryTable
    let teams: [StatsTeam]
    @Binding var selectedTeamCode: String?
    let allowNegative: Bool

    private let rowHeight: CGFloat = 38
    private let teamWidth: CGFloat = 94
    private let dateWidth: CGFloat = 62

    private var todayIndex: Int {
        statsTodayColumnIndex(table.columns)
    }

    private var visibleTeams: [StatsTeam] {
        teams
            .filter { table.rows[$0.code] != nil }
            .sorted { lhs, rhs in
                let left = rankedValue(lhs.code)
                let right = rankedValue(rhs.code)
                return left == right ? lhs.name < rhs.name : left > right
            }
    }

    private var columns: [FrozenGridColumn<Int>] {
        table.columns.indices.map { FrozenGridColumn(id: $0, width: dateWidth) }
    }

    private var graphSeries: [TimelineGraphSeries] {
        visibleTeams.map { team in
            TimelineGraphSeries(
                id: team.code,
                color: Color(hex: team.colorHex),
                values: carriedValues(for: team.code),
                lineWidth: lineWidth(team),
                opacity: lineOpacity(team)
            )
        }
    }
    private var yDomain: (Double, Double) {
        let values = visibleTeams.flatMap {
            (table.rows[$0.code] ?? []).compactMap { $0 }
        }

        guard let low = values.min(), let high = values.max() else {
            return (0, 1)
        }

        if low == high {
            return allowNegative
                ? (low - 1, high + 1)
                : (max(0, low - 1), high + 1)
        }

        return (low, high)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            graph

            FrozenDataGrid(
                rows: visibleTeams,
                columns: columns,
                rowHeaderWidth: teamWidth,
                rowHeight: rowHeight,
                headerHeight: rowHeight,
                initialColumnID: todayIndex
            ) {
                Text("Team")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.055))
                    .overlay(alignment: .bottom) { tableHorizontalHairline }
            } header: { column in
                Text(displayHistoryDate(table.columns[column.id]))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.055))
                    .overlay(alignment: .leading) { tableVerticalHairline }
                    .overlay(alignment: .bottom) { tableHorizontalHairline }
            } rowHeader: { team in
                Button {
                    selectedTeamCode = selectedTeamCode == team.code ? nil : team.code
                } label: {
                    HStack(spacing: 5) {
                        StatsTeamLogo(team: team, size: 21)
                        Text(team.code)
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
                    .overlay {
                        selectedTeamCode == team.code
                            ? Color(hex: team.colorHex).opacity(0.16)
                            : Color.primary.opacity(0.025)
                    }
                    .overlay(alignment: .bottom) { tableHorizontalHairline }
                }
                .buttonStyle(.plain)
            } cell: { team, column in
                let bounds = columnBounds(column.id)
                let value = displayValue(
                    teamCode: team.code,
                    columnIndex: column.id
                )

                Text(formatHistoryValue(value))
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        historyHeatColor(
                            value: value,
                            low: bounds.low,
                            high: bounds.high
                        )
                    )
                    .overlay(alignment: .leading) { tableVerticalHairline }
                    .overlay(alignment: .bottom) { tableHorizontalHairline }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            }
        }
    }

    private var graph: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let selectedTeamCode,
                   let selected = visibleTeams.first(where: { $0.code == selectedTeamCode }) {
                    StatsTeamLogo(team: selected, size: 26)
                    Text("\(selected.name) — \(title)")
                        .font(.headline)
                } else {
                    Text("All Teams — \(title)")
                        .font(.headline)
                }

                Spacer()

                if selectedTeamCode != nil {
                    Button("All Teams") {
                        self.selectedTeamCode = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            AlignedTimelineGraph(
                labels: table.columns.map(displayHistoryDate),
                series: graphSeries,
                leadingWidth: teamWidth,
                columnWidth: dateWidth,
                yMin: yDomain.0,
                yMax: yDomain.1,
                initialColumnIndex: todayIndex,
                height: 250,
                showXLabels: false
            ) { value in
                String(Int(value.rounded()))
            }
        }
        .padding(12)
        .background(
            .thinMaterial,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private func rankedValue(_ teamCode: String) -> Double {
        guard let values = table.rows[teamCode], !values.isEmpty else {
            return -Double.greatestFiniteMagnitude
        }

        for index in stride(
            from: min(todayIndex, values.count - 1),
            through: 0,
            by: -1
        ) {
            if let value = values[index] { return value }
        }

        return -Double.greatestFiniteMagnitude
    }

    private func lineWidth(_ team: StatsTeam) -> CGFloat {
        guard let selectedTeamCode else { return 1.6 }
        return selectedTeamCode == team.code ? 3.6 : 1.0
    }

    private func lineOpacity(_ team: StatsTeam) -> Double {
        guard let selectedTeamCode else { return 0.88 }
        return selectedTeamCode == team.code ? 1.0 : 0.22
    }

    private func carriedValues(for teamCode: String) -> [Double?] {
        guard let raw = table.rows[teamCode] else { return [] }

        var lastValue: Double?
        return raw.map { value in
            if let value {
                lastValue = value
                return value
            }
            return lastValue
        }
    }

    private func displayValue(
        teamCode: String,
        columnIndex: Int
    ) -> Double? {
        let values = carriedValues(for: teamCode)
        guard values.indices.contains(columnIndex) else { return nil }
        return values[columnIndex]
    }

    private func columnBounds(_ index: Int) -> (low: Double, high: Double) {
        let values = visibleTeams.compactMap {
            displayValue(teamCode: $0.code, columnIndex: index)
        }
        return (values.min() ?? 0, values.max() ?? 0)
    }
    private func historyHeatColor(
        value: Double?,
        low: Double,
        high: Double
    ) -> Color {
        guard let value else { return .clear }
        guard high > low else { return Color.accentColor.opacity(0.07) }

        let rank = (value - low) / (high - low)
        let base = allowNegative && value < 0 ? 0.025 : 0.04
        return Color.accentColor.opacity(base + rank * 0.16)
    }

    private func formatHistoryValue(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(Int(value.rounded()))
    }
}

private func statsTodayColumnIndex(_ columns: [String]) -> Int {
    guard !columns.isEmpty else { return 0 }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current

    let now = Date()
    let month = calendar.component(.month, from: now)
    let day = calendar.component(.day, from: now)

    for (index, raw) in columns.enumerated() {
        let pieces = raw.split(separator: "/")
        guard pieces.count == 2,
              let rawMonth = Int(pieces[0]),
              let rawDay = Int(pieces[1]) else {
            continue
        }

        if rawMonth == month && rawDay == day {
            return index
        }
    }

    return columns.count - 1
}

private struct StatsTeamLogo: View {
    let team: StatsTeam?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: team?.logoURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            default:
                Image(systemName: "hockey.puck.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

private func displayDay(_ raw: String) -> String {
    let parts = raw.split(separator: "-")
    guard parts.count == 3,
          let month = Int(parts[1]),
          let day = Int(parts[2]) else {
        return raw
    }
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.year = Int(parts[0])
    components.month = month
    components.day = day
    guard let date = components.date else { return raw }
    return date.formatted(
        .dateTime.day().month(.abbreviated).locale(Locale(identifier: "en_GB"))
    )
}

private func displayHistoryDate(_ raw: String) -> String {
    let pieces = raw.split(separator: "/")
    guard pieces.count == 2,
          let month = Int(pieces[0]),
          let day = Int(pieces[1]) else {
        return raw
    }

    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_GB")
    guard let date = calendar.date(
        from: DateComponents(year: 2000, month: month, day: day)
    ) else {
        return raw
    }

    return date.formatted(
        .dateTime
            .day()
            .month(.abbreviated)
            .locale(Locale(identifier: "en_GB"))
    )
}

private var tableVerticalHairline: some View {
    Rectangle()
        .fill(.quaternary)
        .frame(width: 1)
}

private var tableHorizontalHairline: some View {
    Rectangle()
        .fill(.quaternary)
        .frame(height: 1)
}

#Preview {
    NavigationStack {
        StatsView()
    }
}
