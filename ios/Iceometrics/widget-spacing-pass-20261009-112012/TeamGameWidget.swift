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
            $0.isToday
                && $0.containsTeam("NYR")
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
                ZStack {
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

                        LinearGradient(
                            colors: [
                                .black.opacity(0.02),
                                .black.opacity(0.22)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }

                    VStack(spacing: 8) {
                        HStack {
                            teamLogo(
                                game.awayTeam
                            )

                            Spacer()

                            teamLogo(
                                game.homeTeam
                            )
                        }

                        Spacer()

                        Text("VS")
                            .font(
                                .system(
                                    size: 30,
                                    weight: .black,
                                    design: .rounded
                                )
                            )

                        Text(game.detail)
                            .font(.caption)

                        Spacer()

                        HStack {
                            Text(percent(game.awayProbability))
                            Spacer()
                            Text(percent(game.homeProbability))
                        }
                        .font(.headline.bold())
                    }
                    .padding(14)
                    .foregroundStyle(.white)
                }
            } else {
                VStack(spacing: 6) {
                    Text("TEAM GAME")
                        .font(.caption.bold())

                    Text(
                        entry.hasSnapshot
                        ? "NO NYR GAME"
                        : "NO SNAPSHOT"
                    )
                    .font(.headline.bold())
                }
                .foregroundStyle(.white)
            }
        }
        .containerBackground(
            Color.blue,
            for: .widget
        )
    }

    @ViewBuilder
    private func teamLogo(
        _ team: WidgetTeam
    ) -> some View {
        if let image = cachedLogo(
            for: team
        ) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(
                    width: 48,
                    height: 48
                )
        } else {
            Text(team.abbreviation)
                .font(
                    .system(
                        size: 16,
                        weight: .black,
                        design: .rounded
                    )
                )
                .frame(
                    width: 48,
                    height: 48
                )
        }
    }

    private func cachedLogo(
        for team: WidgetTeam
    ) -> UIImage? {
        guard let root =
            FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier:
                    iceometricsWidgetAppGroup
            )
        else {
            return nil
        }

        let url =
            root
                .appendingPathComponent(
                    "WidgetTeamLogos",
                    isDirectory: true
                )
                .appendingPathComponent(
                    team.abbreviation
                        .uppercased()
                        + ".img"
                )

        guard let data =
            try? Data(
                contentsOf: url
            )
        else {
            return nil
        }

        return UIImage(data: data)
    }

    private func percent(
        _ value: Double?
    ) -> String {
        guard let value else {
            return "—"
        }

        return "\(Int((value * 100).rounded()))%"
    }
}

struct TeamGameWidget: Widget {
    let kind = "IceometricsTeamGameDataTest"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: TeamGameProvider()
        ) { entry in
            TeamGameWidgetView(entry: entry)
        }
        .configurationDisplayName("Team Game")
        .description("Team Game data diagnostic.")
        .supportedFamilies([
            .systemSmall
        ])
        .contentMarginsDisabled()
    }
}
