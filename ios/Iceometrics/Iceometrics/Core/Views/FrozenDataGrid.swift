import SwiftUI
import Combine

struct FrozenGridColumn<ID: Hashable>: Identifiable {
    let id: ID
    let width: CGFloat
}

private struct FrozenGridScrollTarget<ID: Hashable>: Hashable {
    let id: ID
}

@MainActor
private final class FrozenHorizontalScrollState: ObservableObject {
    @Published private(set) var offset: CGFloat = 0

    func update(_ next: CGFloat) {
        guard abs(next - offset) > 0.25 else { return }
        offset = next
    }
}

@MainActor
private final class FrozenVerticalScrollState: ObservableObject {
    @Published private(set) var offset: CGFloat = 0

    func update(_ next: CGFloat) {
        guard abs(next - offset) > 0.25 else { return }
        offset = next
    }
}

struct FrozenDataGrid<
    Row: Identifiable,
    ColumnID: Hashable,
    Corner: View,
    Header: View,
    RowHeader: View,
    Cell: View
>: View {
    let rows: [Row]
    let columns: [FrozenGridColumn<ColumnID>]
    let rowHeaderWidth: CGFloat
    let rowHeight: CGFloat
    let headerHeight: CGFloat
    let initialColumnID: ColumnID?

    private let corner: () -> Corner
    private let header: (FrozenGridColumn<ColumnID>) -> Header
    private let rowHeader: (Row) -> RowHeader
    private let cell: (Row, FrozenGridColumn<ColumnID>) -> Cell

    @StateObject private var horizontalState = FrozenHorizontalScrollState()
    @StateObject private var verticalState = FrozenVerticalScrollState()

    init(
        rows: [Row],
        columns: [FrozenGridColumn<ColumnID>],
        rowHeaderWidth: CGFloat,
        rowHeight: CGFloat,
        headerHeight: CGFloat,
        initialColumnID: ColumnID? = nil,
        @ViewBuilder corner: @escaping () -> Corner,
        @ViewBuilder header: @escaping (FrozenGridColumn<ColumnID>) -> Header,
        @ViewBuilder rowHeader: @escaping (Row) -> RowHeader,
        @ViewBuilder cell: @escaping (Row, FrozenGridColumn<ColumnID>) -> Cell
    ) {
        self.rows = rows
        self.columns = columns
        self.rowHeaderWidth = rowHeaderWidth
        self.rowHeight = rowHeight
        self.headerHeight = headerHeight
        self.initialColumnID = initialColumnID
        self.corner = corner
        self.header = header
        self.rowHeader = rowHeader
        self.cell = cell
    }

    private var contentWidth: CGFloat {
        rowHeaderWidth + columns.reduce(0) { $0 + $1.width }
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        FrozenGridHeaderRow(
                            columns: columns,
                            rowHeaderWidth: rowHeaderWidth,
                            headerHeight: headerHeight,
                            horizontalState: horizontalState,
                            verticalState: verticalState,
                            corner: corner,
                            header: header
                        )
                        .zIndex(4)

                        ForEach(rows) { row in
                            HStack(spacing: 0) {
                                FrozenGridRowHeader(
                                    row: row,
                                    width: rowHeaderWidth,
                                    height: rowHeight,
                                    horizontalState: horizontalState,
                                    content: rowHeader
                                )
                                .zIndex(3)

                                ForEach(columns) { column in
                                    cell(row, column)
                                        .frame(width: column.width, height: rowHeight)
                                }
                            }
                            .frame(width: contentWidth, alignment: .leading)
                        }
                    }
                    .frame(
                        width: max(contentWidth, viewport.size.width),
                        alignment: .topLeading
                    )
                }
                .onScrollGeometryChange(for: CGPoint.self) { geometry in
                    geometry.contentOffset
                } action: { _, offset in
                    horizontalState.update(offset.x)
                    verticalState.update(offset.y)
                }
                .onAppear { scrollToInitial(proxy) }
                .onChange(of: initialColumnID) { _, _ in
                    scrollToInitial(proxy)
                }
            }
        }
        .clipped()
    }

    private func scrollToInitial(_ proxy: ScrollViewProxy) {
        guard let initialColumnID else { return }
        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo(
                FrozenGridScrollTarget(id: initialColumnID),
                anchor: .center
            )
        }
    }
}

private struct FrozenGridHeaderRow<
    ColumnID: Hashable,
    Corner: View,
    Header: View
>: View {
    let columns: [FrozenGridColumn<ColumnID>]
    let rowHeaderWidth: CGFloat
    let headerHeight: CGFloat

    @ObservedObject var horizontalState: FrozenHorizontalScrollState
    @ObservedObject var verticalState: FrozenVerticalScrollState

    let corner: () -> Corner
    let header: (FrozenGridColumn<ColumnID>) -> Header

    var body: some View {
        HStack(spacing: 0) {
            corner()
                .frame(width: rowHeaderWidth, height: headerHeight)
                .background(.background)
                .offset(x: horizontalState.offset)
                .zIndex(5)

            ForEach(columns) { column in
                header(column)
                    .frame(width: column.width, height: headerHeight)
                    .background(.background)
                    .id(FrozenGridScrollTarget(id: column.id))
            }
        }
        .background(.background)
        .offset(y: verticalState.offset)
        .zIndex(4)
        .transaction { $0.animation = nil }
    }
}

private struct FrozenGridRowHeader<
    Row: Identifiable,
    Content: View
>: View {
    let row: Row
    let width: CGFloat
    let height: CGFloat
    @ObservedObject var horizontalState: FrozenHorizontalScrollState
    let content: (Row) -> Content

    var body: some View {
        content(row)
            .frame(width: width, height: height)
            .background(.background)
            .offset(x: horizontalState.offset)
            .transaction { $0.animation = nil }
    }
}
