import Foundation

enum WidgetSampleData {
    static let rangers = WidgetTeam(
        abbreviation: "NYR",
        name: "Rangers",
        accentHex: "#1769C2"
    )

    static let devils = WidgetTeam(
        abbreviation: "NJD",
        name: "Devils",
        accentHex: "#D82032"
    )

    static let islanders = WidgetTeam(
        abbreviation: "NYI",
        name: "Islanders",
        accentHex: "#F47D30"
    )

    static let flyers = WidgetTeam(
        abbreviation: "PHI",
        name: "Flyers",
        accentHex: "#E85A24"
    )

    static let mapleLeafs = WidgetTeam(
        abbreviation: "TOR",
        name: "Maple Leafs",
        accentHex: "#3C73B9"
    )

    static let bruins = WidgetTeam(
        abbreviation: "BOS",
        name: "Bruins",
        accentHex: "#E8B325"
    )

    static let capitals = WidgetTeam(
        abbreviation: "WSH",
        name: "Capitals",
        accentHex: "#567EB4"
    )

    static let hurricanes = WidgetTeam(
        abbreviation: "CAR",
        name: "Hurricanes",
        accentHex: "#9A293E"
    )

    static let avalanche = WidgetTeam(
        abbreviation: "COL",
        name: "Avalanche",
        accentHex: "#7B4560"
    )

    static let stars = WidgetTeam(
        abbreviation: "DAL",
        name: "Stars",
        accentHex: "#23936F"
    )

    static let oilers = WidgetTeam(
        abbreviation: "EDM",
        name: "Oilers",
        accentHex: "#D86B29"
    )

    static let canucks = WidgetTeam(
        abbreviation: "VAN",
        name: "Canucks",
        accentHex: "#3A8495"
    )

    static let kings = WidgetTeam(
        abbreviation: "LAK",
        name: "Kings",
        accentHex: "#85919B"
    )

    static let goldenKnights = WidgetTeam(
        abbreviation: "VGK",
        name: "Golden Knights",
        accentHex: "#B89B56"
    )

    static let teamGame = WidgetGame(
        id: "NYR-NJD",
        awayTeam: rangers,
        homeTeam: devils,
        awayScore: 3,
        homeScore: 2,
        awayProbability: 0.68,
        homeProbability: 0.32,
        phase: .live,
        detail: "2nd · 8:14",
        isFavoriteTeamGame: true
    )

    static let games: [WidgetGame] = [
        teamGame,

        WidgetGame(
            id: "NYI-PHI",
            awayTeam: islanders,
            homeTeam: flyers,
            awayScore: 2,
            homeScore: 2,
            awayProbability: 0.51,
            homeProbability: 0.49,
            phase: .live,
            detail: "3rd · 12:07",
            isFavoriteTeamGame: false
        ),

        WidgetGame(
            id: "TOR-BOS",
            awayTeam: mapleLeafs,
            homeTeam: bruins,
            awayScore: 0,
            homeScore: 0,
            awayProbability: 0.44,
            homeProbability: 0.56,
            phase: .scheduled,
            detail: "7:30 PM",
            isFavoriteTeamGame: false
        ),

        WidgetGame(
            id: "WSH-CAR",
            awayTeam: capitals,
            homeTeam: hurricanes,
            awayScore: 2,
            homeScore: 4,
            awayProbability: 0.00,
            homeProbability: 1.00,
            phase: .final,
            detail: "FINAL",
            isFavoriteTeamGame: false
        ),

        WidgetGame(
            id: "COL-DAL",
            awayTeam: avalanche,
            homeTeam: stars,
            awayScore: 1,
            homeScore: 2,
            awayProbability: 0.39,
            homeProbability: 0.61,
            phase: .intermission,
            detail: "INT · 2nd",
            isFavoriteTeamGame: false
        ),

        WidgetGame(
            id: "EDM-VAN",
            awayTeam: oilers,
            homeTeam: canucks,
            awayScore: 0,
            homeScore: 0,
            awayProbability: 0.57,
            homeProbability: 0.43,
            phase: .starting,
            detail: "STARTING",
            isFavoriteTeamGame: false
        ),

        WidgetGame(
            id: "VGK-LAK",
            awayTeam: goldenKnights,
            homeTeam: kings,
            awayScore: 0,
            homeScore: 0,
            awayProbability: 0.55,
            homeProbability: 0.45,
            phase: .scheduled,
            detail: "10:30 PM",
            isFavoriteTeamGame: false
        )
    ]
}
