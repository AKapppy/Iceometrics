
import SwiftUI
import Foundation

struct ModelsView: View {
    @StateObject private var viewModel: ModelsViewModel
    @State private var selectedSection: ModelsSection = .playoffPicture
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
                            teams: snapshot.teams
                        )
                    } else {
                        ModelUnavailableView(
                            title: "Playoff picture unavailable"
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
    case magicTragic
    case pointProbabilities
    case playoffWinProbabilities

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playoffPicture:
            "Playoff Picture"
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
        case .magicTragic: "Magic"
        case .pointProbabilities: "Points"
        case .playoffWinProbabilities: "Series"
        }
    }
}

private struct ModelTabButtonStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func makeBody(
        configuration: Configuration
    ) -> some View {
        configuration.label
            .padding(.horizontal, horizontalSizeClass == .compact ? 8 : 12)
            .padding(.vertical, horizontalSizeClass == .compact ? 6 : 7)
            .foregroundStyle(
                isSelected
                    ? Color.white
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

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                ModelPanelHeader(
                    title: "Playoff Picture",
                    day: picture.day,
                    subtitle: picture.mode
                )

                FullPlayoffBracketGraphic(
                    picture: picture,
                    teams: teams
                )
            }
            .padding(.bottom, 8)
        }
    }
}

private struct FullPlayoffBracketGraphic: View {
    let picture: ModelPlayoffPicture
    let teams: [ModelTeam]

    private let height: CGFloat = 222
    private let logoSize: CGFloat = 18

    private let round1Y: [CGFloat] = [24, 44, 68, 88, 132, 152, 176, 196]
    private let round2Y: [CGFloat] = [34, 78, 142, 186]
    private let conferenceFinalY: [CGFloat] = [56, 164]
    private let conferenceChampionY: CGFloat = 110
    private let cupWinnerY: CGFloat = 110

    private var eastRound1: [String] { picture.east.round1.flatMap(normalizedPair) }
    private var eastRound2: [String] { picture.east.round2.flatMap(normalizedPair) }
    private var eastFinal: [String] { normalizedPair(picture.east.finalMatchup) }
    private var westRound1: [String] { picture.west.round1.flatMap(normalizedPair) }
    private var westRound2: [String] { picture.west.round2.flatMap(normalizedPair) }
    private var westFinal: [String] { normalizedPair(picture.west.finalMatchup) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Eastern Conference")
                Spacer()
                Text("Stanley Cup")
                Spacer()
                Text("Western Conference")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            GeometryReader { proxy in
                let leftEdge: CGFloat = 12
                let rightEdge = max(leftEdge + 240, proxy.size.width - 12)
                let centerX = proxy.size.width / 2
                let step = max(30, (centerX - leftEdge) / 4)

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
                            fromX: e1 + logoSize / 2,
                            toX: e2 - logoSize / 2,
                            sourcePairs: round1Pairs,
                            destinationY: round2Y
                        )
                        drawConnections(
                            context: &context,
                            fromX: e2 + logoSize / 2,
                            toX: e3 - logoSize / 2,
                            sourcePairs: round2Pairs,
                            destinationY: conferenceFinalY
                        )
                        drawConnections(
                            context: &context,
                            fromX: e3 + logoSize / 2,
                            toX: e4 - logoSize / 2,
                            sourcePairs: [(conferenceFinalY[0], conferenceFinalY[1])],
                            destinationY: [conferenceChampionY]
                        )

                        drawConnections(
                            context: &context,
                            fromX: w1 - logoSize / 2,
                            toX: w2 + logoSize / 2,
                            sourcePairs: round1Pairs,
                            destinationY: round2Y
                        )
                        drawConnections(
                            context: &context,
                            fromX: w2 - logoSize / 2,
                            toX: w3 + logoSize / 2,
                            sourcePairs: round2Pairs,
                            destinationY: conferenceFinalY
                        )
                        drawConnections(
                            context: &context,
                            fromX: w3 - logoSize / 2,
                            toX: w4 + logoSize / 2,
                            sourcePairs: [(conferenceFinalY[0], conferenceFinalY[1])],
                            destinationY: [conferenceChampionY]
                        )

                        drawFinalConnection(
                            context: &context,
                            fromX: e4 + logoSize / 2,
                            toX: centerX - logoSize / 2,
                            y: conferenceChampionY
                        )
                        drawFinalConnection(
                            context: &context,
                            fromX: w4 - logoSize / 2,
                            toX: centerX + logoSize / 2,
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

                    bracketNodes(eastRound1, x: e1, y: round1Y)
                    bracketNodes(eastRound2, x: e2, y: round2Y)
                    bracketNodes(eastFinal, x: e3, y: conferenceFinalY)
                    bracketNodes(
                        picture.east.champion.isEmpty ? [""] : [picture.east.champion],
                        x: e4,
                        y: [conferenceChampionY]
                    )

                    bracketNodes(westRound1, x: w1, y: round1Y)
                    bracketNodes(westRound2, x: w2, y: round2Y)
                    bracketNodes(westFinal, x: w3, y: conferenceFinalY)
                    bracketNodes(
                        picture.west.champion.isEmpty ? [""] : [picture.west.champion],
                        x: w4,
                        y: [conferenceChampionY]
                    )

                    bracketNodes(
                        picture.champion.isEmpty ? [""] : [picture.champion],
                        x: centerX,
                        y: [cupWinnerY],
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
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.secondary)
            .position(x: x, y: 7)
    }

    @ViewBuilder
    private func bracketNodes(
        _ codes: [String],
        x: CGFloat,
        y: [CGFloat],
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
                        size: logoSize - 3
                    )
                }
            }
            .frame(width: logoSize + 2, height: logoSize + 2)
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

private struct MagicTragicPanel: View {
    let snapshot: ModelMagicTragic
    let teams: [ModelTeam]

    @State private var mode: MagicDisplayMode = .both

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                ModelPanelHeader(
                    title: "Magic / Tragic",
                    day: snapshot.day,
                    subtitle: "\(snapshot.gamesPerTeam)-game season"
                )

                Spacer(minLength: 18)

                Picker(
                    "Mode",
                    selection: $mode
                ) {
                    ForEach(MagicDisplayMode.allCases) {
                        Text($0.rawValue)
                            .tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
            }

            ScrollView(
                [.horizontal, .vertical],
                showsIndicators: true
            ) {
                VStack(
                    alignment: .leading,
                    spacing: 18
                ) {
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
    }
}

private struct MagicConferenceTable: View {
    let conference: ModelMagicTragicConference
    let teams: [ModelTeam]
    let mode: MagicDisplayMode

    private let teamWidth: CGFloat = 116
    private let statWidth: CGFloat = 48

    private var cellWidth: CGFloat {
        mode == .both ? 84 : 60
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
                                height: 36
                            )
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
            ) { _, column in
                headerCell(
                    column,
                    width: cellWidth
                )
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
        .padding(.horizontal, 8)
        .frame(
            width: teamWidth,
            height: 36,
            alignment: .leading
        )
        .background(
            Color.primary.opacity(0.025)
        )
        .overlay(alignment: .bottom) {
            Divider()
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
                height: 36
            )
            .background(
                Color.primary.opacity(0.018)
            )
            .overlay(alignment: .leading) {
                Divider()
            }
            .overlay(alignment: .bottom) {
                Divider()
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
                height: 34,
                alignment: alignment
            )
            .background(
                Color.primary.opacity(0.055)
            )
            .overlay(alignment: .leading) {
                Divider()
            }
            .overlay(alignment: .bottom) {
                Divider()
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
                Divider()
            }
            .overlay(alignment: .bottom) {
                Divider()
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

    private let teamWidth: CGFloat = 116
    private let predictionWidth: CGFloat = 58
    private let probabilityWidth: CGFloat = 62

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

            ForEach(snapshot.values, id: \.self) { value in
                headerCell(
                    "\(value)",
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
            .padding(.horizontal, 8)
            .frame(
                width: teamWidth,
                height: 36,
                alignment: .leading
            )
            .background(
                Color.primary.opacity(0.025)
            )
            .overlay(alignment: .bottom) {
                Divider()
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
                    height: 36
                )
                .background(
                    Color.accentColor.opacity(0.08)
                )
                .overlay(alignment: .leading) {
                    Divider()
                }
                .overlay(alignment: .bottom) {
                    Divider()
                }

            ForEach(
                Array(snapshot.values.indices),
                id: \.self
            ) { index in
                let probability = index < row.probabilities.count
                    ? row.probabilities[index]
                    : 0
                let intensity = rowMax > 0
                    ? probability / rowMax
                    : 0

                Text(
                    formatModelProbability(
                        probability
                    )
                )
                .font(
                    .system(
                        .caption2,
                        design: .monospaced
                    )
                )
                .frame(
                    width: probabilityWidth,
                    height: 36
                )
                .background(
                    probability > 0
                        ? Color.accentColor.opacity(
                            0.035 + (0.23 * intensity)
                        )
                        : Color.clear
                )
                .overlay(alignment: .leading) {
                    Divider()
                }
                .overlay(alignment: .bottom) {
                    Divider()
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
                height: 34,
                alignment: alignment
            )
            .background(
                Color.primary.opacity(0.055)
            )
            .overlay(alignment: .leading) {
                Divider()
            }
            .overlay(alignment: .bottom) {
                Divider()
            }
    }
}

// MARK: - Playoff Win Probabilities

private struct PlayoffWinProbabilitiesPanel: View {
    let snapshot: ModelPlayoffWinProbabilities
    let teams: [ModelTeam]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModelPanelHeader(
                title: "Playoff Win Probabilities",
                day: snapshot.day
            )

            ScrollView(.vertical) {
                VStack(
                    alignment: .leading,
                    spacing: 18
                ) {
                    ForEach(snapshot.rounds) { round in
                        VStack(
                            alignment: .leading,
                            spacing: 10
                        ) {
                            Text(round.title)
                                .font(.headline)

                            LazyVGrid(
                                columns: [
                                    GridItem(
                                        .adaptive(
                                            minimum: 340,
                                            maximum: 520
                                        ),
                                        spacing: 12
                                    )
                                ],
                                alignment: .leading,
                                spacing: 12
                            ) {
                                ForEach(round.series) { series in
                                    ModelSeriesProbabilityCard(
                                        series: series,
                                        teams: teams
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }
}

private struct ModelSeriesProbabilityCard: View {
    let series: ModelSeriesProbability
    let teams: [ModelTeam]

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

                Text(series.prediction)
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
                    isWinner: series.winner == series.a
                )

                seriesProbabilityRow(
                    team: series.b,
                    winProbability: series.bWin,
                    probabilities: series.bProbabilities,
                    isWinner: series.winner == series.b
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
        .padding(11)
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
        isWinner: Bool
    ) -> some View {
        GridRow {
            HStack(spacing: 5) {
                ModelTeamLogo(
                    team: teamForCode(
                        team,
                        teams: teams
                    ),
                    code: team,
                    size: 22
                )

                Text(team)
                    .font(.caption.weight(.semibold))
            }
            .frame(
                maxWidth: .infinity,
                minHeight: 34,
                alignment: .leading
            )
            .padding(.horizontal, 6)
            .background(
                isWinner
                    ? Color.accentColor.opacity(0.10)
                    : Color.primary.opacity(0.018)
            )

            probabilityCell(
                winProbability,
                emphasis: true
            )

            ForEach(0..<4, id: \.self) { index in
                probabilityCell(
                    index < probabilities.count
                        ? probabilities[index]
                        : 0,
                    emphasis: false
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
                minHeight: 30
            )
            .padding(.horizontal, 4)
            .background(
                Color.primary.opacity(0.055)
            )
    }

    private func probabilityCell(
        _ value: Double,
        emphasis: Bool
    ) -> some View {
        Text(
            formatModelProbability(value)
        )
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
            minHeight: 34
        )
        .padding(.horizontal, 4)
        .background(
            emphasis
                ? Color.accentColor.opacity(0.055)
                : Color.primary.opacity(0.018)
        )
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
