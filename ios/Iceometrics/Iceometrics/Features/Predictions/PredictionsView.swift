// ICEOMETRICS_NOTES_BATCH05_LATEST_PROBABILITY_BARS_V2
import SwiftUI
import Charts

struct PredictionsView: View {
    @StateObject private var viewModel: PredictionsViewModel
    @AppStorage("iceometrics.predictions.tab") private var selectedPredictionTab = "pie"
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
        let index = table.columns.indices.reversed().first { column in
            teams.contains { team in
                table.value(teamCode: team.code, columnIndex: column) != nil
            }
        } ?? predictionTodayColumnIndex(table.columns, season: season)

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

// ICEOMETRICS_NOTES_BIG_PASS_07_V1_PRED
private struct PredictionMetricPanel: View {
    let title: String
    let table: PredictionTable
    let teams: [PredictionTeam]
    let season: String
    let compact: Bool
    @Binding var selectedTeamCode: String?
    @AppStorage("iceometrics.predictions.lastFocusedTeamCode") private var lastFocusedTeamCode = ""
    @State private var iceoScrollLink = IceoTimelineScrollLink()

    private var teamWidth: CGFloat { compact ? 82 : 105 }
    private var dateWidth: CGFloat { compact ? 58 : 62 }

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
                .onAppear {
                    if let selectedTeamCode { lastFocusedTeamCode = selectedTeamCode }
                }
                .onChange(of: selectedTeamCode) { _, next in
                    if let next { lastFocusedTeamCode = next }
                }

            PredictionSpreadsheet(
                table: table,
                teams: teams,
                season: season,
                compact: compact,
                selectedTeamCode: $selectedTeamCode,
                linkedHorizontalScroll: iceoScrollLink
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
                    Text("\(selected.code) — \(title)")
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
            
                if selectedTeamCode == nil,
                   !lastFocusedTeamCode.isEmpty,
                   teams.contains(where: { $0.code == lastFocusedTeamCode }) {
                    Button("Focus \(lastFocusedTeamCode)") {
                        selectedTeamCode = lastFocusedTeamCode
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
                showXLabels: false,
                adaptiveYScale: false,
                selectedSeriesID: selectedTeamCode,
                zeroBaseline: true,
                percentageScale: true,
                linkedHorizontalScroll: iceoScrollLink
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.iceometricsFavoritePaletteTeamCode) private var favoritePaletteTeamCode
    let linkedHorizontalScroll: IceoTimelineScrollLink

    private let rowHeight: CGFloat = 36

    private var teamColumnWidth: CGFloat { compact ? 82 : 105 }
    private var dateColumnWidth: CGFloat { compact ? 58 : 62 }

    private var todayIndex: Int {
        predictionTodayColumnIndex(table.columns, season: season)
    }

    // // ICEOMETRICS_PREDICTION_COLUMN_NORMALIZATION_V1
    // Use the visible dataset for EACH date, separately. A missing cell stays
    // transparent; a constant-valued column stays neutral gray.
    private var columnProbabilityBounds: [(low: Double, high: Double)] {
        table.columns.indices.map { index in
            let values = teams.compactMap { team -> Double? in
                guard let value = table.value(teamCode: team.code, columnIndex: index),
                      value.isFinite else { return nil }
                return value
            }
            return (values.min() ?? 0, values.max() ?? 0)
        }
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

    // The table and the right pane scroll together vertically. Bars are not a
    // separate scroll view: their rows always match the team rows.
    @State private var tableVerticalOffset: CGFloat = 0
    private let latestPaneWidth: CGFloat = 235

    private var latestAvailableColumn: Int {
        guard !table.columns.isEmpty else { return 0 }
        return table.columns.indices.reversed().first { index in
            teams.contains { team in
                table.value(teamCode: team.code, columnIndex: index) != nil
            }
        } ?? todayIndex
    }

    // ICEOMETRICS_DOC_REMAINING_20261015_V1_PREDICTIONS
    private var latestBarPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text("LATEST · \(table.columns.isEmpty ? "—" : displayPredictionDate(table.columns[latestAvailableColumn], season: season))")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("0–100%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 9)
            .frame(height: rowHeight)
            .background(Color.primary.opacity(0.055))
            .overlay(alignment: .bottom) { gridHorizontalHairline }

            GeometryReader { _ in
                VStack(spacing: 0) {
                    ForEach(teams) { team in
                        let value = table.value(
                            teamCode: team.code,
                            columnIndex: latestAvailableColumn
                        )
                        HStack(spacing: 7) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.primary.opacity(0.085))
                                    if let value {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(
                                                LinearGradient(
                                                    colors: TeamPerformancePalette.predictionBarColors(teamCode: team.code, fallbackHex: team.colorHex),
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(width: max(0, geo.size.width * CGFloat(min(1, max(0, value)))))
                                    }
                                }
                            }
                            .frame(height: 11)
                            Text(value.map {
                                $0.formatted(.percent.precision(.fractionLength(1)))
                            } ?? "—")
                                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                                .frame(width: 52, alignment: .trailing)
                                .foregroundStyle(value == nil ? .tertiary : .primary)
                        }
                        .padding(.horizontal, 9)
                        .frame(height: rowHeight)
                        .background(Color.primary.opacity(0.018))
                        .overlay(alignment: .bottom) { gridHorizontalHairline }
                    }
                }
                .offset(y: -tableVerticalOffset)
            }
            .clipped()
        }
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1)
        }
        .accessibilityLabel("Latest available predicted probabilities")
    }

    var body: some View {
        GeometryReader { viewport in
            // At very narrow widths use the table alone rather than pushing
            // the pinned bar pane offscreen.
            let showLatestPane = !compact && viewport.size.width >= 440
            let paneWidth = min(latestPaneWidth, max(160, viewport.size.width * 0.29))
            HStack(spacing: 0) {

            let probabilityBounds = columnProbabilityBounds
            // ICEOMETRICS_DOC_PREDICTION_BARS_VISIBLE_20261015
            // Do not `return` here: the pinned right-hand pane is the NEXT view
            // in the HStack and must be constructed by the ViewBuilder.
            FrozenDataGrid(
                rows: teams,
                columns: columns,
                rowHeaderWidth: teamColumnWidth,
                rowHeight: rowHeight,
                headerHeight: rowHeight,
                initialColumnID: todayIndex,
                linkedHorizontalScroll: linkedHorizontalScroll,
                onVerticalScroll: { next in
                    if abs(next - tableVerticalOffset) > 0.75 {
                        tableVerticalOffset = next
                    }
                }
            ) {
                Text("Team")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .leading
                    )
                    .padding(.horizontal, 3)
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
                    HStack(spacing: 4) {
                        PredictionTeamLogo(team: team)

                        Text(team.code)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 3)
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
                    isToday: column.id == todayIndex,
                    teamCode: team.code,
                    bounds: probabilityBounds[column.id]
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            }
            .frame(
                width: viewport.size.width - (showLatestPane ? paneWidth : 0),
                height: viewport.size.height
            )

                if showLatestPane {
                    latestBarPanel.frame(width: paneWidth)
                }
            }
            .frame(width: viewport.size.width, height: viewport.size.height)
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

    private func normalizedColumnScore(
        _ value: Double?,
        bounds: (low: Double, high: Double)
    ) -> Double {
        guard let value, value.isFinite,
              bounds.high > bounds.low else { return 0 }
        let fraction = (value - bounds.low) / (bounds.high - bounds.low)
        // +1 = favorite team GOOD, -1 = favorite team BAD, 0 = gray.
        return min(1, max(-1, (fraction * 2) - 1))
    }

    private func probabilityCell(
        _ value: Double?,
        isToday: Bool,
        teamCode: String,
        bounds: (low: Double, high: Double)
    ) -> some View {

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
        .foregroundStyle(value == nil ? Color.secondary : (colorScheme == .dark ? Color.white : Color.black))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            value == nil
                ? Color.clear
                : TeamPerformancePalette.cellColor(
                    teamCode: favoritePaletteTeamCode ?? "",
                    score: normalizedColumnScore(value, bounds: bounds),
                    scheme: colorScheme
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
    // ICEOMETRICS_PREDICTION_ISO_DATE_V1
    let dateParts = raw.split(separator: "-")
    if dateParts.count == 3,
       let year = Int(dateParts[0]),
       let month = Int(dateParts[1]),
       let day = Int(dateParts[2]) {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return eastern.date(from: DateComponents(year: year, month: month, day: day))
    }

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
