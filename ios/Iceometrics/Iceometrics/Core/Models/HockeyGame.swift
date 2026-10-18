import Foundation

nonisolated struct HockeyGame: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let startTime: Date
    let status: GameStatus
    let awayTeam: Team
    let homeTeam: Team
    let awayScore: Int?
    let homeScore: Int?
    let venue: String?
    let gameTypeId: Int?
    let awayShots: Int?
    let homeShots: Int?
    let periodNumber: Int?
    let periodType: String?
    let timeRemaining: String?
    let isIntermission: Bool?
    let league: String?

    init(
        id: String,
        startTime: Date,
        status: GameStatus,
        awayTeam: Team,
        homeTeam: Team,
        awayScore: Int?,
        homeScore: Int?,
        venue: String?,
        gameTypeId: Int? = nil,
        awayShots: Int? = nil,
        homeShots: Int? = nil,
        periodNumber: Int? = nil,
        periodType: String? = nil,
        timeRemaining: String? = nil,
        isIntermission: Bool? = nil,
        league: String? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.status = status
        self.awayTeam = awayTeam
        self.homeTeam = homeTeam
        self.awayScore = awayScore
        self.homeScore = homeScore
        self.venue = venue
        self.gameTypeId = gameTypeId
        self.awayShots = awayShots
        self.homeShots = homeShots
        self.periodNumber = periodNumber
        self.periodType = periodType
        self.timeRemaining = timeRemaining
        self.isIntermission = isIntermission
        self.league = league
    }

    // Shared hockey clock notation for Standard, Smart Fill and Game Details.
    // Intermissions are named for the period just completed, not the upcoming OT.
    var scoreboardLiveText: String {
        guard status == .live else { return status.rawValue }

        let period = max(0, periodNumber ?? 0)
        let type = (periodType ?? "").uppercased()
        if isIntermission == true {
            let clock = (timeRemaining ?? "").trimmingCharacters(in: .whitespaces)
            let upcomingPeriod = period >= 4
                && (clock == "20:00" || clock == "05:00" || clock == "5:00")
            let justCompleted = max(1, period - (upcomingPeriod ? 1 : 0))
            return "\(Self.scoreboardOrdinal(justCompleted)) Int."
        }
        if type == "SO" { return "SO" }

        let periodLabel: String
        if period <= 3 && period > 0 {
            periodLabel = Self.scoreboardOrdinal(period)
        } else if period >= 4 || type == "OT" {
            let overtimeNumber = max(1, period - 3)
            periodLabel = overtimeNumber == 1 ? "OT" : "\(overtimeNumber) OT"
        } else {
            periodLabel = "Live"
        }

        let clock = (timeRemaining ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clock.isEmpty ? periodLabel : "\(periodLabel) · \(clock)"
    }

    private static func scoreboardOrdinal(_ period: Int) -> String {
        let ending: String
        if (11...13).contains(period % 100) {
            ending = "th"
        } else {
            switch period % 10 {
            case 1: ending = "st"
            case 2: ending = "nd"
            case 3: ending = "rd"
            default: ending = "th"
            }
        }
        return "\(period)\(ending)"
    }

    var leagueCode: String {
        league?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .nilIfEmpty
            ?? awayTeam.leagueCode
    }
}

private nonisolated extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
