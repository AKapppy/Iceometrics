import SwiftUI
import WidgetKit
import UIKit

struct TeamGameEntry: TimelineEntry {
    let date: Date
    let game: WidgetGame?
    let hasSnapshot: Bool
}

struct TeamGameProvider: TimelineProvider {
    func placeholder(
        in context: Context
    ) -> TeamGameEntry {
        TeamGameEntry(
            date: Date(),
            game: nil,
            hasSnapshot: false
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (TeamGameEntry) -> Void
    ) {
        completion(makeEntry())
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<TeamGameEntry>) -> Void
    ) {
        let entry = makeEntry()

        completion(
            Timeline(
                entries: [entry],
                policy: .after(
                    Date().addingTimeInterval(15 * 60)
                )
            )
        )
    }

    private func makeEntry() -> TeamGameEntry {
        guard let snapshot = WidgetSnapshotStore.load() else {
            return TeamGameEntry(
                date: Date(),
                game: nil,
                hasSnapshot: false
            )
        }

        let game = snapshot.games.first {
            $0.isToday && $0.containsTeam("NYR")
        }

        return TeamGameEntry(
            date: Date(),
            game: game,
            hasSnapshot: true
        )
    }
}

struct TeamGameWidgetView: View {
    let entry: TeamGameEntry

    var body: some View {
        Group {
            if let game = entry.game {
                gameCard(game)
            } else {
                emptyState
            }
        }
        .widgetURL(
            URL(string: "iceometrics://scoreboard")
        )
        .containerBackground(
            Color.clear,
            for: .widget
        )
    }

    private func gameCard(
        _ game: WidgetGame
    ) -> some View {
        ZStack {
            splitBackground(game)

            VStack(spacing: 0) {
                HStack {
                    teamLogo(
                        game.awayTeam
                    )

                    Spacer()

                    teamLogo(
                        game.homeTeam
                    )
                }
                .padding(.top, 8)
                .padding(.horizontal, 12)

                Spacer(minLength: 0)

                Text("VS")
                    .font(
                        .system(
                            size: 31,
                            weight: .black,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)

                Text(game.detail)
                    .font(
                        .system(
                            size: 11,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.top, 4)

                Spacer(minLength: 0)

                HStack {
                    probabilityText(
                        game.awayProbability
                    )

                    Spacer()

                    probabilityText(
                        game.homeProbability
                    )
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
    }

    private func splitBackground(
        _ game: WidgetGame
    ) -> some View {
        GeometryReader { proxy in
            let awayShare = max(
                0,
                min(
                    1,
                    game.awayProbability ?? 0.5
                )
            )

            let split =
                proxy.size.width * awayShare

            ZStack {
                HStack(spacing: 0) {
                    Color(
                        widgetHex:
                            game.awayTeam.accentHex
                    )
                    .frame(width: split)

                    Color(
                        widgetHex:
                            game.homeTeam.accentHex
                    )
                    .frame(maxWidth: .infinity)
                }
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height
                )

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                .white.opacity(0.08),
                                .black.opacity(0.18),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: 26,
                        height: proxy.size.height
                    )
                    .position(
                        x: split,
                        y: proxy.size.height / 2
                    )

                LinearGradient(
                    colors: [
                        .white.opacity(0.07),
                        .clear,
                        .black.opacity(0.16)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    @ViewBuilder
    private func teamLogo(
        _ team: WidgetTeam
    ) -> some View {
        if let image =
            WidgetTeamLogoStore.image(
                for: team
            ) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(
                    width: 38,
                    height: 38
                )
        } else {
            topCode(
                team.abbreviation
            )
            .frame(
                width: 38,
                height: 38
            )
        }
    }

    private func topCode(
        _ code: String
    ) -> some View {
        Text(code)
            .font(
                .system(
                    size: 13,
                    weight: .black,
                    design: .rounded
                )
            )
            .foregroundStyle(.white)
    }

    private func probabilityText(
        _ value: Double?
    ) -> some View {
        Text(percent(value))
            .font(
                .system(
                    size: 18,
                    weight: .black,
                    design: .rounded
                )
            )
            .foregroundStyle(.white)
            .monospacedDigit()
    }

    private func percent(
        _ value: Double?
    ) -> String {
        guard let value else {
            return "—"
        }

        return "\(Int((value * 100).rounded()))%"
    }

    private var emptyState: some View {
        ZStack {
            Color(
                red: 0.07,
                green: 0.08,
                blue: 0.10
            )

            VStack(spacing: 6) {
                Image(systemName: "hockey.puck.fill")
                    .font(.title2)

                Text(
                    entry.hasSnapshot
                    ? "NO NYR GAME"
                    : "OPEN ICEOMETRICS"
                )
                .font(.caption.bold())
            }
            .foregroundStyle(.white)
        }
    }
}

struct TeamGameWidget: Widget {
    let kind = "IceometricsTeamGamePolished"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: TeamGameProvider()
        ) { entry in
            TeamGameWidgetView(entry: entry)
        }
        .configurationDisplayName("Team Game")
        .description("Current or next featured game.")
        .supportedFamilies([
            .systemSmall
        ])
        .contentMarginsDisabled()
    }
}
