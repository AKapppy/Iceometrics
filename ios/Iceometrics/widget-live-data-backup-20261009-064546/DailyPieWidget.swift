import SwiftUI
import WidgetKit

struct DailyPieSlice: Identifiable {
    let id = UUID()
    let value: Double
    let hex: String
}

struct DailyPieEntry: TimelineEntry {
    let date: Date
    let label: String
    let slices: [DailyPieSlice]
}

struct DailyPieProvider: TimelineProvider {
    private var sampleSlices: [DailyPieSlice] {
        [
            .init(value: 0.18, hex: "#1769C2"),
            .init(value: 0.15, hex: "#D82032"),
            .init(value: 0.14, hex: "#23936F"),
            .init(value: 0.13, hex: "#E8B325"),
            .init(value: 0.12, hex: "#7B4560"),
            .init(value: 0.11, hex: "#D86B29"),
            .init(value: 0.09, hex: "#3A8495"),
            .init(value: 0.08, hex: "#B89B56")
        ]
    }

    func placeholder(
        in context: Context
    ) -> DailyPieEntry {
        DailyPieEntry(
            date: Date(),
            label: "TODAY",
            slices: sampleSlices
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (
            DailyPieEntry
        ) -> Void
    ) {
        completion(
            DailyPieEntry(
                date: Date(),
                label: "TODAY",
                slices: sampleSlices
            )
        )
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (
            Timeline<DailyPieEntry>
        ) -> Void
    ) {
        let entry = DailyPieEntry(
            date: Date(),
            label: "TODAY",
            slices: sampleSlices
        )

        completion(
            Timeline(
                entries: [entry],
                policy: .after(
                    Date().addingTimeInterval(30 * 60)
                )
            )
        )
    }
}

struct PieWedge: Shape {
    let start: Double
    let end: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let center = CGPoint(
            x: rect.midX,
            y: rect.midY
        )

        let radius =
            min(rect.width, rect.height) / 2

        path.move(to: center)

        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(
                -90 + start * 360
            ),
            endAngle: .degrees(
                -90 + end * 360
            ),
            clockwise: false
        )

        path.closeSubpath()

        return path
    }
}

struct DailyPieWidgetView: View {
    @Environment(\.widgetFamily)
    private var family

    let entry: DailyPieEntry

    var body: some View {
        GeometryReader { geometry in
            let size = min(
                geometry.size.width,
                geometry.size.height
            )

            VStack(spacing: labelSpacing) {
                Spacer(minLength: 0)

                pie
                    .frame(
                        width: size * pieScale,
                        height: size * pieScale
                    )
                    .shadow(
                        color: .black.opacity(0.28),
                        radius: 12,
                        y: 6
                    )

                Text(entry.label)
                    .font(
                        .system(
                            size: labelSize,
                            weight: .black,
                            design: .rounded
                        )
                    )
                    .tracking(1.3)
                    .foregroundStyle(
                        .white.opacity(0.48)
                    )

                Spacer(minLength: 0)
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
        .containerBackground(
            Color(
                red: 0.035,
                green: 0.040,
                blue: 0.050
            ),
            for: .widget
        )
    }

    private var pie: some View {
        ZStack {
            ForEach(
                Array(
                    sliceRanges.enumerated()
                ),
                id: \.offset
            ) { index, range in
                PieWedge(
                    start: range.start,
                    end: range.end
                )
                .fill(
                    Color(
                        widgetHex:
                            entry.slices[index].hex
                    )
                )
            }

            Circle()
                .stroke(
                    .white.opacity(0.12),
                    lineWidth: 1
                )
        }
    }

    private var sliceRanges:
        [(start: Double, end: Double)] {
        var running = 0.0

        return entry.slices.map { slice in
            let start = running
            running += slice.value

            return (
                start: start,
                end: running
            )
        }
    }

    private var pieScale: CGFloat {
        switch family {
        case .systemSmall:
            0.78

        case .systemLarge:
            0.83

        case .systemExtraLarge:
            0.86

        default:
            0.78
        }
    }

    private var labelSize: CGFloat {
        switch family {
        case .systemSmall:
            8

        case .systemLarge:
            9

        case .systemExtraLarge:
            10

        default:
            8
        }
    }

    private var labelSpacing: CGFloat {
        family == .systemSmall ? 4 : 7
    }
}

struct DailyPieWidget: Widget {
    let kind = "DailyPieWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: DailyPieProvider()
        ) { entry in
            DailyPieWidgetView(
                entry: entry
            )
        }
        .configurationDisplayName(
            "Daily Pie"
        )
        .description(
            "The Iceometrics daily prediction pie."
        )
        .supportedFamilies([
            .systemSmall,
            .systemLarge,
            .systemExtraLarge
        ])
    }
}
