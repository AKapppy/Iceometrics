import SwiftUI
import WidgetKit

struct TeamGameEntry: TimelineEntry {
    let date: Date
    let game: WidgetGame
}

struct TeamGameProvider: TimelineProvider {
    func placeholder(in context: Context) -> TeamGameEntry {
        TeamGameEntry(
            date: Date(),
            game: WidgetSampleData.teamGame
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (TeamGameEntry) -> Void
    ) {
        completion(
            TeamGameEntry(
                date: Date(),
                game: WidgetSampleData.teamGame
            )
        )
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<TeamGameEntry>) -> Void
    ) {
        let entry = TeamGameEntry(
            date: Date(),
            game: WidgetSampleData.teamGame
        )

        let refresh = Date().addingTimeInterval(15 * 60)

        completion(
            Timeline(
                entries: [entry],
                policy: .after(refresh)
            )
        )
    }
}

struct ProbabilitySplitBackground: View {
    let game: WidgetGame

    private var awayShare: Double {
        max(0, min(1, game.awayProbability))
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let split = width * awayShare
            let seamWidth: CGFloat = 34

            ZStack {
                HStack(spacing: 0) {
                    Color(widgetHex: game.awayTeam.accentHex)
                        .frame(width: split)

                    Color(widgetHex: game.homeTeam.accentHex)
                        .frame(maxWidth: .infinity)
                }

                Rectangle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(
                                    color: Color(
                                        widgetHex:
                                            game.awayTeam.accentHex
                                    ).opacity(0),
                                    location: 0
                                ),
                                .init(
                                    color: .black.opacity(0.22),
                                    location: 0.50
                                ),
                                .init(
                                    color: Color(
                                        widgetHex:
                                            game.homeTeam.accentHex
                                    ).opacity(0),
                                    location: 1
                                )
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: seamWidth)
                    .offset(
                        x: split
                        - width / 2
                    )

                LinearGradient(
                    colors: [
                        .black.opacity(0.08),
                        .black.opacity(0.28)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipped()
        }
    }
}

struct TeamGameWidgetView: View {
    @Environment(\.widgetFamily)
    private var family

    let entry: TeamGameEntry

    var body: some View {
        ZStack {
            ProbabilitySplitBackground(
                game: entry.game
            )

            if family == .systemSmall {
                smallView
            } else {
                mediumView
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    private var smallView: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                teamBadge(
                    entry.game.awayTeam,
                    alignment: .leading
                )

                Spacer()

                teamBadge(
                    entry.game.homeTeam,
                    alignment: .trailing
                )
            }

            Spacer()

            if isScoreState {
                Text(
                    "\(entry.game.awayScore)  \(entry.game.homeScore)"
                )
                .font(
                    .system(
                        size: 34,
                        weight: .black,
                        design: .rounded
                    )
                )
                .monospacedDigit()
            } else {
                Text("VS")
                    .font(
                        .system(
                            size: 24,
                            weight: .black,
                            design: .rounded
                        )
                    )
            }

            Text(entry.game.detail)
                .font(.caption2.weight(.bold))
                .opacity(0.82)
                .padding(.top, 2)

            Spacer()

            HStack {
                predictionText(
                    entry.game.awayProbability
                )

                Spacer()

                predictionText(
                    entry.game.homeProbability
                )
            }
        }
        .foregroundStyle(.white)
        .padding(14)
    }

    private var mediumView: some View {
        HStack(spacing: 0) {
            VStack(
                alignment: .leading,
                spacing: 8
            ) {
                teamBadge(
                    entry.game.awayTeam,
                    alignment: .leading
                )

                predictionText(
                    entry.game.awayProbability,
                    large: true
                )
            }

            Spacer(minLength: 8)

            VStack(spacing: 4) {
                statusPill

                if isScoreState {
                    Text(
                        "\(entry.game.awayScore) – \(entry.game.homeScore)"
                    )
                    .font(
                        .system(
                            size: 38,
                            weight: .black,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                } else {
                    Text("VS")
                        .font(
                            .system(
                                size: 28,
                                weight: .black,
                                design: .rounded
                            )
                        )
                }

                Text(entry.game.detail)
                    .font(.caption.weight(.bold))
                    .opacity(0.82)
            }

            Spacer(minLength: 8)

            VStack(
                alignment: .trailing,
                spacing: 8
            ) {
                teamBadge(
                    entry.game.homeTeam,
                    alignment: .trailing
                )

                predictionText(
                    entry.game.homeProbability,
                    large: true
                )
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var isScoreState: Bool {
        switch entry.game.phase {
        case .live, .intermission, .final:
            true
        default:
            false
        }
    }

    private var statusPill: some View {
        Text(statusText)
            .font(.system(size: 9, weight: .black))
            .tracking(0.8)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(.black.opacity(0.22))
            )
    }

    private var statusText: String {
        switch entry.game.phase {
        case .live:
            "LIVE"
        case .intermission:
            "INTERMISSION"
        case .starting:
            "STARTING"
        case .final:
            "FINAL"
        case .scheduled:
            "PREGAME"
        }
    }

    private func teamBadge(
        _ team: WidgetTeam,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(team.abbreviation)
                .font(
                    .system(
                        size: 20,
                        weight: .black,
                        design: .rounded
                    )
                )

            Text(team.name.uppercased())
                .font(.system(size: 7, weight: .bold))
                .opacity(0.65)
        }
    }

    private func predictionText(
        _ probability: Double,
        large: Bool = false
    ) -> some View {
        Text(
            "\(Int((probability * 100).rounded()))%"
        )
        .font(
            .system(
                size: large ? 24 : 15,
                weight: .black,
                design: .rounded
            )
        )
        .monospacedDigit()
    }
}

struct TeamGameWidget: Widget {
    let kind = "TeamGameWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: TeamGameProvider()
        ) { entry in
            TeamGameWidgetView(entry: entry)
        }
        .configurationDisplayName("Team Game")
        .description(
            "Follow one team's current or upcoming game."
        )
        .supportedFamilies([
            .systemSmall,
            .systemMedium
        ])
    }
}
