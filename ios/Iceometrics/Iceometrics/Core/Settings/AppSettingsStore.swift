import SwiftUI
import Combine
import Foundation

enum AppAppearance: String, CaseIterable, Identifiable {
    case dark
    case light
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .system: "System"
        }
    }
}

enum AppAccentMode: String, CaseIterable, Identifiable {
    case favorite
    case custom
    case appDefault

    var id: String { rawValue }

    var title: String {
        switch self {
        case .favorite: "Team"
        case .custom: "Custom"
        case .appDefault: "Default"
        }
    }
}

struct ScoreboardCompetitionOption:
    Identifiable,
    Hashable
{
    let id: String
    let name: String
}

enum ScoreboardCompetitionCatalog {
    static func id(for game: HockeyGame) -> String {
        normalizedID(game.leagueCode)
    }

    static func option(
        for game: HockeyGame
    ) -> ScoreboardCompetitionOption {
        let competitionID = id(for: game)

        return ScoreboardCompetitionOption(
            id: competitionID,
            name: displayName(for: competitionID)
        )
    }

    static func displayName(
        for id: String
    ) -> String {
        switch normalizedID(id) {
        case "NHL":
            return "NHL"
        case "PWHL":
            return "PWHL"
        case "OLY", "OLYMPICS":
            return "Olympics"
        case "WJC", "WORLDJUNIORS", "WORLD_JUNIORS":
            return "World Juniors"
        case "WORLDS", "IIHFWC", "WORLDCHAMPIONSHIP":
            return "World Championship"
        case "4NATIONS", "FOURNATIONS":
            return "4 Nations"
        default:
            return id
                .replacingOccurrences(
                    of: "_",
                    with: " "
                )
                .capitalized
        }
    }

    private static func normalizedID(
        _ value: String
    ) -> String {
        value
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .uppercased()
    }
}

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published var favoriteTeamID: String? {
        didSet {
            if let favoriteTeamID {
                defaults.set(favoriteTeamID, forKey: Keys.favoriteTeamID)
            } else {
                defaults.removeObject(forKey: Keys.favoriteTeamID)
            }
        }
    }

    @Published var accentMode: AppAccentMode {
        didSet {
            defaults.set(accentMode.rawValue, forKey: Keys.accentMode)
        }
    }

    @Published var customAccentHex: String {
        didSet {
            defaults.set(customAccentHex, forKey: Keys.customAccentHex)
        }
    }

    @Published var appearance: AppAppearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: Keys.appearance)
        }
    }

    @Published var selectedSeason: String {
        didSet {
            defaults.set(selectedSeason, forKey: Keys.selectedSeason)
        }
    }

    @Published var showPregamePredictions: Bool {
        didSet {
            defaults.set(
                showPregamePredictions,
                forKey: Keys.showPregamePredictions
            )
        }
    }

    @Published var hiddenCompetitionIDs: Set<String> {
        didSet {
            defaults.set(
                Array(hiddenCompetitionIDs).sorted(),
                forKey: Keys.hiddenCompetitionIDs
            )
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        favoriteTeamID = defaults.string(forKey: Keys.favoriteTeamID)

        accentMode = AppAccentMode(
            rawValue: defaults.string(forKey: Keys.accentMode) ?? ""
        ) ?? .favorite

        customAccentHex = defaults.string(
            forKey: Keys.customAccentHex
        ) ?? "#0A84FF"

        appearance = AppAppearance(
            rawValue: defaults.string(forKey: Keys.appearance) ?? ""
        ) ?? .dark

        // The current season remains the default even after a fresh install.
        let storedSeason = defaults.string(forKey: Keys.selectedSeason) ?? "2026-2027"
        selectedSeason = (2019...2026).contains(Int(storedSeason.prefix(4)) ?? -1)
            && storedSeason == "\(Int(storedSeason.prefix(4)) ?? 0)-\((Int(storedSeason.prefix(4)) ?? 0) + 1)"
                ? storedSeason : "2026-2027"

        if defaults.object(
            forKey: Keys.showPregamePredictions
        ) == nil {
            showPregamePredictions = true
        } else {
            showPregamePredictions = defaults.bool(
                forKey: Keys.showPregamePredictions
            )
        }

        hiddenCompetitionIDs = Set(
            defaults.stringArray(
                forKey: Keys.hiddenCompetitionIDs
            ) ?? []
        )
    }

    var preferredColorScheme: ColorScheme? {
        switch appearance {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }

    func accentColor(for teams: [Team]) -> Color {
        switch accentMode {
        case .custom:
            return Color(hex: customAccentHex, fallback: .blue)

        case .favorite:
            guard let favoriteTeamID,
                  let team = teams.first(where: { $0.id == favoriteTeamID }),
                  let hex = TeamAccentPalette.primaryHex(for: team) else {
                return .blue
            }
            return Color(hex: hex, fallback: .blue)

        case .appDefault:
            return .blue
        }
    }

    // The favorite NHL team alone chooses the heat-map palette, regardless
    // of the row's team or the primary accent mode (Team/Custom/Default).
    func favoritePaletteTeamCode(for teams: [Team]) -> String? {
        guard let favoriteTeamID,
              let favorite = teams.first(where: { $0.id == favoriteTeamID }),
              favorite.leagueCode == "NHL" else {
            return nil
        }
        return favorite.abbreviation.uppercased()
    }

    func accentForegroundColor(for teams: [Team]) -> Color {
        let selectedHex: String
        switch accentMode {
        case .custom:
            selectedHex = customAccentHex
        case .appDefault:
            selectedHex = "#0A84FF"
        case .favorite:
            if let favoriteTeamID,
               let team = teams.first(where: { $0.id == favoriteTeamID }),
               let hex = TeamAccentPalette.primaryHex(for: team) {
                selectedHex = hex
            } else {
                selectedHex = "#0A84FF"
            }
        }
        return TeamPerformancePalette.accentTextColor(hex: selectedHex)
    }

    func isCompetitionVisible(
        _ competitionID: String
    ) -> Bool {
        !hiddenCompetitionIDs.contains(
            competitionID.uppercased()
        )
    }

    func setCompetitionVisible(
        _ competitionID: String,
        visible: Bool
    ) {
        let normalized = competitionID.uppercased()

        if visible {
            hiddenCompetitionIDs.remove(normalized)
        } else {
            hiddenCompetitionIDs.insert(normalized)
        }
    }

    func reset() {
        favoriteTeamID = nil
        accentMode = .favorite
        customAccentHex = "#0A84FF"
        appearance = .dark
        selectedSeason = "2026-2027"
        showPregamePredictions = true
        hiddenCompetitionIDs = []
    }

    private enum Keys {
        static let favoriteTeamID = "settings.favoriteTeamID"
        static let accentMode = "settings.accentMode"
        static let customAccentHex = "settings.customAccentHex"
        static let appearance = "settings.appearance"
        static let selectedSeason = "settings.selectedSeason"
        static let showPregamePredictions = "settings.showPregamePredictions"
        static let hiddenCompetitionIDs = "settings.hiddenCompetitionIDs"
    }
}

enum TeamAccentPalette {
    static func primaryHex(for team: Team) -> String? {
        let code = team.abbreviation.uppercased()

        if team.leagueCode == "PWHL" {
            return pwhl[code]
        }

        return nhl[code]
    }

    private static let nhl: [String: String] = [
        "ANA": "#CF4520", "BOS": "#FFB81C", "BUF": "#002654",
        "CAR": "#CC0000", "CBJ": "#002654", "CGY": "#C8102E",
        "CHI": "#CF0A2C", "COL": "#6F263D", "DAL": "#006847",
        "DET": "#CE1126", "EDM": "#FF4C00", "FLA": "#C8102E",
        "LAK": "#A2AAAD", "MIN": "#154734", "MTL": "#AF1E2D",
        "NJD": "#CE1126", "NSH": "#FFB81C", "NYI": "#F47D30",
        "NYR": "#0038A8", "OTT": "#C52032", "PHI": "#F74902",
        "PIT": "#FCB514", "SEA": "#99D9D9", "SJS": "#006D75",
        "STL": "#002F87", "TBL": "#002868", "TOR": "#00205B",
        "UTA": "#7AB2E0", "VAN": "#00205B", "VGK": "#B4975A",
        "WPG": "#004C97", "WSH": "#C8102E",
    ]

    static func primaryHex(forCode code: String, leagueCode: String = "NHL") -> String? {
        if leagueCode.uppercased() == "PWHL" {
            return pwhl[code.uppercased()]
        }
        return nhl[code.uppercased()]
    }

    private static let pwhl: [String: String] = [
        "BOS": "#B0E0D0", "MIN": "#9070C0", "MTL": "#802030",
        "NY": "#00B0B0", "OTT": "#A01020", "SEA": "#80B0C0",
        "TOR": "#F0B010", "VAN": "#004070",
    ]
}

// ICEOMETRICS_TEAM_PALETTE_V1
// Current/heritage team color references approved for use; source hex verification
// may be refined later. Do not replace a brand endpoint to improve accessibility.
// Instead, the final cell fill is a 36% tint over the current color-scheme surface.
enum TeamPerformancePalette {
    static let neutralHex = "#7D858F"
    static let tintStrength = 0.36

    private static let nhl: [String: (good: String, bad: String)] = [
        "ANA": (good: "#CF4520", bad: "#010101"),
        "BOS": (good: "#FFB81C", bad: "#000000"),
        "BUF": (good: "#FCB514", bad: "#002654"),
        "CAR": (good: "#A2AAAD", bad: "#CC0000"),
        "CBJ": (good: "#002654", bad: "#CE1126"),
        "CGY": (good: "#F1BE48", bad: "#C8102E"),
        "CHI": (good: "#00833E", bad: "#CF0A2C"),
        "COL": (good: "#236192", bad: "#6F263D"),
        "DAL": (good: "#006847", bad: "#000000"),
        "DET": (good: "#FFFFFF", bad: "#CE1126"),
        "EDM": (good: "#FF4C00", bad: "#041E42"),
        "FLA": (good: "#041E42", bad: "#C8102E"),
        "LAK": (good: "#FFC72C", bad: "#582C83"),
        "MIN": (good: "#154734", bad: "#A6192E"),
        "MTL": (good: "#192168", bad: "#AF1E2D"),
        "NJD": (good: "#046A38", bad: "#CE1126"),
        "NSH": (good: "#FFB81C", bad: "#041E42"),
        "NYI": (good: "#00539B", bad: "#F47D30"),
        "NYR": (good: "#0038A8", bad: "#CE1126"),
        "OTT": (good: "#C2912C", bad: "#C52032"),
        "PHI": (good: "#F74902", bad: "#000000"),
        "PIT": (good: "#FCB514", bad: "#000000"),
        "SEA": (good: "#99D9D9", bad: "#E9072B"),
        "SJS": (good: "#006D75", bad: "#EA7200"),
        "STL": (good: "#002F87", bad: "#C8102E"),
        "TBL": (good: "#002868", bad: "#000000"),
        "TOR": (good: "#00205B", bad: "#000000"),
        "UTA": (good: "#7AB2E0", bad: "#090909"),
        "VAN": (good: "#00843D", bad: "#00205B"),
        "VGK": (good: "#B4975A", bad: "#C8102E"),
        "WPG": (good: "#004C97", bad: "#AC162C"),
        "WSH": (good: "#041E42", bad: "#C8102E"),
    ]

    // Predictions use the team's two real palette colors. Order by
    // perceived brightness so zero always starts on the darker shade.
    static func predictionBarColors(teamCode: String, fallbackHex: String) -> [Color] {
        let pair = nhl[teamCode.uppercased()]
        let first = pair?.good ?? fallbackHex
        let second = pair?.bad ?? fallbackHex
        let darkFirst = luminance(first) <= luminance(second)
        return [
            Color(hex: darkFirst ? first : second, fallback: .accentColor),
            Color(hex: darkFirst ? second : first, fallback: .accentColor)
        ]
    }

    private static func luminance(_ hex: String) -> Double {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let value = UInt64(cleaned, radix: 16), cleaned.count == 6 else {
            return 0
        }
        let red = Double((value >> 16) & 0xFF)
        let green = Double((value >> 8) & 0xFF)
        let blue = Double(value & 0xFF)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private struct RGB {
        var red: Double
        var green: Double
        var blue: Double

        init(hex: String) {
            let text = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            let number = Int(text, radix: 16) ?? 0
            red = Double((number >> 16) & 0xFF) / 255
            green = Double((number >> 8) & 0xFF) / 255
            blue = Double(number & 0xFF) / 255
        }

        func mixed(with other: RGB, amount: Double) -> RGB {
            let a = min(max(amount, 0), 1)
            return RGB(
                red: red + (other.red - red) * a,
                green: green + (other.green - green) * a,
                blue: blue + (other.blue - blue) * a
            )
        }

        init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        var color: Color {
            Color(red: red, green: green, blue: blue)
        }

        var luminance: Double {
            func linear(_ component: Double) -> Double {
                component <= 0.04045
                    ? component / 12.92
                    : pow((component + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red)
                + 0.7152 * linear(green)
                + 0.0722 * linear(blue)
        }
    }

    // score: +1 = GOOD, 0 = neutral, -1 = BAD.
    // Positive/negative interpolation is computed with the ORIGINAL brand hex.
    // Only the resulting cell fill is tinted for black/white text legibility.
    static func cellColor(
        teamCode: String,
        score: Double,
        scheme: ColorScheme
    ) -> Color {
        let endpoints = nhl[teamCode.uppercased()]
        let neutral = RGB(hex: neutralHex)
        let position = score.isFinite ? min(max(score, -1), 1) : 0
        let hex = position >= 0 ? endpoints?.good : endpoints?.bad
        // If no NHL favorite is selected, keep the familiar generic blue/red
        // heat map instead of arbitrarily borrowing an NHL team's colors.
        let defaultHex = position >= 0 ? "#2367EB" : "#E32E45"
        let target = RGB(hex: hex ?? defaultHex)
        let brand = neutral.mixed(with: target, amount: abs(position))
        let surface = RGB(hex: scheme == .dark ? "#121212" : "#FFFFFF")
        return surface.mixed(with: brand, amount: tintStrength).color
    }

    // Text on a SOLID primary accent: whichever of black/white has greater WCAG contrast.
    static func accentTextColor(hex: String) -> Color {
        let lum = RGB(hex: hex).luminance
        let blackContrast = (lum + 0.05) / 0.05
        let whiteContrast = 1.05 / (lum + 0.05)
        return blackContrast >= whiteContrast ? .black : .white
    }
}

private struct IceometricsAccentForegroundKey: EnvironmentKey {
    static let defaultValue: Color = .white
}

extension EnvironmentValues {
    var iceometricsAccentForegroundColor: Color {
        get { self[IceometricsAccentForegroundKey.self] }
        set { self[IceometricsAccentForegroundKey.self] = newValue }
    }
}



// ICEOMETRICS_FAVORITE_GRADIENT_V1
// Injected once at the app root. Only performance-table backgrounds use it;
// NHL row logos and per-team graph-line colors remain individual team colors.
private struct IceometricsFavoritePaletteTeamCodeKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var iceometricsFavoritePaletteTeamCode: String? {
        get { self[IceometricsFavoritePaletteTeamCodeKey.self] }
        set { self[IceometricsFavoritePaletteTeamCodeKey.self] = newValue }
    }
}
