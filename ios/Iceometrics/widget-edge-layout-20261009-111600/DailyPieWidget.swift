import SwiftUI
import WidgetKit

struct DailyPieEntry:
    TimelineEntry {
    let date: Date
    let pie: WidgetPie?
    let hasSnapshot: Bool
}

struct DailyPieProvider:
    TimelineProvider {
    func placeholder(
        in context: Context
    ) -> DailyPieEntry {
        DailyPieEntry(
            date: Date(),
            pie: nil,
            hasSnapshot: false
        )
    }

    func getSnapshot(
        in context: Context,
        completion:
            @escaping (
                DailyPieEntry
            ) -> Void
    ) {
        completion(makeEntry())
    }

    func getTimeline(
        in context: Context,
        completion:
            @escaping (
                Timeline<
                    DailyPieEntry
                >
            ) -> Void
    ) {
        completion(
            Timeline(
                entries: [
                    makeEntry()
                ],
                policy: .after(
                    Date()
                        .addingTimeInterval(
                            30 * 60
                        )
                )
            )
        )
    }

    private func makeEntry()
        -> DailyPieEntry {
        let snapshot =
            WidgetSnapshotStore.load()

        return DailyPieEntry(
            date: Date(),
            pie: snapshot?.pie,
            hasSnapshot:
                snapshot != nil
        )
    }
}

struct WidgetAnnularSector:
    Shape {
    let innerRatio: CGFloat
    let startDegrees: Double
    let endDegrees: Double

    func path(
        in rect: CGRect
    ) -> Path {
        var path = Path()

        let center = CGPoint(
            x: rect.midX,
            y: rect.midY
        )

        let outer =
            min(
                rect.width,
                rect.height
            ) / 2

        let inner =
            outer * innerRatio

        path.addArc(
            center: center,
            radius: outer,
            startAngle:
                .degrees(
                    startDegrees
                ),
            endAngle:
                .degrees(
                    endDegrees
                ),
            clockwise: false
        )

        path.addArc(
            center: center,
            radius: inner,
            startAngle:
                .degrees(
                    endDegrees
                ),
            endAngle:
                .degrees(
                    startDegrees
                ),
            clockwise: true
        )

        path.closeSubpath()

        return path
    }
}

struct DailyPieWidgetView:
    View {
    @Environment(
        \.widgetFamily
    )
    private var family

    let entry: DailyPieEntry

    var body: some View {
        GeometryReader {
            geometry in
            VStack(spacing: 4) {
                Spacer(minLength: 0)

                if let pie =
                    entry.pie {
                    ringChart(pie)
                        .frame(
                            width:
                                chartSize(
                                    geometry
                                ),
                            height:
                                chartSize(
                                    geometry
                                )
                        )

                    Text(pie.label)
                        .font(
                            .system(
                                size:
                                    labelSize,
                                weight:
                                    .black,
                                design:
                                    .rounded
                            )
                        )
                        .tracking(1.25)
                        .foregroundStyle(
                            .white
                                .opacity(
                                    0.50
                                )
                        )
                } else {
                    emptyState
                }

                Spacer(minLength: 0)
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
        .widgetURL(
            URL(string: "iceometrics://predictions/pie")
        )
        .containerBackground(
            Color(
                red: 0.035,
                green: 0.040,
                blue: 0.050
            ),
            for: .widget
        )
    }

    private func ringChart(
        _ pie: WidgetPie
    ) -> some View {
        ZStack {
            let ringCount =
                max(
                    1,
                    pie.rings.count
                )

            let innerHole:
                CGFloat = 0.23

            let available =
                1.0 - innerHole

            ForEach(
                Array(
                    pie.rings
                        .enumerated()
                ),
                id: \.offset
            ) { ringIndex, ring in
                let outerRatio =
                    1.0
                    - CGFloat(
                        ringIndex
                    )
                    * available
                    / CGFloat(
                        ringCount
                    )

                let innerRatio =
                    max(
                        innerHole,
                        outerRatio
                        - available
                        / CGFloat(
                            ringCount
                        )
                        + 0.012
                    )

                ringView(
                    ring,
                    innerRatio:
                        innerRatio
                            / outerRatio
                )
                .scaleEffect(
                    outerRatio
                )
            }

            Image(
                systemName:
                    "trophy.fill"
            )
            .resizable()
            .scaledToFit()
            .frame(
                width:
                    family
                        == .systemSmall
                    ? 20
                    : 34,
                height:
                    family
                        == .systemSmall
                    ? 28
                    : 45
            )
            .foregroundStyle(
                .white.opacity(0.48)
            )
        }
    }

    private func ringView(
        _ ring: WidgetPieRing,
        innerRatio: CGFloat
    ) -> some View {
        ZStack {
            ForEach(
                Array(
                    ranges(
                        for: ring
                    ).enumerated()
                ),
                id: \.offset
            ) {
                index,
                range in

                WidgetAnnularSector(
                    innerRatio:
                        innerRatio,
                    startDegrees:
                        range.start,
                    endDegrees:
                        range.end
                )
                .fill(
                    Color(
                        widgetHex:
                            ring.slices[
                                index
                            ]
                            .colorHex
                    )
                    .opacity(
                        max(
                            0.58,
                            0.94
                            - Double(
                                ringDepth(
                                    ring
                                )
                            )
                            * 0.08
                        )
                    )
                )
            }
        }
    }

    private func ranges(
        for ring:
            WidgetPieRing
    ) -> [(
        start: Double,
        end: Double
    )] {
        var running =
            -90.0

        return ring.slices.map {
            slice in

            let extent =
                360
                * slice.value

            let start =
                running

            running += extent

            return (
                start: start,
                end: running
            )
        }
    }

    private func ringDepth(
        _ ring: WidgetPieRing
    ) -> Int {
        entry.pie?
            .rings
            .firstIndex {
                $0.key
                    == ring.key
            }
            ?? 0
    }

    private func chartSize(
        _ geometry:
            GeometryProxy
    ) -> CGFloat {
        let side =
            min(
                geometry.size.width,
                geometry.size.height
            )

        switch family {
        case .systemSmall:
            return side * 0.78

        case .systemLarge:
            return side * 0.84

        case .systemExtraLarge:
            return side * 0.87

        default:
            return side * 0.78
        }
    }

    private var labelSize:
        CGFloat {
        switch family {
        case .systemSmall:
            return 8

        case .systemLarge:
            return 9

        case .systemExtraLarge:
            return 10

        default:
            return 8
        }
    }

    private var emptyState:
        some View {
        VStack(spacing: 7) {
            Image(
                systemName:
                    entry.hasSnapshot
                    ? "chart.pie"
                    : "arrow.clockwise.circle"
            )
            .font(.title2)
            .opacity(0.60)

            Text(
                entry.hasSnapshot
                ? "PIE DATA UNAVAILABLE"
                : "OPEN ICEOMETRICS"
            )
            .font(
                .caption2
                    .weight(
                        .bold
                    )
            )
            .opacity(0.65)

            if !entry.hasSnapshot {
                Text("TO UPDATE")
                    .font(
                        .system(
                            size: 8,
                            weight:
                                .bold
                        )
                    )
                    .tracking(1)
                    .opacity(0.45)
            }
        }
        .foregroundStyle(.white)
    }
}

struct DailyPieWidget:
    Widget {
    let kind =
        "DailyPieWidget"

    var body:
        some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider:
                DailyPieProvider()
        ) { entry in
            DailyPieWidgetView(
                entry: entry
            )
        }
        .configurationDisplayName(
            "Daily Pie"
        )
        .description(
            "The current Iceometrics playoff prediction pie."
        )
        .supportedFamilies([
            .systemSmall,
            .systemLarge,
            .systemExtraLarge,
        ])
    }
}
