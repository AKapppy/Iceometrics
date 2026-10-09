import Foundation
import SwiftUI
import AppIntents
import UIKit

let iceometricsWidgetAppGroup =
    "group.com.akappy.Iceometrics"

enum WidgetGamePhase:
    String,
    Codable {
    case scheduled
    case starting
    case live
    case intermission
    case final
    case postponed
    case unknown
}

struct WidgetTeam:
    Codable,
    Hashable {
    let id: String
    let abbreviation: String
    let name: String
    let accentHex: String
    let logoURL: URL?
}

struct WidgetGame:
    Codable,
    Identifiable,
    Hashable {
    let id: String

    let startTime: Date
    let isToday: Bool

    let awayTeam: WidgetTeam
    let homeTeam: WidgetTeam

    let awayScore: Int?
    let homeScore: Int?

    let awayProbability: Double?
    let homeProbability: Double?

    let phase: WidgetGamePhase
    let detail: String

    let isFavoriteTeamGame: Bool
}

struct WidgetPie:
    Codable {
    let dataDate: Date
    let label: String
    let rings: [WidgetPieRing]
}

struct WidgetPieRing:
    Codable,
    Identifiable {
    let key: String
    let label: String
    let slices: [WidgetPieSlice]

    var id: String {
        key
    }
}

struct WidgetPieSlice:
    Codable,
    Identifiable {
    let teamCode: String
    let teamName: String
    let colorHex: String
    let value: Double

    var id: String {
        teamCode
    }
}

struct WidgetSnapshot:
    Codable {
    let generatedAt: Date
    let favoriteTeamID: String?
    let games: [WidgetGame]
    let pie: WidgetPie?
}

enum WidgetSnapshotStore {
    static func load()
        -> WidgetSnapshot? {
        guard let containerURL =
            FileManager.default
                .containerURL(
                    forSecurityApplicationGroupIdentifier:
                        iceometricsWidgetAppGroup
                )
        else {
            return nil
        }

        let url =
            containerURL.appendingPathComponent(
                "widget-snapshot.json"
            )

        guard let data =
            try? Data(contentsOf: url)
        else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try? decoder.decode(
            WidgetSnapshot.self,
            from: data
        )
    }
}

extension Color {
    init(widgetHex hex: String) {
        let cleaned =
            hex.trimmingCharacters(
                in:
                    CharacterSet
                        .alphanumerics
                        .inverted
            )

        var value: UInt64 = 0

        Scanner(string: cleaned)
            .scanHexInt64(&value)

        let r: Double
        let g: Double
        let b: Double

        if cleaned.count == 6 {
            r = Double(
                (value >> 16) & 0xFF
            ) / 255

            g = Double(
                (value >> 8) & 0xFF
            ) / 255

            b = Double(
                value & 0xFF
            ) / 255
        } else {
            r = 0.25
            g = 0.30
            b = 0.35
        }

        self.init(
            red: r,
            green: g,
            blue: b
        )
    }
}

// MARK: - Team Game configuration

enum WidgetTeamChoice:
    String,
    AppEnum,
    CaseIterable {
    case ANA
    case BOS
    case BUF
    case CAR
    case CBJ
    case CGY
    case CHI
    case COL
    case DAL
    case DET
    case EDM
    case FLA
    case LAK
    case MIN
    case MTL
    case NJD
    case NSH
    case NYI
    case NYR
    case OTT
    case PHI
    case PIT
    case SEA
    case SJS
    case STL
    case TBL
    case TOR
    case UTA
    case VAN
    case VGK
    case WPG
    case WSH

    static var typeDisplayRepresentation:
        TypeDisplayRepresentation {
        "NHL Team"
    }

    static var caseDisplayRepresentations:
        [WidgetTeamChoice:
            DisplayRepresentation] {
        [
            .ANA: "Anaheim Ducks",
            .BOS: "Boston Bruins",
            .BUF: "Buffalo Sabres",
            .CAR: "Carolina Hurricanes",
            .CBJ: "Columbus Blue Jackets",
            .CGY: "Calgary Flames",
            .CHI: "Chicago Blackhawks",
            .COL: "Colorado Avalanche",
            .DAL: "Dallas Stars",
            .DET: "Detroit Red Wings",
            .EDM: "Edmonton Oilers",
            .FLA: "Florida Panthers",
            .LAK: "Los Angeles Kings",
            .MIN: "Minnesota Wild",
            .MTL: "Montreal Canadiens",
            .NJD: "New Jersey Devils",
            .NSH: "Nashville Predators",
            .NYI: "New York Islanders",
            .NYR: "New York Rangers",
            .OTT: "Ottawa Senators",
            .PHI: "Philadelphia Flyers",
            .PIT: "Pittsburgh Penguins",
            .SEA: "Seattle Kraken",
            .SJS: "San Jose Sharks",
            .STL: "St. Louis Blues",
            .TBL: "Tampa Bay Lightning",
            .TOR: "Toronto Maple Leafs",
            .UTA: "Utah Mammoth",
            .VAN: "Vancouver Canucks",
            .VGK: "Vegas Golden Knights",
            .WPG: "Winnipeg Jets",
            .WSH: "Washington Capitals",
        ]
    }
}

struct TeamGameIntent:
    WidgetConfigurationIntent {
    static var title:
        LocalizedStringResource =
        "Team Game"

    static var description =
        IntentDescription(
            "Choose the NHL team this widget follows."
        )

    @Parameter(
        title: "Team",
        default: .NYR
    )
    var team: WidgetTeamChoice
}

struct WidgetTeamLogoView: View {
    let team: WidgetTeam
    let size: CGFloat

    var body: some View {
        Group {
            if let image =
                WidgetTeamLogoStore.image(
                    for: team
                ) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                fallback
            }
        }
        .frame(
            width: size,
            height: size
        )
    }

    private var fallback: some View {
        Text(team.abbreviation)
            .font(
                .system(
                    size:
                        max(
                            8,
                            size * 0.34
                        ),
                    weight: .black,
                    design: .rounded
                )
            )
            .minimumScaleFactor(0.6)
            .foregroundStyle(.white)
            .frame(
                width: size,
                height: size
            )
    }
}

enum WidgetTeamLogoStore {
    static func image(
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
}


extension WidgetGame {
    func containsTeam(
        _ abbreviation: String
    ) -> Bool {
        awayTeam.abbreviation
            .caseInsensitiveCompare(
                abbreviation
            ) == .orderedSame
        ||
        homeTeam.abbreviation
            .caseInsensitiveCompare(
                abbreviation
            ) == .orderedSame
    }

    var isActive: Bool {
        phase == .live
            || phase == .intermission
            || phase == .starting
    }
}
