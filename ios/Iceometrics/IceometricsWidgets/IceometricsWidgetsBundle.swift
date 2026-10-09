import SwiftUI
import WidgetKit

@main
struct IceometricsWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DailyPieWidget()
        TeamGameWidget()
        TodaysGamesWidget()
    }
}
