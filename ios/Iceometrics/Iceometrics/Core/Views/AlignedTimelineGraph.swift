import SwiftUI
import Combine

/// Shared by a chart and its spreadsheet. Events do not invalidate the
/// entire chart/table view hierarchy on every pixel of a drag.
struct IceoTimelineScrollEvent {
    let x: CGFloat
    let sender: UUID
    let centeredColumn: Int?
}

// A single scroll-geometry sample keeps its horizontal, vertical and
// centered-column measurements consistent for chart/table synchronization.
struct IceoScrollSample: Equatable {
    let x: CGFloat
    let y: CGFloat
    let centeredColumn: Int
}

@MainActor
final class IceoTimelineScrollLink: ObservableObject {
    let events = PassthroughSubject<IceoTimelineScrollEvent, Never>()
    private var lastX: CGFloat = 0

    func report(_ x: CGFloat, sender: UUID, centeredColumn: Int? = nil) {
        let next = max(0, x)
        guard abs(next - lastX) > 0.75 else { return }
        lastX = next
        events.send(IceoTimelineScrollEvent(
            x: next, sender: sender, centeredColumn: centeredColumn
        ))
    }
}

struct TimelineGraphSeries: Identifiable {
    let id: String
    let color: Color
    let values: [Double?]
    let lineWidth: CGFloat
    let opacity: Double
}

struct AlignedTimelineGraph: View {
    let labels: [String]
    let series: [TimelineGraphSeries]
    let leadingWidth: CGFloat
    let columnWidth: CGFloat
    let yMin: Double
    let yMax: Double
    let initialColumnIndex: Int?
    let height: CGFloat
    var showXLabels: Bool = true
    var adaptiveYScale: Bool = false
    var selectedSeriesID: String? = nil
    var zeroBaseline: Bool = false
    var percentageScale: Bool = false
    var symmetricYScale: Bool = false
    var linkedHorizontalScroll: IceoTimelineScrollLink? = nil
    let formatY: (Double) -> String

    private let xLabelHeight: CGFloat = 24
    @State private var iceoLinkedPosition = ScrollPosition()
    @State private var iceoScrollSender = UUID()

    private var iceoExternalScrolls: AnyPublisher<IceoTimelineScrollEvent, Never> {
        linkedHorizontalScroll?.events.eraseToAnyPublisher()
            ?? Empty<IceoTimelineScrollEvent, Never>().eraseToAnyPublisher()
    }

    private let tickCount = 5
    private let yLabelWidth: CGFloat = 38

    @State private var visibleColumns: ClosedRange<Int>?

    private var plotHeight: CGFloat {
        max(80, height - (showXLabels ? xLabelHeight : 0))
    }

    private var timelineWidth: CGFloat {
        max(columnWidth, CGFloat(max(labels.count, 1)) * columnWidth)
    }

    private var safeRange: Double {
        max(0.000_001, displayDomain.max - displayDomain.min)
    }

    /// The lines displayed within the horizontal viewport determine the
    /// vertical domain. Selecting a team changes the domain as well as its
    /// highlight. Only finite data points can affect the scale.
    private var displayDomain: (min: Double, max: Double) {
        guard adaptiveYScale, !labels.isEmpty else { return (yMin, yMax) }

        let lower = min(max(0, visibleColumns?.lowerBound ?? 0), labels.count - 1)
        let upper = min(max(lower, visibleColumns?.upperBound ?? labels.count - 1), labels.count - 1)
        let focused = selectedSeriesID.flatMap { id in
            series.first(where: { $0.id == id })
        }
        let candidates = focused.map { [$0] } ?? series

        var values: [Double] = []
        for line in candidates {
            for index in lower...upper {
                if line.values.indices.contains(index),
                   let value = line.values[index], value.isFinite {
                    values.append(value)
                }
            }
        }
        guard let lowest = values.min(), let highest = values.max() else {
            return (yMin, yMax)
        }

        if percentageScale {
            // Percentage predictions always start at 0. Don't show 100%
            // unless the strongest visible forecast approaches it.
            let padded = min(100.0, max(0, highest) * 1.045)
            let stops: [Double] = [5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 75, 80, 90, 95, 100]
            return (0, stops.first(where: { $0 >= padded }) ?? 100)
        }

        if symmetricYScale {
            // Goal differential: keep zero centered so positive and negative
            // differences remain directly comparable.
            let extent = niceUpper(max(2.0, abs(lowest), abs(highest)) * 1.04)
            return (-extent, extent)
        }

        if zeroBaseline {
            return (0, niceUpper(max(4, highest) * 1.04))
        }

        let span = max(1, highest - lowest)
        let margin = span * 0.05
        return (lowest - margin, highest + margin)
    }

    private func niceUpper(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 1 }
        let base = pow(10.0, floor(log10(value)))
        let scaled = value / base
        let steps: [Double] = [1, 1.25, 1.5, 2, 2.5, 4, 5, 7.5, 10]
        return (steps.first(where: { $0 >= scaled }) ?? 10) * base
    }

    var body: some View {
        HStack(spacing: 0) {
            yAxisLabels
                .frame(width: leadingWidth, height: plotHeight)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        Canvas { context, _ in
                            drawGrid(context: &context)
                            drawSeries(context: &context)
                        }
                        .frame(width: timelineWidth, height: plotHeight)

                        if showXLabels {
                            VStack(spacing: 0) {
                                Color.clear.frame(height: plotHeight)

                                HStack(spacing: 0) {
                                    ForEach(labels.indices, id: \.self) { index in
                                        Text(labels[index])
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .frame(width: columnWidth, height: xLabelHeight)
                                            .id(index)
                                    }
                                }
                            }
                        } else {
                            HStack(spacing: 0) {
                                ForEach(labels.indices, id: \.self) { index in
                                    Color.clear
                                        .frame(width: columnWidth, height: 1)
                                        .id(index)
                                }
                            }
                        }
                    }
                    .frame(width: timelineWidth, height: height, alignment: .topLeading)
                }
                .onScrollGeometryChange(for: ClosedRange<Int>.self) { geometry in
                    let visible = geometry.visibleRect
                    let lastIndex = max(0, labels.count - 1)
                    let first = min(lastIndex, max(0, Int(floor(visible.minX / columnWidth))))
                    let last = min(lastIndex, max(first, Int(ceil(visible.maxX / columnWidth)) - 1))
                    return first...last
                } action: { _, range in
                    if visibleColumns != range {
                        visibleColumns = range
                    }
                }
                .scrollPosition($iceoLinkedPosition)
                .onScrollGeometryChange(for: IceoScrollSample.self) { geometry in
                    let x = max(0, geometry.contentOffset.x)
                    let middle = x + geometry.containerSize.width * 0.5
                    let column = max(0, Int(middle / max(1, columnWidth)))
                    return IceoScrollSample(x: x, y: 0, centeredColumn: column)
                } action: { _, sample in
                    linkedHorizontalScroll?.report(
                        sample.x,
                        sender: iceoScrollSender,
                        centeredColumn: sample.centeredColumn
                    )
                }
                .onReceive(iceoExternalScrolls) { event in
                    guard event.sender != iceoScrollSender else { return }
                    iceoLinkedPosition.scrollTo(x: event.x)
                }
                .onAppear { scrollToInitial(proxy) }
                .onChange(of: initialColumnIndex) { _, _ in
                    scrollToInitial(proxy)
                }
            }
        }
        .frame(height: height, alignment: .topLeading)
    }

    private var yAxisLabels: some View {
        GeometryReader { _ in
            ZStack(alignment: .topTrailing) {
                ForEach(0..<tickCount, id: \.self) { tick in
                    let fraction = Double(tick) / Double(tickCount - 1)
                    let value = displayDomain.max - (safeRange * fraction)

                    Text(formatY(value))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .position(
                            x: max(18, leadingWidth - 20),
                            y: 2 + CGFloat(fraction) * max(1, plotHeight - 4)
                        )
                }
            }
        }
    }

    private func drawGrid(context: inout GraphicsContext) {
        for tick in 0..<tickCount {
            let fraction = CGFloat(tick) / CGFloat(tickCount - 1)
            let y = 1 + fraction * max(1, plotHeight - 2)

            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: timelineWidth, y: y))
            context.stroke(
                path,
                with: .color(Color.primary.opacity(0.09)),
                lineWidth: 1
            )
        }
    }

    private func drawSeries(context: inout GraphicsContext) {
        for item in series {
            var path = Path()
            var segmentOpen = false

            for index in labels.indices {
                guard item.values.indices.contains(index),
                      let value = item.values[index] else {
                    segmentOpen = false
                    continue
                }

                let x = (CGFloat(index) + 0.5) * columnWidth
                let ratio = (value - displayDomain.min) / safeRange
                let unclampedY = plotHeight - CGFloat(ratio) * plotHeight
                let y = min(plotHeight - 1, max(1, unclampedY))
                let point = CGPoint(x: x, y: y)

                if segmentOpen {
                    path.addLine(to: point)
                } else {
                    path.move(to: point)
                    segmentOpen = true
                }
            }

            context.stroke(
                path,
                with: .color(item.color.opacity(item.opacity)),
                style: StrokeStyle(
                    lineWidth: item.lineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }

    private func scrollToInitial(_ proxy: ScrollViewProxy) {
        guard let initialColumnIndex,
              labels.indices.contains(initialColumnIndex) else { return }

        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo(initialColumnIndex, anchor: .center)
        }
    }
}
