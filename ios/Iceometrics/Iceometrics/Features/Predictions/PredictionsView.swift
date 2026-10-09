import SwiftUI
import Charts

struct PredictionsView: View {
    @StateObject private var viewModel: PredictionsViewModel
    @State private var selectedPredictionTab = "pie"
    @State private var selectedTeamCode: String?
    @State private var hasInitializedTeamSelection = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var settings: AppSettingsStore

    @MainActor
    init(viewModel: PredictionsViewModel? = nil) {
        _viewModel = StateObject(
            wrappedValue: viewModel ?? PredictionsViewModel()
        )
    }

    var body: some View {
        Group {
            if let snapshot = viewModel.snapshot,
               snapshot.hasData {
                predictionContent(snapshot)
            } else if viewModel.isLoading {
                ProgressView("Loading MoneyPuck predictions…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView(
                    "Predictions unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ContentUnavailableView(
                    "No prediction data",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("No MoneyPuck simulation tables are available yet.")
                )
            }
        }
        .navigationTitle("Predictions")
        .toolbar {
            ToolbarItem {
                Button {
                    Task(priority: .userInitiated) {
                        await viewModel.refresh()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
                .help("Refresh predictions")
            }
        }
        .task(priority: .utility) {
            await viewModel.loadIfNeeded()
            selectFirstAvailableMetricIfNeeded()
            initializeFavoriteTeamSelectionIfNeeded()
        }
        .onChange(of: viewModel.snapshot?.generatedAt) { _, _ in
            selectFirstAvailableMetricIfNeeded()
            initializeFavoriteTeamSelectionIfNeeded()
        }
        .onChange(of: settings.favoriteTeamID) { _, _ in
            hasInitializedTeamSelection = false
            initializeFavoriteTeamSelectionIfNeeded()
        }
    }

    @ViewBuilder
    private func predictionContent(
        _ snapshot: PredictionSnapshot
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            predictionTabPicker(snapshot.metrics)

            HStack(alignment: .firstTextBaseline) {
                Text(
                    selectedPredictionTab == "pie"
                        ? "MoneyPuck Predictions"
                        : (selectedMetric?.title ?? "MoneyPuck Predictions")
                )
                .font(.title2.bold())

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Group {
                if selectedPredictionTab == "pie" {
                    PredictionPieChartView(snapshot: snapshot)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity
                        )
                } else if let table = snapshot.tables[selectedPredictionTab] {
                    PredictionMetricPanel(
                        title: selectedMetric?.title
                            ?? "Prediction Probability",
                        table: table,
                        teams: sortedTeams(
                            snapshot.teams,
                            table: table
                        ),
                        season: snapshot.season,
                        compact: horizontalSizeClass == .compact,
                        selectedTeamCode: $selectedTeamCode
                    )
                } else {
                    ContentUnavailableView(
                        "Metric unavailable",
                        systemImage: "tablecells",
                        description: Text("This MoneyPuck table was not included in the latest export.")
                    )
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )

            HStack(spacing: 6) {
                Text(viewModel.sourceStatusText)
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

    private func predictionTabPicker(
        _ metrics: [PredictionMetric]
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                predictionTabButtons(metrics)
            }
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    predictionTabButtons(metrics)
                }
                .padding(.horizontal, 1)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func predictionTabButtons(
        _ metrics: [PredictionMetric]
    ) -> some View {
        Button {
            selectedPredictionTab = "pie"
        } label: {
            Text(horizontalSizeClass == .compact ? "Pie" : "Pie Chart")
                .font(
                    (horizontalSizeClass == .compact ? Font.caption : Font.subheadline)
                        .weight(.semibold)
                )
                .lineLimit(1)
        }
        .buttonStyle(
            PredictionMetricButtonStyle(
                isSelected: selectedPredictionTab == "pie"
            )
        )

        ForEach(metrics) { metric in
            Button {
                selectedPredictionTab = metric.key
            } label: {
                Text(
                    horizontalSizeClass == .compact
                        ? compactMetricLabel(metric.label)
                        : metric.label
                )
                    .font(
                        (horizontalSizeClass == .compact ? Font.caption : Font.subheadline)
                            .weight(.semibold)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .buttonStyle(
                PredictionMetricButtonStyle(
                    isSelected: selectedPredictionTab == metric.key
                )
            )
        }
    }

    private func compactMetricLabel(_ label: String) -> String {
        switch label {
        case "Make Playoffs":
            return "Playoffs"
        case "Make Round 2":
            return "Round 2"
        case "Make Conference Final":
            return "Conf."
        case "Win Stanley Cup":
            return "Cup"
        default:
            return label
                .replacingOccurrences(of: "Make ", with: "")
                .replacingOccurrences(of: "Conference Final", with: "Conf.")
                .replacingOccurrences(of: "Stanley Cup", with: "Cup")
        }
    }

    private var selectedMetric: PredictionMetric? {
        viewModel.metrics.first {
            $0.key == selectedPredictionTab
        }
    }

    private func sortedTeams(
        _ teams: [PredictionTeam],
        table: PredictionTable
    ) -> [PredictionTeam] {
        let season = viewModel.snapshot?.season ?? ""
        let index = predictionTodayColumnIndex(
            table.columns,
            season: season
        )

        return teams.sorted { lhs, rhs in
            let left = predictionRankValue(
                table: table,
                teamCode: lhs.code,
                through: index
            )

            let right = predictionRankValue(
                table: table,
                teamCode: rhs.code,
                through: index
            )

            return left == right ? lhs.name < rhs.name : left > right
        }
    }

    private func predictionRankValue(
        table: PredictionTable,
        teamCode: String,
        through index: Int
    ) -> Double {
        guard !table.columns.isEmpty else {
            return -Double.greatestFiniteMagnitude
        }

        for columnIndex in stride(
            from: min(index, table.columns.count - 1),
            through: 0,
            by: -1
        ) {
            if let value = table.value(
                teamCode: teamCode,
                columnIndex: columnIndex
            ) {
                return value
            }
        }

        return -Double.greatestFiniteMagnitude
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

    private func selectFirstAvailableMetricIfNeeded() {
        guard let snapshot = viewModel.snapshot else {
            return
        }

        if selectedPredictionTab == "pie" {
            return
        }

        if snapshot.tables[selectedPredictionTab] != nil {
            return
        }

        if let first = snapshot.metrics.first(
            where: {
                snapshot.tables[$0.key] != nil
            }
        ) {
            selectedPredictionTab = first.key
        } else {
            selectedPredictionTab = "pie"
        }
    }
}

private struct PredictionMetricButtonStyle: ButtonStyle {
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

private struct PredictionMetricPanel: View {
    let title: String
    let table: PredictionTable
    let teams: [PredictionTeam]
    let season: String
    let compact: Bool
    @Binding var selectedTeamCode: String?

    private var teamWidth: CGFloat { compact ? 96 : 152 }
    private var dateWidth: CGFloat { compact ? 66 : 76 }

    private var todayIndex: Int {
        predictionTodayColumnIndex(table.columns, season: season)
    }

    private var yDomain: (Double, Double) {
        // Prediction charts always start at zero, but only climb to 100%
        // when the leading team is actually near that ceiling.
        let highest = graphSeries
            .flatMap(\.values)
            .compactMap { $0 }
            .max() ?? 0

        let ceilings: [Double] = [
            10, 20, 30, 40, 50, 60, 70, 75, 80, 90, 95, 100
        ]
        let ceiling = ceilings.first(where: { $0 > highest }) ?? 100
        return (0, ceiling)
    }

    private var graphSeries: [TimelineGraphSeries] {
        teams.map { team in
            TimelineGraphSeries(
                id: team.code,
                color: Color(hex: team.colorHex, fallback: .accentColor),
                values: table.columns.indices.map { index in
                    table.value(teamCode: team.code, columnIndex: index)
                        .map { $0 * 100 }
                },
                lineWidth: lineWidth(team),
                opacity: lineOpacity(team)
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            probabilityChart

            PredictionSpreadsheet(
                table: table,
                teams: teams,
                season: season,
                compact: compact,
                selectedTeamCode: $selectedTeamCode
            )
            .frame(maxHeight: .infinity)
        }
    }

    private var probabilityChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let selectedTeamCode,
                   let selected = teams.first(where: { $0.code == selectedTeamCode }) {
                    PredictionTeamLogo(team: selected)
                    Text("\(selected.name) — \(title)")
                        .font(.headline)
                } else {
                    Text("All Teams — \(title)")
                        .font(.headline)
                }

                Spacer()

                if selectedTeamCode != nil {
                    Button("All Teams") {
                        selectedTeamCode = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            AlignedTimelineGraph(
                labels: table.columns.map {
                    displayPredictionDate($0, season: season)
                },
                series: graphSeries,
                leadingWidth: teamWidth,
                columnWidth: dateWidth,
                yMin: yDomain.0,
                yMax: yDomain.1,
                initialColumnIndex: todayIndex,
                height: 226,
                showXLabels: false
            ) { value in
                "\(Int(value.rounded()))%"
            }
        }
        .padding(.vertical, 6)
    }

    private func lineWidth(_ team: PredictionTeam) -> CGFloat {
        guard let selectedTeamCode else { return 1.6 }
        return selectedTeamCode == team.code ? 3.6 : 1.0
    }

    private func lineOpacity(_ team: PredictionTeam) -> Double {
        guard let selectedTeamCode else { return 0.88 }
        return selectedTeamCode == team.code ? 1.0 : 0.20
    }
}

private struct PredictionSpreadsheet: View {
    let table: PredictionTable
    let teams: [PredictionTeam]
    let season: String
    let compact: Bool
    @Binding var selectedTeamCode: String?

    private let rowHeight: CGFloat = 42

    private var teamColumnWidth: CGFloat { compact ? 96 : 152 }
    private var dateColumnWidth: CGFloat { compact ? 66 : 76 }

    private var todayIndex: Int {
        predictionTodayColumnIndex(table.columns, season: season)
    }

    private var columns: [FrozenGridColumn<Int>] {
        table.columns.indices.map {
            FrozenGridColumn(id: $0, width: dateColumnWidth)
        }
    }

    private var gridHorizontalHairline: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.14))
            .frame(height: 0.5)
    }

    private var gridVerticalHairline: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.14))
            .frame(width: 0.5)
    }

    var body: some View {
        FrozenDataGrid(
            rows: teams,
            columns: columns,
            rowHeaderWidth: teamColumnWidth,
            rowHeight: rowHeight,
            headerHeight: rowHeight,
            initialColumnID: todayIndex
        ) {
            Text("Team")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .leading
                )
                .padding(.horizontal, 8)
                .background(Color.primary.opacity(0.055))
                .overlay(alignment: .bottom) { gridHorizontalHairline }
        } header: { column in
            dateHeader(
                table.columns[column.id],
                isToday: column.id == todayIndex
            )
        } rowHeader: { team in
            Button {
                selectedTeamCode = selectedTeamCode == team.code ? nil : team.code
            } label: {
                HStack(spacing: 6) {
                    PredictionTeamLogo(team: team)

                    Text(compact ? team.code : team.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 7)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
                .overlay {
                    selectedTeamCode == team.code
                        ? Color(hex: team.colorHex, fallback: .accentColor).opacity(0.16)
                        : Color.primary.opacity(0.025)
                }
                .overlay(alignment: .bottom) { gridHorizontalHairline }
            }
            .buttonStyle(.plain)
        } cell: { team, column in
            probabilityCell(
                table.value(teamCode: team.code, columnIndex: column.id),
                isToday: column.id == todayIndex
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private func dateHeader(_ raw: String, isToday: Bool) -> some View {
        Text(displayPredictionDate(raw, season: season))
            .font(.caption.weight(isToday ? .bold : .semibold))
            .foregroundStyle(isToday ? .primary : .secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                isToday
                    ? Color.accentColor.opacity(0.10)
                    : Color.primary.opacity(0.055)
            )
            .overlay(alignment: .leading) { gridVerticalHairline }
            .overlay(alignment: .bottom) { gridHorizontalHairline }
    }

    private func probabilityCell(_ value: Double?, isToday: Bool) -> some View {
        let clamped = min(max(value ?? 0, 0), 1)

        return Text(
            value.map {
                $0.formatted(
                    .percent.precision(.fractionLength(1))
                )
            } ?? ""
        )
        .font(
            .system(.caption, design: .monospaced)
            .weight(isToday ? .bold : .medium)
        )
        .foregroundStyle(value == nil ? .tertiary : .primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color.accentColor.opacity(
                value == nil
                    ? 0
                    : 0.025 + clamped * (isToday ? 0.18 : 0.11)
            )
        )
        .overlay(alignment: .leading) { gridVerticalHairline }
        .overlay(alignment: .bottom) { gridHorizontalHairline }
    }
}

private func predictionTodayColumnIndex(
    _ columns: [String],
    season: String
) -> Int {
    guard !columns.isEmpty else { return 0 }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
    let today = calendar.startOfDay(for: Date())

    let dated = columns.enumerated().compactMap { index, raw -> (Int, Date)? in
        guard let date = predictionColumnDate(raw, season: season) else {
            return nil
        }
        return (index, calendar.startOfDay(for: date))
    }

    if let exact = dated.first(where: {
        calendar.isDate($0.1, inSameDayAs: today)
    }) {
        return exact.0
    }

    if let latestPast = dated.filter({ $0.1 <= today }).last {
        return latestPast.0
    }

    return 0
}

private func predictionColumnDate(
    _ raw: String,
    season: String
) -> Date? {
    let parts = raw.split(separator: "/")
    guard parts.count == 2,
          let month = Int(parts[0]),
          let day = Int(parts[1]),
          let startYear = Int(season.prefix(4)) else {
        return nil
    }

    let year = month >= 7 ? startYear : startYear + 1
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current

    return calendar.date(
        from: DateComponents(year: year, month: month, day: day)
    )
}

private func displayPredictionDate(
    _ raw: String,
    season: String
) -> String {
    guard let date = predictionColumnDate(raw, season: season) else {
        return raw
    }

    return date.formatted(
        .dateTime
            .day()
            .month(.abbreviated)
            .locale(Locale(identifier: "en_GB"))
    )
}

private struct PredictionTeamLogo: View {
    let team: PredictionTeam

    var body: some View {
        AsyncImage(url: team.logoURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
            case .failure:
                Image(systemName: "hockey.puck.fill")
                    .foregroundStyle(.secondary)
            case .empty:
                ProgressView()
                    .controlSize(.mini)
            @unknown default:
                EmptyView()
            }
        }
        .frame(width: 28, height: 28)
    }

}

#Preview {
    NavigationStack {
        PredictionsView()
    }
}
