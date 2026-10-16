import SwiftUI
import Charts
import Foundation

/// Consistent good/neutral/bad coloring without changing the user's accent.
enum StatsPerformancePalette {
    static let good = Color(red: 0.12, green: 0.52, blue: 0.88)
    static let bad = Color(red: 0.90, green: 0.24, blue: 0.30)
    static let neutral = Color(red: 0.49, green: 0.52, blue: 0.56)

    /// Continuous bad > neutral gray > good, even if the team accent is red.
    static func relative(_ value: Double) -> Color {
        let rank = min(1.0, max(0.0, value))
        let amount = abs(rank - 0.5) * 2.0
        let gray = (r: 0.49, g: 0.52, b: 0.56)
        let target = rank >= 0.5
            ? (r: 0.12, g: 0.52, b: 0.88)
            : (r: 0.90, g: 0.24, b: 0.30)
        return Color(
            red: gray.r + (target.r - gray.r) * amount,
            green: gray.g + (target.g - gray.g) * amount,
            blue: gray.b + (target.b - gray.b) * amount
        ).opacity(0.30)
    }

    static func signed(_ value: Double, extent: Double) -> Color {
        let limit = max(1.0, extent)
        return relative(0.5 + 0.5 * min(1.0, max(-1.0, value / limit)))
    }
}

struct StatsView: View {
    @StateObject private var viewModel: StatsViewModel
    @State private var selectedSection: StatsSection = .teamStats
    @AppStorage("iceometrics.stats.section") private var savedSection = "teamStats"
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
        .onAppear {
            selectedSection = StatsSection(rawValue: savedSection) ?? .teamStats
        }
        .onChange(of: selectedSection) { _, newSection in
            savedSection = newSection.rawValue
        }
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
    @Environment(\.iceometricsAccentForegroundColor) private var accentForegroundColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, horizontalSizeClass == .compact ? 8 : 12)
            .padding(.vertical, horizontalSizeClass == .compact ? 6 : 7)
            .foregroundStyle(isSelected ? accentForegroundColor : Color.primary)
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
    // ICEOMETRICS_NOTES_BATCH01_SORT_V1
    let snapshot: StatsSnapshot
    @Binding var selectedTeamCode: String?
    @State private var phase: StatsPhase = .regular
    @State private var sortKey: TeamSortKey = .pointsPercentage
    @State private var descending = true
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.iceometricsFavoritePaletteTeamCode) private var favoritePaletteTeamCode

    private let rowHeight: CGFloat = 36
    private var teamWidth: CGFloat { compact ? 76 : 82 }

    private var columns: [FrozenGridColumn<TeamSortKey>] {
        if compact {
            // RECORD already contains W-L-OT, so omit the redundant W/L
            // columns on iPhone and size every remaining column to its text.
            return [
                // Keep the iPhone table dense, but never squeeze values into
                // each other. Horizontal scrolling is preferable to clipping.
                FrozenGridColumn(id: .record, width: 84),
                FrozenGridColumn(id: .gp, width: 40),
                FrozenGridColumn(id: .pts, width: 44),
                FrozenGridColumn(id: .gf, width: 40),
                FrozenGridColumn(id: .ga, width: 40),
                FrozenGridColumn(id: .gd, width: 44),
                FrozenGridColumn(id: .pointsPercentage, width: 58),
                FrozenGridColumn(id: .winPercentage, width: 58),
            ]
        }

        return [
            FrozenGridColumn(id: .record, width: 92),
            FrozenGridColumn(id: .gp, width: 44),
            FrozenGridColumn(id: .w, width: 42),
            FrozenGridColumn(id: .l, width: 42),
            FrozenGridColumn(id: .pts, width: 44),
            FrozenGridColumn(id: .gf, width: 42),
            FrozenGridColumn(id: .ga, width: 42),
            FrozenGridColumn(id: .gd, width: 42),
            FrozenGridColumn(id: .pointsPercentage, width: 60),
            FrozenGridColumn(id: .winPercentage, width: 60),
        ]
    }

    var body: some View {
        // One min/max per metric rather than a full-team scan in every cell.
        let performanceRanges: [TeamSortKey: (low: Double, high: Double)] =
            Dictionary(uniqueKeysWithValues: TeamSortKey.allCases.map { key in
                let values = rows.compactMap { numericValue($0, key: key) }
                return (key, (low: values.min() ?? 0, high: values.max() ?? 0))
            })

        return FrozenDataGrid(
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
                HStack(spacing: 4) {
                    StatsTeamLogo(
                        team: snapshot.team(for: row.teamCode),
                        size: 22
                    )
                    Text(row.teamCode)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 3)
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
            let bounds = performanceRanges[column.id] ?? (low: 0, high: 0)
            statCell(row, key: column.id, low: bounds.low, high: bounds.high)
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
        key: TeamSortKey,
        low: Double,
        high: Double
    ) -> some View {
        let inverse = key == .l || key == .ga

        Text(textValue(row, key: key))
            .font(.system(.caption, design: .monospaced).weight(.medium))
            .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                heatColor(
                    teamCode: favoritePaletteTeamCode ?? "",
                    value: numericValue(row, key: key),
                    low: low,
                    high: high,
                    inverse: inverse,
                    key: key
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
        teamCode: String,
        value: Double?,
        low: Double,
        high: Double,
        inverse: Bool,
        key: TeamSortKey
    ) -> Color {
        // Games played does not indicate performance quality.
        if key == .gp || key == .record || key == .team {
            return TeamPerformancePalette.cellColor(
                teamCode: teamCode, score: 0, scheme: colorScheme
            )
        }
        guard let value, high > low else {
            return TeamPerformancePalette.cellColor(
                teamCode: teamCode, score: 0, scheme: colorScheme
            )
        }
        let rank = min(max((value - low) / (high - low), 0), 1)
        let goodRank = inverse ? 1 - rank : rank
        return TeamPerformancePalette.cellColor(
            teamCode: teamCode,
            score: (2 * goodRank) - 1,
            scheme: colorScheme
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.iceometricsFavoritePaletteTeamCode) private var favoritePaletteTeamCode

    private let rowHeight: CGFloat = 36
    private let teamWidth: CGFloat = 82
    private let dateWidth: CGFloat = 52

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
                HStack(spacing: 4) {
                    StatsTeamLogo(team: team, size: 22)
                    Text(team.code)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 3)
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
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(resultColor(result, teamCode: favoritePaletteTeamCode ?? ""))
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

    private func resultColor(_ result: String, teamCode: String) -> Color {
        let score: Double
        switch result {
        case "W": score = 1.0
        case "OTW": score = 0.83
        case "SOW": score = 0.68
        case "SOL": score = -0.68
        case "OTL": score = -0.83
        case "L": score = -1.0
        default: return .clear
        }
        return TeamPerformancePalette.cellColor(
            teamCode: teamCode, score: score, scheme: colorScheme
        )
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
                                options: ["All", "Goals", "Assists", "Points", "Shots", "Hits", "Blocks", "+/-", "PIM"],
                                allStats: ["Goals", "Assists", "Points", "Shots", "Hits", "Blocks", "+/-", "PIM"],
                                snapshot: snapshot
                            )
                            PlayerCategoryPanel(
                                title: "Goalies",
                                players: data.goalies,
                                options: ["All", "Wins", "Losses", "OTL", "Save %", "Shutouts", "Saves", "Games Started", "Saves / GS", "GAA"],
                                allStats: ["Wins", "Losses", "OTL", "Save %", "Shutouts", "Saves", "Games Started", "Saves / GS", "GAA"],
                                snapshot: snapshot
                            )
                        }
                    }
                } else {
                    ScrollView(.vertical) {
                        HStack(alignment: .top, spacing: 14) {
                        PlayerCategoryPanel(
                            title: "Skaters",
                            players: data.skaters,
                            options: ["All", "Goals", "Assists", "Points", "Shots", "Hits", "Blocks", "+/-", "PIM"],
                            allStats: ["Goals", "Assists", "Points", "Shots", "Hits", "Blocks", "+/-", "PIM"],
                            snapshot: snapshot
                        )
                        PlayerCategoryPanel(
                            title: "Goalies",
                            players: data.goalies,
                            options: ["All", "Wins", "Losses", "OTL", "Save %", "Shutouts", "Saves", "Games Started", "Saves / GS", "GAA"],
                            allStats: ["Wins", "Losses", "OTL", "Save %", "Shutouts", "Saves", "Games Started", "Saves / GS", "GAA"],
                            snapshot: snapshot
                        )
                        }
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
                LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(allStats, id: \.self) { stat in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(stat)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(topPlayers(for: stat, limit: 5)) { player in
                                    if player.value(stat) == 0 {
                                        IceometricsZeroPlayerCard()
                                    } else {
                                        PlayerLeaderCard(
                                            player: player, stat: stat, snapshot: snapshot
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(topPlayers(for: selectedStat, limit: 25)) { player in
                        if player.value(selectedStat) == 0 {
                            IceometricsZeroPlayerRow()
                        } else {
                            PlayerLeaderRow(
                                player: player, stat: selectedStat, snapshot: snapshot
                            )
                        }
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

private struct IceometricsZeroPlayerCard: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.square.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 75, height: 94)
                .foregroundStyle(.tertiary)
            Text("Data pending")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 140)
            Text("—")
                .font(.title2.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(width: 160)
        .frame(minHeight: 186)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityLabel("Player leader data unavailable")
    }
}

private struct IceometricsZeroPlayerRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.square.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .foregroundStyle(.tertiary)
            Text("Data pending")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("—").foregroundStyle(.tertiary)
        }
        .padding(.vertical, 7)
        .accessibilityLabel("Player leader data unavailable")
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
            IceometricsHistoryToolbar(
                title: "Points",
                selection: $phase,
                phases: phases,
                allowNegative: false
            )

            if let table = snapshot.pointsHistory(for: phase) {
                HistoryStatsPanel(
                    title: "Points",
                    table: table,
                    teams: snapshot.teams,
                    games: snapshot.games,
                    phase: phase,
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
            IceometricsHistoryToolbar(
                title: "Goal Differential",
                selection: $phase,
                phases: phases,
                allowNegative: true
            )

            if let table = snapshot.goalDifferentialHistory(for: phase) {
                HistoryStatsPanel(
                    title: "Goal Differential",
                    table: table,
                    teams: snapshot.teams,
                    games: snapshot.games,
                    phase: phase,
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

// ICEOMETRICS_NOTES_BATCH03_STATS_CHARTS_V1
// Focus controls share a scope across both historical graphs. Team membership
// matches the 2026 NHL division alignment (including Utah Mammoth, UTA).
private enum IceometricsHistoryFocus: String, CaseIterable, Identifiable {
    case league, east, west, atlantic, metropolitan, central, pacific

    var id: String { rawValue }

    var title: String {
        return switch self {
        case .league: "Whole League"
        case .east: "Eastern Conference"
        case .west: "Western Conference"
        case .atlantic: "Atlantic Division"
        case .metropolitan: "Metropolitan Division"
        case .central: "Central Division"
        case .pacific: "Pacific Division"
        }
    }

    var members: Set<String>? {
        return switch self {
        case .league: Optional<Set<String>>.none
        case .east: Self.atlanticTeams.union(Self.metro)
        case .west: Self.centralTeams.union(Self.pacificTeams)
        case .atlantic: Self.atlanticTeams
        case .metropolitan: Self.metro
        case .central: Self.centralTeams
        case .pacific: Self.pacificTeams
        }
    }

    private static let atlanticTeams: Set<String> = [
        "BOS", "BUF", "DET", "FLA", "MTL", "OTT", "TBL", "TOR"
    ]
    private static let metro: Set<String> = [
        "CAR", "CBJ", "NJD", "NYI", "NYR", "PHI", "PIT", "WSH"
    ]
    private static let centralTeams: Set<String> = [
        "CHI", "COL", "DAL", "MIN", "NSH", "STL", "UTA", "WPG"
    ]
    private static let pacificTeams: Set<String> = [
        "ANA", "CGY", "EDM", "LAK", "SEA", "SJS", "VAN", "VGK"
    ]
}

// ICEOMETRICS_NOTES_BATCH04_CHART_FOCUS_TOOLBAR_V1
// Controls are on the same line as the graph title/phase on spacious screens.
// Compact widths stack naturally instead of squeezing or clipping pickers.
private struct IceometricsHistoryToolbar: View {
    let title: String
    @Binding var selection: StatsPhase
    let phases: [StatsPhase]
    let allowNegative: Bool
    @AppStorage("iceometrics.stats.graph.focus") private var focusValue = "league"
    @AppStorage("iceometrics.stats.graph.points.axis.v2") private var pointsAxis = "date"
    @AppStorage("iceometrics.stats.graph.goalDifferential.axis") private var goalAxis = "date"

    private var axis: Binding<String> {
        Binding(get: { allowNegative ? goalAxis : pointsAxis },
                set: { next in
                    if allowNegative { goalAxis = next } else { pointsAxis = next }
                })
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            // Three zones: title + phases left, X-axis centered, Focus right.
            // This option needs genuine room; otherwise use the stacked layout.
            ZStack {
                HStack(spacing: 12) {
                    Text(title)
                        .font(.title2.bold())
                        .fixedSize(horizontal: true, vertical: false)
                    StatsPhasePicker(selection: $selection, phases: phases)
                        .frame(width: 300)
                    Spacer(minLength: 0)
                }
                axisPicker
                HStack { Spacer(minLength: 0); focusPicker }
            }
            .frame(minWidth: 1120)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                StatsPanelHeader(title: title, selection: $selection, phases: phases)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { axisPicker; Spacer(minLength: 0); focusPicker }
                    VStack(alignment: .leading, spacing: 8) {
                        axisPicker
                        focusPicker
                    }
                }
            }
        }
    }

    private var axisPicker: some View {
        Picker("X-Axis", selection: axis) {
            Text("Date").tag("date")
            Text("Games Played").tag("games")
        }
        .pickerStyle(.segmented)
        .frame(width: 215)
    }
    private var focusPicker: some View {
        Picker("Focus", selection: $focusValue) {
            ForEach(IceometricsHistoryFocus.allCases) { option in
                Text(option.title).tag(option.rawValue)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 195)
    }
}

// ICEOMETRICS_NOTES_BIG_PASS_07_V1_STATS
private struct HistoryStatsPanel: View {
    let title: String
    let table: StatsHistoryTable
    let teams: [StatsTeam]
    let games: [StatsGame]
    let phase: StatsPhase
    @Binding var selectedTeamCode: String?
    let allowNegative: Bool

    // Persist independently for Points and Goal Differential, so returning to
    // a graph restores the viewer's preferred horizontal axis.
    @AppStorage("iceometrics.stats.graph.points.axis.v2") private var pointsAxis = "date"
    @AppStorage("iceometrics.stats.graph.goalDifferential.axis") private var goalAxis = "date"
    @AppStorage("iceometrics.stats.graph.focus") private var focusValue = "league"

    private var gamesAxis: Bool {
        allowNegative ? goalAxis == "games" : pointsAxis == "games"
    }

    private var axisSelection: Binding<String> {
        Binding(
            get: { allowNegative ? goalAxis : pointsAxis },
            set: { value in
                if allowNegative { goalAxis = value }
                else { pointsAxis = value }
            }
        )
    }

    private var focus: IceometricsHistoryFocus {
        IceometricsHistoryFocus(rawValue: focusValue) ?? .league
    }
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.iceometricsFavoritePaletteTeamCode) private var favoritePaletteTeamCode
    @State private var iceoScrollLink = IceoTimelineScrollLink()

    private let rowHeight: CGFloat = 34
    private let teamWidth: CGFloat = 82
    private let dateWidth: CGFloat = 52

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

    // Always maintain the chronological date table. Only the chart switches
    // its X-axis to completed-game count; its series are NOT date-fill-forward.
    private var gameNumberHistory: [String: [Double?]] {
        var totals = Dictionary(uniqueKeysWithValues: teams.map { ($0.code, 0) })
        var values = Dictionary(uniqueKeysWithValues: teams.map {
            ($0.code, [Double?](arrayLiteral: 0.0))
        })

        let completed = games
            .filter { $0.gameTypeID == phase.gameTypeID && $0.isFinal }
            .sorted { ($0.day, $0.id) < ($1.day, $1.id) }

        for game in completed {
            guard let away = game.awayScore,
                  let home = game.homeScore,
                  away != home else { continue }

            for teamCode in [game.awayCode, game.homeCode] {
                guard values[teamCode] != nil else { continue }
                let earned: Int
                if allowNegative {
                    earned = teamCode == game.awayCode ? away - home : home - away
                } else {
                    let won = (teamCode == game.awayCode && away > home)
                        || (teamCode == game.homeCode && home > away)
                    earned = won ? 2 : (game.wentToExtraTime ? 1 : 0)
                }
                totals[teamCode, default: 0] += earned
                values[teamCode, default: [0.0]].append(
                    Double(totals[teamCode, default: 0])
                )
            }
        }
        return values
    }

    private var gameColumnCount: Int {
        max(1, visibleTeams.compactMap {
            gameNumberHistory[$0.code]?.count
        }.max() ?? 1)
    }

    private var gameLabels: [String] {
        (0..<gameColumnCount).map { index in
            (index % 5 == 0 || index == gameColumnCount - 1)
                ? String(index) : ""
        }
    }

    private var gameColumnWidth: CGFloat {
        // Low-game weeks get wider intervals; full seasons remain scrollable.
        min(64, max(24, 640 / CGFloat(gameColumnCount)))
    }

    // Focus changes visibility, not all the lines' team colors. An actively
    // chosen team remains visible even if it lives outside the chosen division.
    private var chartTeams: [StatsTeam] {
        let membership = focus.members
        return visibleTeams.filter { team in
            (membership?.contains(team.code) ?? true)
                || team.code == selectedTeamCode
        }
    }

    private var graphSeries: [TimelineGraphSeries] {
        let gameValues = gamesAxis ? gameNumberHistory : [:]
        let width = gamesAxis ? gameColumnCount : table.columns.count
        return chartTeams.map { team in
            let source = gamesAxis
                ? (gameValues[team.code] ?? [])
                : (table.rows[team.code] ?? [])
            let values = gamesAxis && source.count < width
                ? source + Array(repeating: nil, count: width - source.count)
                : source
            return TimelineGraphSeries(
                id: team.code,
                color: Color(hex: team.colorHex),
                values: values,
                lineWidth: lineWidth(team),
                opacity: lineOpacity(team)
            )
        }
    }

    private var yDomain: (Double, Double) {
        let values = graphSeries.flatMap { $0.values.compactMap { $0 } }
        guard let low = values.min(), let high = values.max() else {
            return allowNegative ? (-1, 1) : (0, 1)
        }
        if allowNegative {
            let bound = max(1, max(abs(low), abs(high)))
            return (-bound, bound)
        }
        return (0, max(1, high))
    }

    var body: some View {
        let maximum = max(
            1.0,
            visibleTeams
                .flatMap { table.rows[$0.code] ?? [] }
                .compactMap { $0 }
                .map { abs($0) }
                .max() ?? 0
        )
        let rankedTeams = visibleTeams
        let allValues = rankedTeams.flatMap { table.rows[$0.code] ?? [] }.compactMap { $0 }
        let maxAbsoluteGD = max(1.0, allValues.map { abs($0) }.max() ?? 1.0)
        // Precompute once instead of scanning 32 teams for each visible cell.
        let heatBoundsByColumn: [(low: Double, high: Double)] =
            table.columns.indices.map { index in
                if allowNegative { return (low: -maxAbsoluteGD, high: maxAbsoluteGD) }
                let values = rankedTeams.compactMap {
                    table.value(teamCode: $0.code, columnIndex: index)
                }
                return (low: values.min() ?? 0, high: values.max() ?? 0)
            }

        return VStack(alignment: .leading, spacing: 10) {
            graph

            FrozenDataGrid(
                rows: chartTeams,
                columns: columns,
                rowHeaderWidth: teamWidth,
                rowHeight: rowHeight,
                headerHeight: rowHeight,
                initialColumnID: todayIndex,
                linkedHorizontalScroll: iceoScrollLink
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
                    HStack(spacing: 4) {
                        StatsTeamLogo(team: team, size: 21)
                        Text(team.code)
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 3)
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
                let value = displayValue(
                    teamCode: team.code,
                    columnIndex: column.id
                )

                Text(formatHistoryValue(value))
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        value == nil
                            ? Color.clear
                            : TeamPerformancePalette.cellColor(
                                teamCode: favoritePaletteTeamCode ?? "",
                                score: min(max((value ?? 0) / maximum, -1), 1),
                                scheme: colorScheme
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
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                if let selectedTeamCode,
                   let selected = visibleTeams.first(where: { $0.code == selectedTeamCode }) {
                    StatsTeamLogo(team: selected, size: 26)
                    Text("\(selected.name) — \(title)")
                        .font(.headline)
                } else {
                    Text("\(focus.title) — \(title)")
                        .font(.headline)
                }

                Spacer(minLength: 0)

                if selectedTeamCode != nil {
                    Button("Clear Team") { selectedTeamCode = nil }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            AlignedTimelineGraph(
                labels: gamesAxis ? gameLabels : table.columns.map(displayHistoryDate),
                series: graphSeries,
                leadingWidth: teamWidth,
                columnWidth: gamesAxis ? gameColumnWidth : dateWidth,
                yMin: yDomain.0,
                yMax: yDomain.1,
                initialColumnIndex: gamesAxis ? gameColumnCount - 1 : todayIndex,
                height: 250,
                showXLabels: gamesAxis
            ) { value in
                String(Int(value.rounded()))
            }
            .id(gamesAxis ? "game-axis-\(phase.rawValue)" : "date-axis-\(phase.rawValue)")

            Text(gamesAxis
                 ? "X-axis: completed games per team. Lines stop at each team's last game; the table below remains calendar-based."
                 : "X-axis: calendar date. The graph and table share the date timeline.")
                .font(.caption2)
                .foregroundStyle(.secondary)
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
        guard let selectedTeamCode else { return 1.7 }
        return team.code == selectedTeamCode ? 3.8 : 1.3
    }

    private func lineOpacity(_ team: StatsTeam) -> Double {
        guard let selectedTeamCode else { return 0.87 }
        return team.code == selectedTeamCode ? 1.0 : 0.22
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
        // Empty values represent a game still in progress (or scheduled).
        // Keep the previous result for graph continuity, but not for table cells.
        return table.value(teamCode: teamCode, columnIndex: columnIndex)
    }

    private func columnBounds(_ index: Int) -> (low: Double, high: Double) {
        let values = chartTeams.compactMap {
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
        // Zero is neutral in the Points and Goal Differential tables.
        if abs(value) < 0.0000001 {
            return StatsPerformancePalette.neutral.opacity(0.22)
        }
        if allowNegative {
            let extent = max(1.0, abs(low), abs(high))
            return StatsPerformancePalette.signed(value, extent: extent)
        }
        // Positive but tied point totals retain a subtle blue tint.
        guard high > low else { return StatsPerformancePalette.good.opacity(0.08) }
        return StatsPerformancePalette.relative((value - low) / (high - low))
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
