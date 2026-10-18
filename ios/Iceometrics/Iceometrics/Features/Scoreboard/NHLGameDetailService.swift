import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

nonisolated struct NHLPeriodShots: Identifiable, Sendable, Equatable {
    let period: Int
    let label: String
    let away: Int
    let home: Int

    var id: Int { period }
}

nonisolated struct NHLGameStatLine: Identifiable, Sendable, Equatable {
    let label: String
    let awayValue: String
    let homeValue: String

    var id: String { label }
}

nonisolated struct NHLGoalieSlot: Sendable, Equatable {
    let label: String
    let name: String
}

// ICEOMETRICS_NOTES_BIGPASS08_ASSISTS
nonisolated struct NHLGoalScorer: Identifiable, Sendable, Equatable {
    let id: String
    let team: String
    let player: String
    let period: String
    let time: String
    let assists: [String] // Parsed from NHL play-by-play when available.
}

nonisolated struct NHLPenaltySummary: Identifiable, Sendable, Equatable {
    let id: String
    let team: String
    let period: String
    let time: String
    let description: String
}

nonisolated struct NHLTeamLeaders: Sendable, Equatable {
    let goals: String?
    let assists: String?
    let points: String?
}

nonisolated struct NHLSpecialTeamsContext: Sendable, Equatable {
    let state: String?
    let awayPenaltiesTaken: Int?
    let awayPenaltiesDrawn: Int?
    let homePenaltiesTaken: Int?
    let homePenaltiesDrawn: Int?
}

nonisolated struct NHLGameDetail: Sendable, Equatable {
    let shotsByPeriod: [NHLPeriodShots]
    let stats: [NHLGameStatLine]
    let awayGoalie: NHLGoalieSlot?
    let homeGoalie: NHLGoalieSlot?
    let goalScorers: [NHLGoalScorer]
    let awayScratches: [String]
    let homeScratches: [String]
    let awayLeaders: NHLTeamLeaders
    let homeLeaders: NHLTeamLeaders
    let specialTeams: NHLSpecialTeamsContext
    let penalties: [NHLPenaltySummary]
}

nonisolated enum NHLGameDetailError: LocalizedError, Sendable {
    case invalidGameID
    case invalidData

    var errorDescription: String? {
        switch self {
        case .invalidGameID:
            "Game details are not available for this game."
        case .invalidData:
            "Iceometrics could not read the game statistics."
        }
    }
}

// NHL play-by-play publishes skater counts, not an inferred penalty timer.
// Hide unreported/stale situations rather than inventing a power play.
nonisolated struct NHLOnIceStrength: Sendable, Equatable {
    let awayBadge: String?
    let homeBadge: String?
    let centerBadge: String?
}

nonisolated struct NHLGameDetailService: Sendable {
    static let missingText = "⚠︎ NF"

    func fetchOnIceStrength(for game: HockeyGame) async -> NHLOnIceStrength? {
        guard game.status == .live, game.isIntermission != true,
              game.leagueCode == "NHL",
              Int(game.id) != nil,
              let url = URL(string:
                "https://api-web.nhle.com/v1/gamecenter/\(game.id)/play-by-play"
              ),
              let payload = Self.jsonObject(await Self.fetchDataIfAvailable(url)) else {
            return nil
        }
        let plays = Self.dictionaries(payload["plays"])
        guard let mostRecent = plays.last,
              let strength = Self.strengthBadges(from: Self.string(mostRecent["situationCode"])) else {
            return nil
        }
        // A previous period's final play cannot establish the current PP.
        let period = Self.integer(Self.dictionary(mostRecent["periodDescriptor"])["number"])
        if let current = game.periodNumber, current > 0, period != current {
            return nil
        }
        return strength
    }

    static func strengthBadges(from code: String) -> NHLOnIceStrength? {
        let digits = code.filter(\.isNumber)
        guard digits.count == 4,
              let away = Int(String(Array(digits)[1])),
              let home = Int(String(Array(digits)[2])),
              (3...6).contains(away), (3...6).contains(home) else {
            return nil
        }
        // Six skaters means a pulled goalie/extra attacker, NOT a power play.
        // Show "Empty Net" over the six-skater team's logo.
        if away == 6 || home == 6 {
            return NHLOnIceStrength(
                awayBadge: away == 6 ? "Empty Net" : nil,
                homeBadge: home == 6 ? "Empty Net" : nil,
                centerBadge: nil
            )
        }
        if away == 4 && home == 4 {
            return NHLOnIceStrength(
                awayBadge: nil, homeBadge: nil, centerBadge: "4 on 4"
            )
        }
        if away > home {
            let label = away == 5 && home == 4
                ? "PP" : "\(away) on \(home) PP"
            return NHLOnIceStrength(
                awayBadge: label, homeBadge: nil, centerBadge: nil
            )
        }
        if home > away {
            let label = home == 5 && away == 4
                ? "PP" : "\(home) on \(away) PP"
            return NHLOnIceStrength(
                awayBadge: nil, homeBadge: label, centerBadge: nil
            )
        }
        return nil
    }


    func fetchDetail(for game: HockeyGame) async throws -> NHLGameDetail {
        guard Int(game.id) != nil else {
            throw NHLGameDetailError.invalidGameID
        }

        let base = "https://api-web.nhle.com/v1"
        let gameID = game.id
        let season = Self.seasonCompact(for: game)
        let gameType = game.gameTypeId ?? 2

        guard let playURL = URL(
            string: "\(base)/gamecenter/\(gameID)/play-by-play"
        ), let boxURL = URL(
            string: "\(base)/gamecenter/\(gameID)/boxscore"
        ), let rightRailURL = URL(
            string: "\(base)/gamecenter/\(gameID)/right-rail"
        ), let awayClubURL = URL(
            string: "\(base)/club-stats/\(game.awayTeam.abbreviation)/\(season)/\(gameType)"
        ), let homeClubURL = URL(
            string: "\(base)/club-stats/\(game.homeTeam.abbreviation)/\(season)/\(gameType)"
        ) else {
            throw NHLGameDetailError.invalidGameID
        }

        async let playData = Self.fetchDataIfAvailable(playURL)
        async let boxData = Self.fetchDataIfAvailable(boxURL)
        async let railData = Self.fetchDataIfAvailable(rightRailURL)
        async let awayClubData = Self.fetchDataIfAvailable(awayClubURL)
        async let homeClubData = Self.fetchDataIfAvailable(homeClubURL)

        let (playBlob, boxBlob, railBlob, awayBlob, homeBlob) = await (
            playData,
            boxData,
            railData,
            awayClubData,
            homeClubData
        )

        let playByPlay = Self.jsonObject(playBlob)
        let boxscore = Self.jsonObject(boxBlob)
        let rightRail = Self.jsonObject(railBlob)
        let awayClub = Self.jsonObject(awayBlob)
        let homeClub = Self.jsonObject(homeBlob)

        return Self.buildDetail(
            playByPlay: playByPlay,
            boxscore: boxscore,
            rightRail: rightRail,
            awayClub: awayClub,
            homeClub: homeClub,
            game: game
        )
    }

    static func parse(
        data: Data,
        game: HockeyGame
    ) throws -> NHLGameDetail {
        guard let root = jsonObject(data) else {
            throw NHLGameDetailError.invalidData
        }

        return buildDetail(
            playByPlay: root,
            boxscore: nil,
            rightRail: nil,
            awayClub: nil,
            homeClub: nil,
            game: game
        )
    }

    private static func buildDetail(
        playByPlay: [String: Any]?,
        boxscore: [String: Any]?,
        rightRail: [String: Any]?,
        awayClub: [String: Any]?,
        homeClub: [String: Any]?,
        game: HockeyGame
    ) -> NHLGameDetail {
        let pbp = playByPlay ?? [:]
        let awayTeam = dictionary(pbp["awayTeam"])
        let homeTeam = dictionary(pbp["homeTeam"])
        let awayID = integer(awayTeam["id"])
        let homeID = integer(homeTeam["id"])
        let plays = dictionaries(pbp["plays"])
        let playerNames = playerNameMap(from: pbp)

        var shotsByPeriod: [Int: (away: Int, home: Int)] = [:]
        var awayStats = TeamEventStats()
        var homeStats = TeamEventStats()
        var seenTypes = Set<String>()
        var goalScorers: [NHLGoalScorer] = []
        var penalties: [NHLPenaltySummary] = []
        var awayPenalties = 0
        var homePenalties = 0
        var latestSituationCode: String?

        for (index, play) in plays.enumerated() {
            let type = string(play["typeDescKey"]).lowercased()
            guard !type.isEmpty else { continue }
            seenTypes.insert(type)

            let details = dictionary(play["details"])
            let descriptor = dictionary(play["periodDescriptor"])
            let period = integer(descriptor["number"])
            let ownerID = integer(details["eventOwnerTeamId"])
            let situationCode = string(play["situationCode"])
            if !situationCode.isEmpty {
                latestSituationCode = situationCode
            }

            let side: TeamSide?
            if ownerID > 0, ownerID == awayID {
                side = .away
            } else if ownerID > 0, ownerID == homeID {
                side = .home
            } else {
                side = nil
            }

            if period > 0,
               (type == "shot-on-goal" || type == "goal"),
               let side {
                var bucket = shotsByPeriod[period] ?? (away: 0, home: 0)
                switch side {
                case .away:
                    bucket.away += 1
                case .home:
                    bucket.home += 1
                }
                shotsByPeriod[period] = bucket
            }

            if type == "goal", let side {
                let scorerID = integer(details["scoringPlayerId"])
                let scorer = playerNames[scorerID]
                    ?? localizedText(details["scoringPlayerName"])
                    ?? Self.missingText
                // NHL play-by-play identifies up to two assisting players.
                // Suppress missing/unknown values instead of showing bogus NF.
                let assistingPlayers: [(Int, String?)] = [
                    (integer(details["assist1PlayerId"]),
                     localizedText(details["assist1PlayerName"])),
                    (integer(details["assist2PlayerId"]),
                     localizedText(details["assist2PlayerName"]))
                ]
                let assists = unique(assistingPlayers.compactMap { id, name in
                    playerNames[id] ?? name
                })
                goalScorers.append(
                    NHLGoalScorer(
                        id: "goal-\(index)",
                        team: side == .away
                            ? game.awayTeam.abbreviation
                            : game.homeTeam.abbreviation,
                        player: scorer,
                        period: periodLabel(period),
                        time: string(play["timeInPeriod"]).nilIfEmpty
                            ?? Self.missingText,
                        assists: assists
                    )
                )
            }

            if type == "penalty", let side {
                let duration = integer(
                    details["duration"] ?? details["durationMinutes"]
                )
                let committedID = integer(details["committedByPlayerId"])
                let drawnID = integer(details["drawnByPlayerId"])
                let offender = playerNames[committedID] ?? Self.missingText
                let drawn = playerNames[drawnID]
                let reason = string(
                    details["descKey"] ?? details["reason"]
                )
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
                let reasonText = reason.isEmpty ? "Penalty" : reason
                let minutes = duration > 0 ? "\(duration) min" : Self.missingText
                let drawnText = drawn.map { " on \($0)" } ?? ""
                let teamCode = side == .away
                    ? game.awayTeam.abbreviation
                    : game.homeTeam.abbreviation

                penalties.append(
                    NHLPenaltySummary(
                        id: "penalty-\(index)",
                        team: teamCode,
                        period: periodLabel(period),
                        time: string(play["timeInPeriod"]).nilIfEmpty
                            ?? Self.missingText,
                        description: "\(offender) — \(minutes) \(reasonText)\(drawnText)"
                    )
                )

                switch side {
                case .away:
                    awayPenalties += 1
                case .home:
                    homePenalties += 1
                }
            }

            guard let side else { continue }
            switch side {
            case .away:
                awayStats.apply(type: type, details: details)
            case .home:
                homeStats.apply(type: type, details: details)
            }
        }

        var periods = shotsByPeriod.keys.sorted().map { period in
            let bucket = shotsByPeriod[period] ?? (away: 0, home: 0)
            return NHLPeriodShots(
                period: period,
                label: periodLabel(period),
                away: bucket.away,
                home: bucket.home
            )
        }

        if periods.isEmpty,
           let awayShots = game.awayShots,
           let homeShots = game.homeShots {
            periods = [
                NHLPeriodShots(
                    period: 0,
                    label: "Total",
                    away: awayShots,
                    home: homeShots
                )
            ]
        }

        let awayShots = game.awayShots
            ?? periods.reduce(0) { $0 + $1.away }
        let homeShots = game.homeShots
            ?? periods.reduce(0) { $0 + $1.home }
        let hasShotData = game.awayShots != nil
            || game.homeShots != nil
            || !shotsByPeriod.isEmpty
        let faceoffTotal = awayStats.faceoffWins + homeStats.faceoffWins
        // NHL right-rail reports the actual game PP totals (e.g. 1/3).
        // Do not derive opportunities or invent a 0 when absent.
        let powerPlayRow = dictionaries(rightRail?["teamGameStats"]).first {
            string($0["category"]).lowercased() == "powerplay"
        }
        let awayPowerPlay = string(powerPlayRow?["awayValue"]).nilIfEmpty
        let homePowerPlay = string(powerPlayRow?["homeValue"]).nilIfEmpty

        let stats = [
            NHLGameStatLine(
                label: "Shots On Goal",
                awayValue: hasShotData ? String(awayShots) : Self.missingText,
                homeValue: hasShotData ? String(homeShots) : Self.missingText
            ),
            NHLGameStatLine(
                label: "Face-off %",
                awayValue: seenTypes.contains("faceoff") && faceoffTotal > 0
                    ? percent(Double(awayStats.faceoffWins) / Double(faceoffTotal))
                    : Self.missingText,
                homeValue: seenTypes.contains("faceoff") && faceoffTotal > 0
                    ? percent(Double(homeStats.faceoffWins) / Double(faceoffTotal))
                    : Self.missingText
            ),
            NHLGameStatLine(
                label: "Power Play",
                awayValue: awayPowerPlay ?? Self.missingText,
                homeValue: homePowerPlay ?? Self.missingText
            ),
            statLine(
                label: "Penalty Minutes",
                type: "penalty",
                seenTypes: seenTypes,
                away: awayStats.penaltyMinutes,
                home: homeStats.penaltyMinutes
            ),
            statLine(
                label: "Hits",
                type: "hit",
                seenTypes: seenTypes,
                away: awayStats.hits,
                home: homeStats.hits
            ),
            statLine(
                label: "Blocked Shots",
                type: "blocked-shot",
                seenTypes: seenTypes,
                away: awayStats.blockedShots,
                home: homeStats.blockedShots
            ),
            statLine(
                label: "Giveaways",
                type: "giveaway",
                seenTypes: seenTypes,
                away: awayStats.giveaways,
                home: homeStats.giveaways
            ),
            statLine(
                label: "Takeaways",
                type: "takeaway",
                seenTypes: seenTypes,
                away: awayStats.takeaways,
                home: homeStats.takeaways
            )
        ]

        let boxPlayerStats = dictionary(boxscore?["playerByGameStats"])
        let awayBox = dictionary(boxPlayerStats["awayTeam"])
        let homeBox = dictionary(boxPlayerStats["homeTeam"])

        // Never infer a starter from season totals or live save counts.
        // An official starter flag is the only supported source until a
        // documented MoneyPuck starter feed is integrated.
        let awayGoalie = goalieSlot(boxGoalies: dictionaries(awayBox["goalies"]))
        let homeGoalie = goalieSlot(boxGoalies: dictionaries(homeBox["goalies"]))

        let railAwayScratches = scratchesFromRightRail(
            rightRail, teamKey: "awayTeam", playerNames: playerNames
        )
        let railHomeScratches = scratchesFromRightRail(
            rightRail, teamKey: "homeTeam", playerNames: playerNames
        )
        let awayScratches = railAwayScratches.isEmpty ? scratches(
            boxscore: boxscore, teamKey: "awayTeam", playerNames: playerNames
        ) : railAwayScratches
        let homeScratches = railHomeScratches.isEmpty ? scratches(
            boxscore: boxscore, teamKey: "homeTeam", playerNames: playerNames
        ) : railHomeScratches

        return NHLGameDetail(
            shotsByPeriod: periods,
            stats: stats,
            awayGoalie: awayGoalie,
            homeGoalie: homeGoalie,
            goalScorers: goalScorers,
            awayScratches: awayScratches,
            homeScratches: homeScratches,
            awayLeaders: leaders(from: awayClub),
            homeLeaders: leaders(from: homeClub),
            specialTeams: NHLSpecialTeamsContext(
                state: specialTeamsState(
                    situationCode: latestSituationCode,
                    awayCode: game.awayTeam.abbreviation,
                    homeCode: game.homeTeam.abbreviation
                ),
                awayPenaltiesTaken: seenTypes.contains("penalty")
                    ? awayPenalties : nil,
                awayPenaltiesDrawn: seenTypes.contains("penalty")
                    ? homePenalties : nil,
                homePenaltiesTaken: seenTypes.contains("penalty")
                    ? homePenalties : nil,
                homePenaltiesDrawn: seenTypes.contains("penalty")
                    ? awayPenalties : nil
            ),
            penalties: penalties
        )
    }

    private static func fetchDataIfAvailable(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  200..<300 ~= http.statusCode else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private static func jsonObject(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func statLine(
        label: String,
        type: String,
        seenTypes: Set<String>,
        away: Int,
        home: Int
    ) -> NHLGameStatLine {
        NHLGameStatLine(
            label: label,
            awayValue: seenTypes.contains(type) ? String(away) : missingText,
            homeValue: seenTypes.contains(type) ? String(home) : missingText
        )
    }

    private static func goalieSlot(
        boxGoalies: [[String: Any]]
    ) -> NHLGoalieSlot? {
        // Only a documented boxscore "starter" boolean counts as a starter.
        // The strongest season goalie or most active live goalie could be a
        // backup, so neither is suitable as a substitute.
        guard let starter = boxGoalies.first(where: { boolean($0["starter"]) }),
              let name = playerName(starter) else {
            return nil
        }
        return NHLGoalieSlot(label: "NHL confirmed", name: name)
    }

    private static func scratchesFromRightRail(
        _ rightRail: [String: Any]?,
        teamKey: String,
        playerNames: [Int: String]
    ) -> [String] {
        let gameInfo = dictionary(rightRail?["gameInfo"])
        let teamInfo = dictionary(gameInfo[teamKey])
        let names = dictionaries(teamInfo["scratches"]).compactMap { row in
            playerName(row)
                ?? playerNames[integer(row["id"])]
                ?? playerNames[integer(row["playerId"])]
        }
        return unique(names)
    }

    private static func scratches(
        boxscore: [String: Any]?,
        teamKey: String,
        playerNames: [Int: String]
    ) -> [String] {
        guard let boxscore else { return [] }

        var sources: [[String: Any]] = []
        let team = dictionary(boxscore[teamKey])
        if !team.isEmpty { sources.append(team) }

        let pstats = dictionary(boxscore["playerByGameStats"])
        let playerTeam = dictionary(pstats[teamKey])
        if !playerTeam.isEmpty { sources.append(playerTeam) }

        let gameInfo = dictionary(boxscore["gameInfo"])
        let infoTeam = dictionary(gameInfo[teamKey])
        if !infoTeam.isEmpty { sources.append(infoTeam) }

        for source in sources {
            for key in [
                "scratches",
                "scratchedPlayers",
                "scratchedSkaters",
                "projectedScratches"
            ] {
                let names = dictionaries(source[key]).compactMap { row in
                    playerName(row)
                        ?? playerNames[integer(row["playerId"])]
                        ?? playerNames[integer(row["id"])]
                }
                if !names.isEmpty {
                    return unique(names)
                }
            }
        }

        return []
    }

    private static func leaders(
        from club: [String: Any]?
    ) -> NHLTeamLeaders {
        let skaters = dictionaries(club?["skaters"])
        return NHLTeamLeaders(
            goals: leader(skaters, metric: "goals"),
            assists: leader(skaters, metric: "assists"),
            points: leader(skaters, metric: "points")
        )
    }

    private static func leader(
        _ rows: [[String: Any]],
        metric: String
    ) -> String? {
        guard let row = rows.max(by: {
            integer($0[metric]) < integer($1[metric])
        }), let name = playerName(row) else {
            return nil
        }

        return "\(name) (\(integer(row[metric])))"
    }

    private static func specialTeamsState(
        situationCode: String?,
        awayCode: String,
        homeCode: String
    ) -> String? {
        guard let situationCode else { return nil }
        let digits = situationCode.filter(\.isNumber)
        guard digits.count >= 4 else { return nil }
        let values = digits.suffix(4).compactMap { Int(String($0)) }
        guard values.count == 4 else { return nil }

        let awaySkaters = values[1]
        let homeSkaters = values[2]
        guard (3...6).contains(awaySkaters),
              (3...6).contains(homeSkaters) else { return nil }
        if awaySkaters == 6 || homeSkaters == 6 {
            let club = awaySkaters == 6 ? awayCode : homeCode
            return "\(club) Empty Net"
        }
        if awaySkaters == 4 && homeSkaters == 4 { return "4 on 4" }
        if awaySkaters > homeSkaters {
            return "\(awayCode) Power Play"
        }
        if homeSkaters > awaySkaters {
            return "\(homeCode) Power Play"
        }
        return "Even Strength"
    }

    private static func playerNameMap(
        from pbp: [String: Any]
    ) -> [Int: String] {
        var values: [Int: String] = [:]
        for row in dictionaries(pbp["rosterSpots"]) {
            let id = integer(row["playerId"])
            if id > 0, let name = playerName(row) {
                values[id] = name
            }
        }
        return values
    }

    private static func playerName(_ row: [String: Any]) -> String? {
        if let name = localizedText(row["name"]) {
            return name
        }
        let first = localizedText(row["firstName"])
        let last = localizedText(row["lastName"])
        let full = [first, last]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? nil : full
    }

    private static func localizedText(_ value: Any?) -> String? {
        if let value = value as? String {
            return value.nilIfEmpty
        }
        if let value = value as? [String: Any] {
            for key in ["default", "en", "name", "fullName"] {
                if let text = value[key] as? String,
                   let result = text.nilIfEmpty {
                    return result
                }
            }
        }
        return nil
    }

    private static func dictionary(_ value: Any?) -> [String: Any] {
        value as? [String: Any] ?? [:]
    }

    private static func dictionaries(_ value: Any?) -> [[String: Any]] {
        value as? [[String: Any]] ?? []
    }

    private static func integer(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) ?? 0 }
        return 0
    }

    private static func boolean(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            return ["true", "1", "yes"].contains(value.lowercased())
        }
        return false
    }

    private static func string(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }

    private static func periodLabel(_ period: Int) -> String {
        switch period {
        case 1: "1st"
        case 2: "2nd"
        case 3: "3rd"
        case 4: "OT"
        case 5: "SO"
        default: period > 0 ? "P\(period)" : missingText
        }
    }

    private static func percent(_ value: Double) -> String {
        value.formatted(
            .percent.precision(.fractionLength(1))
        )
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func seasonCompact(for game: HockeyGame) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let parts = calendar.dateComponents([.year, .month], from: game.startTime)
        let year = parts.year ?? Calendar.current.component(.year, from: game.startTime)
        let month = parts.month ?? 1
        let start = month >= 7 ? year : year - 1
        return "\(start)\(start + 1)"
    }
}

private nonisolated enum TeamSide: Sendable {
    case away
    case home
}

private nonisolated struct TeamEventStats: Sendable {
    var faceoffWins = 0
    var hits = 0
    var blockedShots = 0
    var giveaways = 0
    var takeaways = 0
    var penaltyMinutes = 0

    mutating func apply(
        type: String,
        details: [String: Any]
    ) {
        switch type {
        case "faceoff":
            faceoffWins += 1
        case "hit":
            hits += 1
        case "blocked-shot":
            blockedShots += 1
        case "giveaway":
            giveaways += 1
        case "takeaway":
            takeaways += 1
        case "penalty":
            penaltyMinutes += Self.integer(
                details["duration"] ?? details["durationMinutes"]
            )
        default:
            break
        }
    }

    private static func integer(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) ?? 0 }
        return 0
    }
}

private nonisolated extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
