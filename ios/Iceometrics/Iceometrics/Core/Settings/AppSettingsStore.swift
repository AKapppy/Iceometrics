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
        showPregamePredictions = true
        hiddenCompetitionIDs = []
    }

    private enum Keys {
        static let favoriteTeamID = "settings.favoriteTeamID"
        static let accentMode = "settings.accentMode"
        static let customAccentHex = "settings.customAccentHex"
        static let appearance = "settings.appearance"
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
        "ANA": "#F47A38", "BOS": "#FFB81C", "BUF": "#003087",
        "CGY": "#C8102E", "CAR": "#CC0000", "CHI": "#C8102E",
        "COL": "#6F263D", "CBJ": "#002654", "DAL": "#006847",
        "DET": "#CE1126", "EDM": "#FF4C00", "FLA": "#041E42",
        "LAK": "#A2AAAD", "MIN": "#154734", "MTL": "#AF1E2D",
        "NSH": "#FFB81C", "NJD": "#CE1126", "NYI": "#00539B",
        "NYR": "#0038A8", "OTT": "#C52032", "PHI": "#F74902",
        "PIT": "#FFB81C", "SJS": "#006D75", "SEA": "#99D9D9",
        "STL": "#002F87", "TBL": "#A2AAAD", "TOR": "#A2AAAD",
        "UTA": "#6CACE4", "VAN": "#00205B", "VGK": "#B9975B",
        "WSH": "#C8102E", "WPG": "#AC162C",
    ]

    private static let pwhl: [String: String] = [
        "BOS": "#B0E0D0", "MIN": "#9070C0", "MTL": "#802030",
        "NY": "#00B0B0", "OTT": "#A01020", "SEA": "#80B0C0",
        "TOR": "#F0B010", "VAN": "#004070",
    ]
}
