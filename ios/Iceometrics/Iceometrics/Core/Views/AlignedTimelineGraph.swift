import SwiftUI

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
    let formatY: (Double) -> String

    private let xLabelHeight: CGFloat = 24
    private let tickCount = 5
    private let yLabelWidth: CGFloat = 38

    private var plotHeight: CGFloat {
        max(80, height - (showXLabels ? xLabelHeight : 0))
    }

    private var timelineWidth: CGFloat {
        max(columnWidth, CGFloat(max(labels.count, 1)) * columnWidth)
    }

    private var safeRange: Double {
        max(0.000_001, yMax - yMin)
    }

    var body: some View {
        HStack(spacing: 0) {
            yAxisLabels
                .frame(width: yLabelWidth, height: plotHeight)

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
                    let value = yMax - (safeRange * fraction)

                    Text(formatY(value))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .position(
                            x: yLabelWidth / 2,
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
                let ratio = (value - yMin) / safeRange
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
