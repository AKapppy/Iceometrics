import SwiftUI

enum WidgetGamePhase: String, Codable {
    case scheduled
    case starting
    case live
    case intermission
    case final
}

struct WidgetTeam: Codable, Hashable {
    let abbreviation: String
    let name: String
    let accentHex: String
}

struct WidgetGame: Codable, Identifiable {
    let id: String

    let awayTeam: WidgetTeam
    let homeTeam: WidgetTeam

    let awayScore: Int
    let homeScore: Int

    let awayProbability: Double
    let homeProbability: Double

    let phase: WidgetGamePhase

    let detail: String
    let isFavoriteTeamGame: Bool
}

extension Color {
    init(widgetHex hex: String) {
        let cleaned = hex
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)

        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let r: Double
        let g: Double
        let b: Double

        if cleaned.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        } else {
            r = 0.2
            g = 0.2
            b = 0.2
        }

        self.init(red: r, green: g, blue: b)
    }
}
