// ICEOMETRICS_MODELS_ALPHA_LAYOUT_V2

import SwiftUI
import Foundation

struct ModelsView: View {
    @StateObject private var viewModel: ModelsViewModel
    @State private var selectedSection: ModelsSection = .playoffPicture
    @State private var nhlStandings: IceometricsNHLStandings?
    @State private var nhlStandingsLoading = false
    @State private var nhlStandingsError: String?

    @AppStorage("iceometrics.models.section") private var savedSection = "playoffPicture"
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @MainActor
    init(viewModel: ModelsViewModel? = nil) {
        _viewModel = StateObject(
            wrappedValue: viewModel ?? ModelsViewModel()
        )
    }

    var body: some View {
        Group {
            if let snapshot = viewModel.snapshot,
               snapshot.hasData {
                content(snapshot)
            } else if viewModel.isLoading {
                ProgressView("Loading NHL models…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView(
                    "Models unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ContentUnavailableView(
                    "No model data",
                    systemImage: "function",
                    description: Text("No NHL model snapshot is available yet.")
                )
            }
        }
        .navigationTitle("Models")
        .onAppear {
            selectedSection = ModelsSection(rawValue: savedSection) ?? .playoffPicture
        }
        .onChange(of: selectedSection) { _, newSection in
            savedSection = newSection.rawValue
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task {
                        await viewModel.refresh()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
                .help("Refresh models")
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .task(id: selectedSection) {
            if selectedSection == .standings || selectedSection == .playoffPicture {
                await loadActualStandings()
            }
        }

    }

    private func loadActualStandings() async {
        guard nhlStandings == nil && !nhlStandingsLoading else { return }
        nhlStandingsLoading = true
        defer { nhlStandingsLoading = false }
        do {
            nhlStandings = try await IceometricsNHLStandings.fetch()
            nhlStandingsError = nil
        } catch {
            nhlStandingsError = "NHL actual standings unavailable: \(error.localizedDescription)"
        }
    }

    private func content(
        _ snapshot: ModelsSnapshot
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("NHL • \(viewModel.updatedText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            modelsSectionPicker

            Group {
                switch selectedSection {
                case .playoffPicture:
                    if let picture = snapshot.playoffPicture {
                        PlayoffPicturePanel(
                            picture: picture,
                            teams: snapshot.teams,
                            actualStandings: nhlStandings,
                            standingsLoading: nhlStandingsLoading,
                            standingsError: nhlStandingsError
                        )
                    } else {
                        ModelUnavailableView(
                            title: "Playoff picture unavailable"
                        )
                    }

                case .standings:
                    if let nhlStandings {
                        IceometricsActualStandingsPanel(snapshot: nhlStandings)
                    } else if nhlStandingsLoading {
                        ProgressView("Loading NHL standings…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView(
                            "Actual NHL standings unavailable",
                            systemImage: "list.number",
                            description: Text(nhlStandingsError ?? "Refresh to try again.")
                        )
                    }

                case .magicTragic:
                    if let magicTragic = snapshot.magicTragic {
                        MagicTragicPanel(
                            snapshot: magicTragic,
                            teams: snapshot.teams
                        )
                    } else {
                        ModelUnavailableView(
                            title: "Magic / Tragic unavailable"
                        )
                    }

                case .pointProbabilities:
                    if let probabilities = snapshot.pointProbabilities {
                        PointProbabilitiesPanel(
                            snapshot: probabilities,
                            teams: snapshot.teams
                        )
                    } else {
                        ModelUnavailableView(
                            title: "Point probabilities unavailable"
                        )
                    }

                case .playoffWinProbabilities:
                    if let probabilities = snapshot.playoffWinProbabilities {
                        PlayoffWinProbabilitiesPanel(
                            snapshot: probabilities,
                            teams: snapshot.teams
                        )
                    } else {
                        ModelUnavailableView(
                            title: "Playoff win probabilities unavailable"
                        )
                    }
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
        }
        .padding(.horizontal)
        .padding(.bottom)
    }

    private var modelsSectionPicker: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                modelsSectionButtons
            }
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )

            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {
                HStack(spacing: 8) {
                    modelsSectionButtons
                }
                .padding(.horizontal, 1)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var modelsSectionButtons: some View {
        ForEach(ModelsSection.allCases) { section in
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
                    .minimumScaleFactor(0.72)
            }
            .buttonStyle(
                ModelTabButtonStyle(
                    isSelected: selectedSection == section
                )
            )
        }
    }
}

private enum ModelsSection: String, CaseIterable, Identifiable {
    case playoffPicture
    case standings
    case magicTragic
    case pointProbabilities
    case playoffWinProbabilities

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playoffPicture:
            "Playoff Picture"
        case .standings:
            "Standings"
        case .magicTragic:
            "Magic / Tragic"
        case .pointProbabilities:
            "Point Probabilities"
        case .playoffWinProbabilities:
            "Playoff Win Probabilities"
        }
    }

    var compactTitle: String {
        switch self {
        case .playoffPicture: "Playoffs"
        case .standings: "Standings"
        case .magicTragic: "Magic"
        case .pointProbabilities: "Points"
        case .playoffWinProbabilities: "Series"
        }
    }
}

private struct ModelTabButtonStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.iceometricsAccentForegroundColor) private var accentForegroundColor

    func makeBody(
        configuration: Configuration
    ) -> some View {
        configuration.label
            .padding(.horizontal, horizontalSizeClass == .compact ? 8 : 12)
            .padding(.vertical, horizontalSizeClass == .compact ? 6 : 7)
            .foregroundStyle(
                isSelected
                    ? accentForegroundColor
                    : Color.primary
            )
            .background(
                isSelected
                    ? Color.accentColor
                    : Color.primary.opacity(
                        configuration.isPressed
                            ? 0.10
                            : 0.055
                    ),
                in: Capsule()
            )
    }
}

private struct ModelUnavailableView: View {
    let title: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: "function",
            description: Text(
                "This model was not included in the latest backend snapshot."
            )
        )
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }
}

private struct ModelPanelHeader: View {
    let title: String
    let day: String
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title2.bold())

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(displayModelDay(day))
                    .font(.subheadline.weight(.semibold))

                if let subtitle,
                   !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Playoff Picture

private struct PlayoffPicturePanel: View {
    let picture: ModelPlayoffPicture
    let teams: [ModelTeam]
    let actualStandings: IceometricsNHLStandings?
    let standingsLoading: Bool
    let standingsError: String?
    @State private var bracketMode: IceometricsBracketMode = .nhl

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                ModelPanelHeader(
                    title: "Playoff Picture",
                    day: picture.day,
                    subtitle: picture.mode
                )

                Picker("Bracket format", selection: $bracketMode) {
                    ForEach(IceometricsBracketMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if bracketMode == .nhl {
                    FullPlayoffBracketGraphic(picture: picture, teams: teams)
                } else if let actualStandings {
                    IceometricsSeededBracket(snapshot: actualStandings, mode: bracketMode)
                } else if standingsLoading {
                    ProgressView("Loading NHL seedings…")
                } else {
                    Text(standingsError ?? "NHL seedings unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 8)
        }
    }
}

// ICEOMETRICS_DOC_REMAINING_20261015_V1_MODELS
// Official NHL current standings. These are ACTUAL standings, never projections.
private struct IceometricsNHLStandings {
    let date: String
    let rows: [IceometricsNHLStanding]

    static func fetch() async throws -> Self {
        let url = URL(string: "https://api-web.nhle.com/v1/standings/now")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let raw = root?["standings"] as? [[String: Any]], !raw.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        func localized(_ value: Any?) -> String {
            if let dict = value as? [String: Any] {
                return dict["default"] as? String ?? ""
            }
            return value as? String ?? ""
        }
        func integer(_ value: Any?) -> Int { (value as? NSNumber)?.intValue ?? 0 }
        let teams = raw.compactMap { entry -> IceometricsNHLStanding? in
            let code = localized(entry["teamAbbrev"])
            guard !code.isEmpty else { return nil }
            return IceometricsNHLStanding(
                code: code,
                name: localized(entry["teamName"]),
                conference: entry["conferenceName"] as? String ?? "",
                division: entry["divisionName"] as? String ?? "",
                gp: integer(entry["gamesPlayed"]),
                wins: integer(entry["wins"]),
                losses: integer(entry["losses"]),
                ot: integer(entry["otLosses"]),
                points: integer(entry["points"]),
                leagueRank: integer(entry["leagueSequence"]),
                conferenceRank: integer(entry["conferenceSequence"]),
                divisionRank: integer(entry["divisionSequence"]),
                wildcardRank: integer(entry["wildcardSequence"])
            )
        }
        guard teams.count >= 20 else { throw URLError(.cannotParseResponse) }
        return Self(
            date: root?["standingsDateTimeUtc"] as? String ?? "NHL current",
            rows: teams.sorted { $0.leagueRank < $1.leagueRank }
        )
    }
}

private struct IceometricsNHLStanding: Identifiable {
    var id: String { code }
    let code: String
    let name: String
    let conference: String
    let division: String
    let gp: Int
    let wins: Int
    let losses: Int
    let ot: Int
    let points: Int
    let leagueRank: Int
    let conferenceRank: Int
    let divisionRank: Int
    let wildcardRank: Int
}

private enum IceometricsBracketMode: String, CaseIterable, Identifiable {
    case nhl, conference, league16, full32
    var id: Self { self }
    var title: String {
        switch self {
        case .nhl: "NHL"
        case .conference: "Conference 1–8"
        case .league16: "League 1–16"
        case .full32: "Full 32"
        }
    }
}

private struct IceometricsSeededBracket: View {
    let snapshot: IceometricsNHLStandings
    let mode: IceometricsBracketMode

    private var pools: [(String, [IceometricsNHLStanding])] {
        switch mode {
        case .nhl: return []
        case .conference:
            return ["Eastern", "Western"].map { name in
                (name, Array(snapshot.rows
                    .filter { $0.conference == name }
                    .sorted { $0.conferenceRank < $1.conferenceRank }
                    .prefix(8)))
            }
        case .league16: return [("League 1–16", Array(snapshot.rows.prefix(16)))]
        case .full32: return [("Full 32-team bracket", snapshot.rows)]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ACTUAL NHL standings seeding • Not Iceometrics projected winners")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(pools.indices, id: \.self) { index in
                let pool = pools[index]
                VStack(alignment: .leading, spacing: 8) {
                    Text(pool.0).font(.headline)
                    let seeds = pool.1
                    ForEach(0..<(seeds.count / 2), id: \.self) { i in
                        let home = seeds[i]
                        let away = seeds[seeds.count - 1 - i]
                        HStack {
                            Text("#\(i + 1) \(home.code)")
                            Spacer(minLength: 8)
                            Text("vs").foregroundStyle(.tertiary)
                            Spacer(minLength: 8)
                            Text("#\(seeds.count - i) \(away.code)")
                        }
                        .font(.subheadline.monospacedDigit())
                        .padding(9)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                    }
                    let rounds = seeds.count == 32 ? 5 : (seeds.count == 16 ? 4 : 3)
                    HStack(spacing: 8) {
                        ForEach(2...rounds, id: \.self) { number in
                            VStack(spacing: 5) {
                                Text("Round \(number)").font(.caption.bold())
                                Text("TBD")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

private struct IceometricsActualStandingsPanel: View {
    let snapshot: IceometricsNHLStandings
    private let grid = [GridItem(.adaptive(minimum: 300), spacing: 12)]
    private var conferences: [String] { ["Eastern", "Western"] }
    private var divisions: [String] { ["Atlantic", "Metropolitan", "Central", "Pacific"] }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Actual NHL standings • \(snapshot.date)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                IceometricsStandingsTable(title: "League 1–32", rows: snapshot.rows)
                Text("Conferences").font(.headline)
                LazyVGrid(columns: grid, alignment: .leading, spacing: 12) {
                    ForEach(conferences, id: \.self) { conference in
                        IceometricsStandingsTable(
                            title: conference + " 1–16",
                            rows: snapshot.rows.filter { $0.conference == conference }
                                .sorted { $0.conferenceRank < $1.conferenceRank }
                        )
                    }
                }
                Text("Divisions").font(.headline)
                LazyVGrid(columns: grid, alignment: .leading, spacing: 12) {
                    ForEach(divisions, id: \.self) { division in
                        IceometricsStandingsTable(
                            title: division + " 1–8",
                            rows: snapshot.rows.filter { $0.division == division }
                                .sorted { $0.divisionRank < $1.divisionRank }
                        )
                    }
                }
                Text("Wild Card • Division top three qualify directly")
                    .font(.headline)
                LazyVGrid(columns: grid, alignment: .leading, spacing: 12) {
                    ForEach(conferences, id: \.self) { conference in
                        IceometricsStandingsTable(
                            title: conference + " wild-card race",
                            rows: snapshot.rows.filter {
                                $0.conference == conference && $0.divisionRank > 3
                            }.sorted { $0.wildcardRank < $1.wildcardRank }
                        )
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }
}

private struct IceometricsStandingsTable: View {
    let title: String
    let rows: [IceometricsNHLStanding]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.subheadline.bold()).padding(9)
            HStack(spacing: 4) {
                Text("#").frame(width: 20, alignment: .trailing)
                Text("Team").frame(maxWidth: .infinity, alignment: .leading)
                Text("GP").frame(width: 25, alignment: .trailing)
                Text("W").frame(width: 23, alignment: .trailing)
                Text("L").frame(width: 23, alignment: .trailing)
                Text("OT").frame(width: 24, alignment: .trailing)
                Text("PTS").frame(width: 32, alignment: .trailing)
            }
            .font(.caption2.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            ForEach(rows.indices, id: \.self) { i in
                let team = rows[i]
                HStack(spacing: 4) {
                    Text(String(i + 1)).frame(width: 20, alignment: .trailing)
                    Text(team.code).frame(maxWidth: .infinity, alignment: .leading)
                    Text(String(team.gp)).frame(width: 25, alignment: .trailing)
                    Text(String(team.wins)).frame(width: 23, alignment: .trailing)
                    Text(String(team.losses)).frame(width: 23, alignment: .trailing)
                    Text(String(team.ot)).frame(width: 24, alignment: .trailing)
                    Text(String(team.points)).frame(width: 32, alignment: .trailing)
                        .fontWeight(.bold)
                }
                .font(.caption.monospacedDigit())
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(i.isMultiple(of: 2) ? Color.primary.opacity(0.035) : Color.clear)
            }
        }
        .padding(.bottom, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct FullPlayoffBracketGraphic: View {
    let picture: ModelPlayoffPicture
    let teams: [ModelTeam]

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    // Extra vertical room for Mac and iPad; iPhone retains compact proportions.
    private var height: CGFloat { horizontalSizeClass == .compact ? 650 : 930 }
    private var verticalScale: CGFloat { height / 650 }
    // Round-aware sizes stay within each bracket column, scaling on Mac
    // without letting adjacent conference/cup circles overlap on iPhone.
    private func sizeForRound(_ round: Int, step: CGFloat) -> CGFloat {
        let caps: [CGFloat] = [60, 92, 110, 128, 140]
        let factors: [CGFloat] = [0.75, 0.82, 0.88, 0.90, 0.90]
        return min(caps[round], max(26, step * factors[round]))
    }

    private var round1Y: [CGFloat] { [90, 138, 194, 242, 416, 464, 520, 568].map { $0 * verticalScale } }
    private var round2Y: [CGFloat] { [114, 218, 440, 544].map { $0 * verticalScale } }
    private var conferenceFinalY: [CGFloat] { [166, 492].map { $0 * verticalScale } }
    private var conferenceChampionY: CGFloat { 328 * verticalScale }
    private var cupWinnerY: CGFloat { 328 * verticalScale }

    private var eastRound1: [String] { let pairs = picture.east.round1.map(normalizedPair); return (Array(pairs.dropFirst(2)) + Array(pairs.prefix(2))).flatMap { $0 } }
    private var eastRound2: [String] { let pairs = picture.east.round2.map(normalizedPair); return (Array(pairs.dropFirst(1)) + Array(pairs.prefix(1))).flatMap { $0 } }
    private var eastFinal: [String] { Array(normalizedPair(picture.east.finalMatchup).reversed()) }
    private var westRound1: [String] { picture.west.round1.flatMap(normalizedPair) }
    private var westRound2: [String] { picture.west.round2.flatMap(normalizedPair) }
    private var westFinal: [String] { normalizedPair(picture.west.finalMatchup) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Western Conference")
                Spacer()
                Text("Stanley Cup")
                Spacer()
                Text("Eastern Conference")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            GeometryReader { proxy in
                // ICEOMETRICS_BRACKET_R1_EDGE_INSET_V1
                // Reserve half of the outermost circle within the view;
                // this keeps the logo + circle inside both Mac and iPhone bounds.
                let roundOneInset = min(CGFloat(46), max(CGFloat(24), proxy.size.width * 0.04))
                let leftEdge: CGFloat = roundOneInset
                let rightEdge = max(leftEdge + 120, proxy.size.width - roundOneInset)
                let centerX = proxy.size.width / 2
                let step = max(30, (centerX - leftEdge) / 4)
                let r1Size = min(
                    sizeForRound(0, step: step),
                    2 * roundOneInset - 6
                )
                let r2Size = sizeForRound(1, step: step)
                let cfSize = sizeForRound(2, step: step)
                let championSize = sizeForRound(3, step: step)
                let cupSize = sizeForRound(4, step: step)

                let e1 = leftEdge
                let e2 = leftEdge + step
                let e3 = leftEdge + step * 2
                let e4 = leftEdge + step * 3

                let w1 = rightEdge
                let w2 = rightEdge - step
                let w3 = rightEdge - step * 2
                let w4 = rightEdge - step * 3

                ZStack {
                    Canvas { context, _ in
                        drawConnections(
                            context: &context,
                            fromX: e1 + r1Size / 2,
                            toX: e2 - r2Size / 2,
                            sourcePairs: round1Pairs,
                            destinationY: round2Y
                        )
                        drawConnections(
                            context: &context,
                            fromX: e2 + r2Size / 2,
                            toX: e3 - cfSize / 2,
                            sourcePairs: round2Pairs,
                            destinationY: conferenceFinalY
                        )
                        drawConnections(
                            context: &context,
                            fromX: e3 + cfSize / 2,
                            toX: e4 - championSize / 2,
                            sourcePairs: [(conferenceFinalY[0], conferenceFinalY[1])],
                            destinationY: [conferenceChampionY]
                        )

                        drawConnections(
                            context: &context,
                            fromX: w1 - r1Size / 2,
                            toX: w2 + r2Size / 2,
                            sourcePairs: round1Pairs,
                            destinationY: round2Y
                        )
                        drawConnections(
                            context: &context,
                            fromX: w2 - r2Size / 2,
                            toX: w3 + cfSize / 2,
                            sourcePairs: round2Pairs,
                            destinationY: conferenceFinalY
                        )
                        drawConnections(
                            context: &context,
                            fromX: w3 - cfSize / 2,
                            toX: w4 + championSize / 2,
                            sourcePairs: [(conferenceFinalY[0], conferenceFinalY[1])],
                            destinationY: [conferenceChampionY]
                        )

                        drawFinalConnection(
                            context: &context,
                            fromX: e4 + championSize / 2,
                            toX: centerX - cupSize / 2,
                            y: conferenceChampionY
                        )
                        drawFinalConnection(
                            context: &context,
                            fromX: w4 - championSize / 2,
                            toX: centerX + cupSize / 2,
                            y: conferenceChampionY
                        )
                    }

                    roundHeader("R1", x: e1)
                    roundHeader("R2", x: e2)
                    roundHeader("CF", x: e3)
                    roundHeader("R1", x: w1)
                    roundHeader("R2", x: w2)
                    roundHeader("CF", x: w3)
                    roundHeader("Cup", x: centerX)

                    Text("CENTRAL")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .position(x: e1 + 36, y: 48 * verticalScale)
                    Text("PACIFIC")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .position(x: e1 + 36, y: 365 * verticalScale)
                    Text("METRO")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .position(x: w1 - 36, y: 48 * verticalScale)
                    Text("ATLANTIC")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .position(x: w1 - 36, y: 365 * verticalScale)

                    bracketNodes(westRound1, x: e1, y: round1Y, size: r1Size)
                    bracketNodes(westRound2, x: e2, y: round2Y, size: r2Size)
                    bracketNodes(westFinal, x: e3, y: conferenceFinalY, size: cfSize)
                    bracketNodes(
                        picture.west.champion.isEmpty ? [""] : [picture.west.champion],
                        x: e4,
                        y: [conferenceChampionY],
                        size: championSize
                    )

                    bracketNodes(eastRound1, x: w1, y: round1Y, size: r1Size)
                    bracketNodes(eastRound2, x: w2, y: round2Y, size: r2Size)
                    bracketNodes(eastFinal, x: w3, y: conferenceFinalY, size: cfSize)
                    bracketNodes(
                        picture.east.champion.isEmpty ? [""] : [picture.east.champion],
                        x: w4,
                        y: [conferenceChampionY],
                        size: championSize
                    )

                    bracketNodes(
                        picture.champion.isEmpty ? [""] : [picture.champion],
                        x: centerX,
                        y: [cupWinnerY],
                        size: cupSize,
                        emphasized: true
                    )
                }
            }
            .frame(height: height)
        }
        .padding(.vertical, 4)
    }

    private var round1Pairs: [(CGFloat, CGFloat)] {
        [
            (round1Y[0], round1Y[1]),
            (round1Y[2], round1Y[3]),
            (round1Y[4], round1Y[5]),
            (round1Y[6], round1Y[7]),
        ]
    }

    private var round2Pairs: [(CGFloat, CGFloat)] {
        [
            (round2Y[0], round2Y[1]),
            (round2Y[2], round2Y[3]),
        ]
    }

    @ViewBuilder
    private func roundHeader(_ title: String, x: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .position(x: x, y: 7)
    }

    @ViewBuilder
    private func bracketNodes(
        _ codes: [String],
        x: CGFloat,
        y: [CGFloat],
        size: CGFloat,
        emphasized: Bool = false
    ) -> some View {
        ForEach(Array(y.enumerated()), id: \.offset) { index, yPosition in
            let code = codes.indices.contains(index) ? codes[index] : ""

            ZStack {
                Circle()
                    .fill(
                        emphasized
                            ? Color.accentColor.opacity(0.15)
                            : Color.primary.opacity(0.04)
                    )
                Circle()
                    .stroke(
                        emphasized
                            ? Color.accentColor.opacity(0.65)
                            : Color.primary.opacity(0.12),
                        lineWidth: emphasized ? 1.2 : 0.6
                    )

                if code.isEmpty {
                    Circle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: 4, height: 4)
                } else {
                    ModelTeamLogo(
                        team: teamForCode(code, teams: teams),
                        code: code,
                        size: size - 3
                    )
                }
            }
            .frame(width: size + 2, height: size + 2)
            .position(x: x, y: yPosition)
            .accessibilityLabel(
                code.isEmpty
                    ? "To be determined"
                    : (teamForCode(code, teams: teams)?.name ?? code)
            )
        }
    }

    private func drawConnections(
        context: inout GraphicsContext,
        fromX: CGFloat,
        toX: CGFloat,
        sourcePairs: [(CGFloat, CGFloat)],
        destinationY: [CGFloat]
    ) {
        let elbowX = fromX + (toX - fromX) * 0.48

        for index in sourcePairs.indices {
            guard destinationY.indices.contains(index) else { continue }
            let pair = sourcePairs[index]
            let targetY = destinationY[index]

            var path = Path()
            path.move(to: CGPoint(x: fromX, y: pair.0))
            path.addLine(to: CGPoint(x: elbowX, y: pair.0))
            path.addLine(to: CGPoint(x: elbowX, y: pair.1))
            path.addLine(to: CGPoint(x: fromX, y: pair.1))

            let midpoint = (pair.0 + pair.1) / 2
            path.move(to: CGPoint(x: elbowX, y: midpoint))
            path.addLine(to: CGPoint(x: toX, y: targetY))

            context.stroke(
                path,
                with: .color(Color.primary.opacity(0.27)),
                style: StrokeStyle(lineWidth: 0.85, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func drawFinalConnection(
        context: inout GraphicsContext,
        fromX: CGFloat,
        toX: CGFloat,
        y: CGFloat
    ) {
        var path = Path()
        path.move(to: CGPoint(x: fromX, y: y))
        path.addLine(to: CGPoint(x: toX, y: y))
        context.stroke(
            path,
            with: .color(Color.primary.opacity(0.32)),
            style: StrokeStyle(lineWidth: 1, lineCap: .round)
        )
    }

    private func normalizedPair(_ raw: [String]) -> [String] {
        let values = raw.filter { !$0.isEmpty }
        switch values.count {
        case 0: return ["", ""]
        case 1: return [values[0], ""]
        default: return Array(values.prefix(2))
        }
    }
}

// MARK: - Magic / Tragic

private enum MagicDisplayMode: String, CaseIterable, Identifiable {
    case magic = "Magic"
    case tragic = "Tragic"
    case both = "Both"

    var id: String { rawValue }
}

// ICEOMETRICS_NOTES_BATCH06_MAGIC_TRAGIC_SPLIT_V1
// Both sides scroll together because they are within one shared scroll view.
// On narrow iPhone screens, only the chosen mode is shown.
// ICEOMETRICS_NOTES_BIG_PASS_07_V1_MODELS
private struct MagicTragicPanel: View {
    let snapshot: ModelMagicTragic
    let teams: [ModelTeam]
    @AppStorage("iceometrics.models.magicTragic.mode") private var chosenMode = "Magic"
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var phoneMode: MagicDisplayMode {
        MagicDisplayMode(rawValue: chosenMode) == .tragic ? .tragic : .magic
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                if horizontalSizeClass == .compact {
                    ModelPanelHeader(
                        title: phoneMode == .magic ? "Magic Numbers" : "Tragic Numbers",
                        day: snapshot.day,
                        subtitle: "\(snapshot.gamesPerTeam)-game season"
                    )
                } else {
                    Text("As of \(snapshot.day) · \(snapshot.gamesPerTeam)-game season")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if horizontalSizeClass == .compact {
                    Picker("Mode", selection: $chosenMode) {
                        Text("Magic").tag("Magic")
                        Text("Tragic").tag("Tragic")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 235)
                }
            }

            if horizontalSizeClass == .compact {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(snapshot.conferences) { conference in
                            MagicConferenceTable(
                                conference: conference,
                                teams: teams,
                                mode: phoneMode
                            )
                        }
                    }
                    .padding(.bottom, 8)
                }
            } else {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    HStack(alignment: .top, spacing: 18) {
                        modeColumn(mode: .magic, title: "Magic Numbers")
                        modeColumn(mode: .tragic, title: "Tragic Numbers")
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func modeColumn(
        mode: MagicDisplayMode,
        title: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(.secondary)
            ForEach(snapshot.conferences) { conference in
                MagicConferenceTable(
                    conference: conference,
                    teams: teams,
                    mode: mode
                )
            }
        }
    }
}

private struct MagicConferenceTable: View {
    let conference: ModelMagicTragicConference
    let teams: [ModelTeam]
    let mode: MagicDisplayMode

    private let teamWidth: CGFloat = 90
    private let statWidth: CGFloat = 38

    private var cellWidth: CGFloat {
        mode == .both ? 74 : 48
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(conference.name)ern Conference")
                .font(.headline)

            VStack(spacing: 0) {
                headerRow

                ForEach(conference.rows) { row in
                    HStack(spacing: 0) {
                        teamCell(row.team)

                        numericCell(
                            String(
                                Int(row.points.rounded())
                            )
                        )

                        numericCell(
                            "\(row.gamesPlayed)"
                        )

                        numericCell(
                            "\(row.gamesRemaining)"
                        )

                        ForEach(
                            Array(conference.columns.indices),
                            id: \.self
                        ) { index in
                            ModelMagicCell(
                                text: value(
                                    row: row,
                                    index: index
                                )
                            )
                            .frame(
                                width: cellWidth,
                                height: 32
                            )
                            .overlay(alignment: .leading) {
                                if index == 0 {
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.55))
                                        .frame(width: 2.5)
                                }
                            }
                        }
                    }
                }
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: 9,
                    style: .continuous
                )
                .stroke(
                    Color.primary.opacity(0.10),
                    lineWidth: 1
                )
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 9,
                    style: .continuous
                )
            )
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            headerCell(
                "Team",
                width: teamWidth,
                alignment: .leading
            )
            headerCell("PTS", width: statWidth)
            headerCell("GP", width: statWidth)
            headerCell("GR", width: statWidth)

            ForEach(
                Array(conference.columns.enumerated()),
                id: \.offset
            ) { index, column in
                headerCell(
                    column,
                    width: cellWidth
                )
                .overlay(alignment: .leading) {
                    if index == 0 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.55))
                            .frame(width: 2.5)
                    }
                }
            }
        }
    }

    private func teamCell(
        _ code: String
    ) -> some View {
        HStack(spacing: 6) {
            ModelTeamLogo(
                team: teamForCode(
                    code,
                    teams: teams
                ),
                code: code,
                size: 24
            )

            Text(code)
                .font(.subheadline.weight(.semibold))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .frame(
            width: teamWidth,
            height: 32,
            alignment: .leading
        )
        .background(
            Color.primary.opacity(0.025)
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 0.5)
        }
    }

    private func numericCell(
        _ text: String
    ) -> some View {
        Text(text)
            .font(
                .system(
                    .caption,
                    design: .monospaced
                )
            )
            .frame(
                width: statWidth,
                height: 32
            )
            .background(
                Color.primary.opacity(0.018)
            )
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 0.5)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 0.5)
            }
    }

    private func headerCell(
        _ text: String,
        width: CGFloat,
        alignment: Alignment = .center
    ) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(
                .horizontal,
                alignment == .leading ? 5 : 0
            )
            .frame(
                width: width,
                height: 30,
                alignment: alignment
            )
            .background(
                Color.primary.opacity(0.055)
            )
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 0.5)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 0.5)
            }
    }

    private func value(
        row: ModelMagicTragicRow,
        index: Int
    ) -> String {
        let magic = index < row.magic.count
            ? row.magic[index]
            : ""
        let tragic = index < row.tragic.count
            ? row.tragic[index]
            : ""

        switch mode {
        case .magic:
            return magic
        case .tragic:
            return tragic
        case .both:
            if magic.isEmpty && tragic.isEmpty {
                return ""
            }
            return "\(magic) / \(tragic)"
        }
    }
}

private struct ModelMagicCell: View {
    let text: String

    var body: some View {
        Text(text)
            .font(
                .system(
                    .caption,
                    design: .monospaced
                )
                .weight(.semibold)
            )
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
            .background(background)
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 0.5)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 0.5)
            }
    }

    private var background: Color {
        if text.contains("*") {
            return Color.accentColor.opacity(0.18)
        }

        if text.contains("DNCD")
            || text.contains("MW") {
            return Color.accentColor.opacity(0.08)
        }

        if text.contains("X") {
            return Color.primary.opacity(0.018)
        }

        if text == "-" {
            return Color.primary.opacity(0.012)
        }

        return Color.primary.opacity(0.035)
    }
}

// MARK: - Point Probabilities

private struct PointProbabilitiesPanel: View {
    let snapshot: ModelPointProbabilities
    let teams: [ModelTeam]
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.iceometricsFavoritePaletteTeamCode) private var favoritePaletteTeamCode

    private let teamWidth: CGFloat = 90
    private let predictionWidth: CGFloat = 46
    private let probabilityWidth: CGFloat = 48

    // Hide probability columns with no finite positive value in ANY row.
    // Retain original indices to preserve correct row-data alignment.
    private var visibleProbabilityIndices: [Int] {
        snapshot.values.indices.filter { index in
            snapshot.rows.contains { row in
                index < row.probabilities.count
                    && row.probabilities[index].isFinite
                    && row.probabilities[index] > 0
            }
        }
    }

    // A mode-focused scale: near-zero values stay close to gray.
    // 10% of the row peak is neutral; full bad lies below zero.
    // ICEOMETRICS_POINTS_PROBABILITY_TINY_BAD_V1
    private func modeFocusedScore(_ probability: Double, peak: Double) -> Double {
        guard peak > 0, probability.isFinite else { return 0 }

        // Explicit zero is an empty result, not a bad result: neutral gray.
        if probability <= 0 { return 0 }

        // Model values are proportions: 0.0001 == 0.01%.
        // Positive values displayed as <.01% must hit full BAD intensity.
        let tinyLimit = 0.0001
        if probability < tinyLimit { return -1 }

        // Work with THIS row's distribution, never a fixed 0...100% scale.
        // Reach neutral much earlier (6% of row peak) than the previous 10%.
        let grayPoint = peak * 0.06
        if probability < grayPoint && grayPoint > tinyLimit {
            let fraction = min(max(
                (probability - tinyLimit) / (grayPoint - tinyLimit),
                0
            ), 1)
            // Curved negative side: strongly bad for tiny values, but fades
            // toward gray earlier across the low end of the distribution.
            return -pow(1 - fraction, 2.0)
        }

        // Keep mid-range values relatively neutral for longer, then grow
        // toward full good as they approach the row's highest probability.
        let denominator = max(peak - max(grayPoint, tinyLimit), 0.000000000001)
        let fraction = min(max(
            (probability - max(grayPoint, tinyLimit)) / denominator,
            0
        ), 1)
        return pow(fraction, 1.8)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModelPanelHeader(
                title: "Point Probabilities",
                day: snapshot.day
            )

            ScrollView(
                [.horizontal, .vertical],
                showsIndicators: true
            ) {
                LazyVStack(
                    spacing: 0,
                    pinnedViews: [.sectionHeaders]
                ) {
                    Section {
                        ForEach(snapshot.rows) { row in
                            probabilityRow(row)
                        }
                    } header: {
                        headerRow
                            .background(.background)
                            .zIndex(10)
                    }
                }
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 9,
                        style: .continuous
                    )
                    .stroke(
                        Color.primary.opacity(0.10),
                        lineWidth: 1
                    )
                }
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 9,
                        style: .continuous
                    )
                )
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            headerCell(
                "Team",
                width: teamWidth,
                alignment: .leading
            )

            headerCell(
                "Pred",
                width: predictionWidth
            )

            ForEach(visibleProbabilityIndices, id: \.self) { index in
                headerCell(
                    "\(snapshot.values[index])",
                    width: probabilityWidth
                )
            }
        }
    }

    private func probabilityRow(
        _ row: ModelPointProbabilityRow
    ) -> some View {
        let rowMax = row.probabilities.max() ?? 0

        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                ModelTeamLogo(
                    team: teamForCode(
                        row.team,
                        teams: teams
                    ),
                    code: row.team,
                    size: 24
                )

                Text(row.team)
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 3)
            .frame(
                width: teamWidth,
                height: 32,
                alignment: .leading
            )
            .background(
                Color.primary.opacity(0.025)
            )
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 0.5)
            }

            Text("\(row.prediction)")
                .font(
                    .system(
                        .caption,
                        design: .monospaced
                    )
                    .weight(.bold)
                )
                .frame(
                    width: predictionWidth,
                    height: 32
                )
                .background(
                    Color.accentColor.opacity(0.08)
                )
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.10))
                        .frame(width: 1)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 0.5)
                }

            ForEach(
                visibleProbabilityIndices,
                id: \.self
            ) { index in
                let probability = index < row.probabilities.count
                    ? row.probabilities[index]
                    : 0

                Text(
                    formatModelProbability(
                        probability
                    )
                )
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                .font(
                    .system(
                        .caption2,
                        design: .monospaced
                    )
                )
                .frame(
                    width: probabilityWidth,
                    height: 32
                )
                .background(
                    probability.isFinite
                            ? TeamPerformancePalette.cellColor(
                            teamCode: favoritePaletteTeamCode ?? "",
                            score: modeFocusedScore(probability, peak: rowMax),
                            scheme: colorScheme
                        )
                        : Color.clear
                )
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.10))
                        .frame(width: 1)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 0.5)
                }
            }
        }
    }

    private func headerCell(
        _ text: String,
        width: CGFloat,
        alignment: Alignment = .center
    ) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(
                .horizontal,
                alignment == .leading ? 8 : 0
            )
            .frame(
                width: width,
                height: 30,
                alignment: alignment
            )
            .background(
                Color.primary.opacity(0.055)
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 0.5)
            }
    }
}

// MARK: - Playoff Win Probabilities

private struct PlayoffWinProbabilitiesPanel: View {
    let snapshot: ModelPlayoffWinProbabilities
    let teams: [ModelTeam]
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModelPanelHeader(
                title: "Playoff Win Probabilities",
                day: snapshot.day
            )

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    if let conference = snapshot.rounds.first(where: { $0.title == "Conference Finals" }),
                       let cup = snapshot.rounds.first(where: { $0.title == "Stanley Cup Final" }) {
                        ForEach(snapshot.rounds.filter {
                            $0.title != "Conference Finals" && $0.title != "Stanley Cup Final"
                        }) { round in
                            roundSection(round)
                        }

                        // Three cards across on wide Mac windows; conference
                        // finals left and the Cup on the FAR RIGHT. Reduce to
                        // two columns when necessary, then stack on iPhone.
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 14) {
                                roundSection(conference, minimum: 430)
                                    .frame(width: 880)
                                Spacer(minLength: 0)
                                roundSection(cup, minimum: 430)
                                    .frame(width: 440)
                            }
                            HStack(alignment: .top, spacing: 14) {
                                roundSection(conference, minimum: 390)
                                    .frame(width: 410)
                                Spacer(minLength: 0)
                                roundSection(cup, minimum: 390)
                                    .frame(width: 410)
                            }
                            VStack(alignment: .leading, spacing: 18) {
                                roundSection(conference, minimum: 300)
                                roundSection(cup, minimum: 300)
                            }
                        }
                    } else {
                        ForEach(snapshot.rounds) { round in
                            roundSection(round)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }

    private func roundSection(
        _ round: ModelWinRound,
        minimum: CGFloat? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(round.title)
                .font(.headline)
            LazyVGrid(
                columns: [GridItem(
                    .adaptive(
                        minimum: minimum ?? (horizontalSizeClass == .compact ? 300 : 430),
                        maximum: 560
                    ),
                    spacing: 12
                )],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(round.series) { series in
                    ModelSeriesProbabilityCard(series: series, teams: teams)
                }
            }
        }
    }

}

private struct ModelSeriesProbabilityCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.iceometricsFavoritePaletteTeamCode) private var favoritePaletteTeamCode
    let series: ModelSeriesProbability
    let teams: [ModelTeam]

    // Evaluate all ten numerical cells as one table, not row-by-row.
    // Exactly one highest-probability cell gets the accent highlight.
    private var highestCellIndex: Int {
        // Compare only the eight *exact* outcomes (A/B in 4/5/6/7).
        // The Win column is an aggregate of four outcomes, not another outcome.
        // Keep the first outcome on ties, matching Python's max(...) ordering.
        let outcomes = Array(series.aProbabilities.prefix(4))
            + Array(series.bProbabilities.prefix(4))
        guard !outcomes.isEmpty else { return 0 }
        return outcomes.indices.reduce(0) { current, index in
            outcomes[index] > outcomes[current] + 0.0000000001
                ? index : current
        }
    }

    private var displayedPrediction: String {
        let index = highestCellIndex
        return "\(index < 4 ? series.a : series.b) in \(4 + index % 4)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                ModelTeamLogo(
                    team: teamForCode(
                        series.a,
                        teams: teams
                    ),
                    code: series.a,
                    size: 28
                )

                Text(series.a)
                    .font(.headline)

                Text("vs")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ModelTeamLogo(
                    team: teamForCode(
                        series.b,
                        teams: teams
                    ),
                    code: series.b,
                    size: 28
                )

                Text(series.b)
                    .font(.headline)

                Spacer()

                Text(displayedPrediction)
                    .font(.caption.weight(.semibold))
                    .padding(
                        .horizontal,
                        8
                    )
                    .padding(
                        .vertical,
                        4
                    )
                    .background(
                        Color.accentColor.opacity(0.10),
                        in: Capsule()
                    )
            }

            Grid(
                horizontalSpacing: 0,
                verticalSpacing: 0
            ) {
                GridRow {
                    probabilityHeader("Team")
                    probabilityHeader("Win")
                    probabilityHeader("in 4")
                    probabilityHeader("in 5")
                    probabilityHeader("in 6")
                    probabilityHeader("in 7")
                }

                seriesProbabilityRow(
                    team: series.a,
                    winProbability: series.aWin,
                    probabilities: series.aProbabilities,
                    probabilityOffset: 0
                )

                seriesProbabilityRow(
                    team: series.b,
                    winProbability: series.bWin,
                    probabilities: series.bProbabilities,
                    probabilityOffset: 4
                )
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 7,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 7,
                    style: .continuous
                )
                .stroke(
                    Color.primary.opacity(0.10),
                    lineWidth: 1
                )
            }

            if series.aWins > 0
                || series.bWins > 0 {
                Text(
                    "Series: \(series.a) \(series.aWins)–\(series.bWins) \(series.b)"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(9)
        .background(
            Color.primary.opacity(0.025),
            in: RoundedRectangle(
                cornerRadius: 11,
                style: .continuous
            )
        )
    }

    @ViewBuilder
    private func seriesProbabilityRow(
        team: String,
        winProbability: Double,
        probabilities: [Double],
        probabilityOffset: Int
    ) -> some View {
        GridRow {
            HStack(spacing: 5) {
                ModelTeamLogo(
                    team: teamForCode(
                        team,
                        teams: teams
                    ),
                    code: team,
                    size: 21
                )

                Text(team)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(
                minWidth: 70,
                minHeight: 30,
                alignment: .leading
            )
            .padding(.horizontal, 4)
            .background(Color.primary.opacity(0.018))

            probabilityCell(
                winProbability,
                teamCode: team,
                emphasis: team.caseInsensitiveCompare(series.winner) == .orderedSame
                    || (series.winner.isEmpty
                        && winProbability > (probabilityOffset == 0 ? series.bWin : series.aWin))
            )

            ForEach(0..<4, id: \.self) { index in
                probabilityCell(
                    index < probabilities.count
                        ? probabilities[index]
                        : 0,
                    teamCode: team,
                    emphasis: probabilityOffset + index == highestCellIndex
                )
            }
        }
    }

    private func probabilityHeader(
        _ text: String
    ) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .frame(
                maxWidth: .infinity,
                minHeight: 28
            )
            .padding(.horizontal, 2)
            .background(
                Color.primary.opacity(0.055)
            )
    }

    private func probabilityCell(
        _ value: Double,
        teamCode: String,
        emphasis: Bool
    ) -> some View {
        Text(
            formatModelProbability(value)
        )
        .foregroundStyle(.primary)
        .font(
            .system(
                .caption2,
                design: .monospaced
            )
            .weight(
                emphasis
                    ? .bold
                    : .regular
            )
        )
        .frame(
            maxWidth: .infinity,
            minHeight: 30
        )
        .padding(.horizontal, 2)
        .background(
            emphasis
                ? Color.accentColor.opacity(0.18)
                : Color.primary.opacity(0.018)
        )
        .overlay(alignment: .bottom) {
            if emphasis {
                Rectangle().fill(Color.accentColor).frame(height: 2)
            }
        }
    }
}

// MARK: - Shared model helpers

private struct ModelTeamLogo: View {
    let team: ModelTeam?
    let code: String
    let size: CGFloat

    var body: some View {
        AsyncImage(
            url: team?.logoURL
        ) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()

            case .failure:
                fallback

            case .empty:
                ProgressView()
                    .controlSize(.mini)

            @unknown default:
                fallback
            }
        }
        .frame(
            width: size,
            height: size
        )
    }

    private var fallback: some View {
        Image(systemName: "hockey.puck.fill")
            .resizable()
            .scaledToFit()
            .padding(size * 0.20)
            .foregroundStyle(.secondary)
    }
}

private func teamForCode(
    _ code: String,
    teams: [ModelTeam]
) -> ModelTeam? {
    teams.first {
        $0.code.caseInsensitiveCompare(code)
            == .orderedSame
    }
}

private func formatModelProbability(
    _ probability: Double
) -> String {
    guard probability > 0 else {
        return ""
    }

    let percent = probability * 100

    if percent < 0.01 {
        return "<.01%"
    }

    return String(
        format: "%.2f%%",
        percent
    )
}

private func displayModelDay(
    _ raw: String
) -> String {
    let parts = raw.split(separator: "-")
    guard parts.count == 3,
          let year = Int(parts[0]),
          let month = Int(parts[1]),
          let day = Int(parts[2]) else {
        return raw
    }

    var components = DateComponents()
    components.calendar = Calendar(
        identifier: .gregorian
    )
    components.year = year
    components.month = month
    components.day = day

    guard let date = components.date else {
        return raw
    }

    return date.formatted(
        .dateTime
            .day()
            .month(.abbreviated)
            .year()
            .locale(
                Locale(identifier: "en_GB")
            )
    )
}

#Preview {
    NavigationStack {
        ModelsView()
    }
}
