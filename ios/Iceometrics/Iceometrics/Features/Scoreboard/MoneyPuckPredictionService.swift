import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

nonisolated struct MoneyPuckGamePrediction: Sendable, Equatable {
    let awayWinProbability: Double
    let homeWinProbability: Double
}

nonisolated struct MoneyPuckPredictionService: Sendable {
    private static let predictionsURL = URL(
        string: "https://moneypuck.com/moneypuck/predictions/"
    )!

    func fetchPredictions(
        for date: Date,
        games: [HockeyGame]
    ) async throws -> [String: MoneyPuckGamePrediction] {
        guard !games.isEmpty else { return [:] }

        return await withTaskGroup(
            of: (String, MoneyPuckGamePrediction?).self,
            returning: [String: MoneyPuckGamePrediction].self
        ) { group in
            for game in games {
                guard game.leagueCode == "NHL" else {
                    continue
                }

                group.addTask {
                    let prediction: MoneyPuckGamePrediction?

                    switch game.status {
                    case .scheduled:
                        prediction = await Self.fetchPregamePrediction(
                            for: game
                        )

                    case .live:
                        prediction = await Self.fetchLivePrediction(
                            for: game
                        )

                    default:
                        prediction = nil
                    }

                    return (game.id, prediction)
                }
            }

            var values: [String: MoneyPuckGamePrediction] = [:]

            for await (gameID, prediction) in group {
                if let prediction {
                    values[gameID] = prediction
                }
            }

            return values
        }
    }

    private static func fetchPregamePrediction(
        for game: HockeyGame
    ) async -> MoneyPuckGamePrediction? {
        guard Int(game.id) != nil,
              let url = URL(
                string:
                    "https://moneypuck.com/moneypuck/predictions/\(game.id).csv"
              )
        else {
            return nil
        }

        var request = request(
            for: url,
            accept: "text/csv,*/*"
        )

        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            let (data, response) = try await URLSession.shared.data(
                for: request
            )

            guard let http = response as? HTTPURLResponse,
                  200..<300 ~= http.statusCode,
                  let csv = String(
                    data: data,
                    encoding: .utf8
                  ),
                  !csv.isEmpty
            else {
                return nil
            }

            return parsePregamePrediction(
                csv: csv,
                game: game
            )
        } catch {
            return nil
        }
    }

    static func parsePregamePrediction(
        csv: String,
        game: HockeyGame
    ) -> MoneyPuckGamePrediction? {
        let lines = csv
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        guard lines.count >= 2 else {
            return nil
        }

        let headers = parseCSVLine(lines[0])
        let values = parseCSVLine(lines[1])

        guard !headers.isEmpty,
              !values.isEmpty else {
            return nil
        }

        var row: [String: String] = [:]

        for (index, header) in headers.enumerated()
            where values.indices.contains(index) {
            row[header] = values[index]
        }

        // Validate that this prediction file actually belongs
        // to the NHL game we requested.
        if let csvGameID = row["gameID"],
           csvGameID != game.id {
            return nil
        }

        if let homeCode = row["homeTeamCode"],
           homeCode.caseInsensitiveCompare(
                game.homeTeam.abbreviation
           ) != .orderedSame {
            return nil
        }

        if let roadCode = row["roadTeamCode"],
           roadCode.caseInsensitiveCompare(
                game.awayTeam.abbreviation
           ) != .orderedSame {
            return nil
        }

        // These are the exact fields displayed as "Chance of Winning"
        // on MoneyPuck's game-predictions page.
        guard let away = probability(
            row["preGameAwayTeamWinOverallScore"]
        ),
        let home = probability(
            row["preGameHomeTeamWinOverallScore"]
        )
        else {
            return nil
        }

        let total = away + home

        guard total > 0 else {
            return nil
        }

        return MoneyPuckGamePrediction(
            awayWinProbability: away / total,
            homeWinProbability: home / total
        )
    }

    private static func fetchLivePrediction(
        for game: HockeyGame
    ) async -> MoneyPuckGamePrediction? {
        guard Int(game.id) != nil else { return nil }

        for season in seasonCandidates(for: game) {
            guard let url = URL(
                string: "https://moneypuck.com/moneypuck/gameData/\(season)/\(game.id).csv"
            ) else {
                continue
            }

            var request = request(for: url, accept: "text/csv,*/*")
            request.timeoutInterval = 8

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      200..<300 ~= http.statusCode,
                      let csv = String(data: data, encoding: .utf8),
                      let prediction = parseLivePrediction(csv: csv) else {
                    continue
                }
                return prediction
            } catch {
                continue
            }
        }

        return nil
    }

    static func parseLivePrediction(
        csv: String
    ) -> MoneyPuckGamePrediction? {
        let lines = csv
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        guard let first = lines.first else { return nil }

        let headers = parseCSVLine(first)
        guard !headers.isEmpty else { return nil }

        var latest: MoneyPuckGamePrediction?
        for line in lines.dropFirst() {
            let values = parseCSVLine(line)
            guard !values.isEmpty else { continue }

            var row: [String: String] = [:]
            for (index, header) in headers.enumerated()
                where values.indices.contains(index) {
                row[header] = values[index]
            }

            var away = probability(row["liveAwayTeamWinOverallScore"])
            var home = probability(row["liveHomeTeamWinOverallScore"])

            if away == nil || home == nil,
               let alternateHome = probability(row["homeWinProbability"]) {
                home = alternateHome
                away = probability(row["awayWinProbability"])
                    ?? max(0, min(1, 1 - alternateHome))
            }

            guard let away, let home else { continue }
            let total = away + home
            guard total > 0 else { continue }

            let normalizedAway: Double
            let normalizedHome: Double
            if 0.90...1.10 ~= total {
                normalizedAway = away
                normalizedHome = home
            } else {
                normalizedAway = max(0, min(1, away / total))
                normalizedHome = max(0, min(1, home / total))
            }

            latest = MoneyPuckGamePrediction(
                awayWinProbability: normalizedAway,
                homeWinProbability: normalizedHome
            )
        }

        return latest
    }

    private static func request(
        for url: URL,
        accept: String
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                + "AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(
            "https://moneypuck.com/",
            forHTTPHeaderField: "Referer"
        )
        return request
    }

    private static func seasonCandidates(for game: HockeyGame) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let parts = calendar.dateComponents([.year, .month], from: game.startTime)
        guard let year = parts.year, let month = parts.month else { return [] }

        let startYear = month >= 7 ? year : year - 1
        var values = ["\(startYear)\(startYear + 1)"]

        if game.id.count >= 4,
           let idYear = Int(game.id.prefix(4)) {
            let fromID = "\(idYear)\(idYear + 1)"
            if !values.contains(fromID) {
                values.append(fromID)
            }
        }

        return values
    }

    private static func probability(_ raw: String?) -> Double? {
        guard let raw,
              let value = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              value >= 0 else {
            return nil
        }

        if value <= 1 {
            return value
        }
        if value <= 100 {
            return value / 100
        }
        return nil
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var values: [String] = []
        var current = ""
        var insideQuotes = false
        var index = line.startIndex

        while index < line.endIndex {
            let char = line[index]
            if char == "\"" {
                let next = line.index(after: index)
                if insideQuotes,
                   next < line.endIndex,
                   line[next] == "\"" {
                    current.append("\"")
                    index = line.index(after: next)
                    continue
                }
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
                values.append(current)
                current = ""
            } else {
                current.append(char)
            }
            index = line.index(after: index)
        }

        values.append(current)
        return values
    }

    static func parsePredictions(
        html: String,
        games: [HockeyGame]
    ) -> [String: MoneyPuckGamePrediction] {
        let rows = regexMatches(
            pattern: #"(?is)<tr[^>]*>.*?</tr>"#,
            in: html
        )

        let candidateRows = rows.isEmpty ? [html] : rows
        var output: [String: MoneyPuckGamePrediction] = [:]

        for game in games {
            guard let row = candidateRows.first(where: {
                rowContainsGame($0, game: game)
            }),
            let prediction = prediction(
                from: row,
                game: game
            ) else {
                continue
            }

            output[game.id] = prediction
        }

        return output
    }

    private static func prediction(
        from htmlRow: String,
        game: HockeyGame
    ) -> MoneyPuckGamePrediction? {
        let plain = normalized(stripHTML(htmlRow))
        let percentRegex = try? NSRegularExpression(
            pattern: #"(\d{1,3}(?:\.\d+)?)\s*%"#
        )
        let fullRange = NSRange(plain.startIndex..., in: plain)
        let matches = percentRegex?.matches(
            in: plain,
            range: fullRange
        ) ?? []

        var percentages: [(position: Int, value: Double)] = []
        for match in matches {
            guard match.numberOfRanges >= 2,
                  let valueRange = Range(match.range(at: 1), in: plain),
                  let value = Double(plain[valueRange]),
                  0...100 ~= value else {
                continue
            }

            percentages.append(
                (position: match.range.location, value: value / 100.0)
            )
        }

        guard percentages.count >= 2,
              let awayPosition = teamPosition(
                game.awayTeam,
                in: plain
              ),
              let homePosition = teamPosition(
                game.homeTeam,
                in: plain
              ) else {
            return nil
        }

        var available = percentages
        guard let away = popNearest(
            to: awayPosition,
            from: &available
        ),
        let home = popNearest(
            to: homePosition,
            from: &available
        ) else {
            return nil
        }

        return MoneyPuckGamePrediction(
            awayWinProbability: away,
            homeWinProbability: home
        )
    }

    private static func rowContainsGame(
        _ htmlRow: String,
        game: HockeyGame
    ) -> Bool {
        let plain = normalized(stripHTML(htmlRow))
        return teamPosition(game.awayTeam, in: plain) != nil
            && teamPosition(game.homeTeam, in: plain) != nil
    }

    private static func teamPosition(
        _ team: Team,
        in normalizedRow: String
    ) -> Int? {
        for alias in aliases(for: team) {
            let needle = normalized(alias)
            guard !needle.isEmpty,
                  let range = normalizedRow.range(of: needle) else {
                continue
            }

            return normalizedRow.distance(
                from: normalizedRow.startIndex,
                to: range.lowerBound
            )
        }

        return nil
    }

    private static func popNearest(
        to position: Int,
        from values: inout [(position: Int, value: Double)]
    ) -> Double? {
        guard let index = values.indices.min(by: {
            abs(values[$0].position - position)
                < abs(values[$1].position - position)
        }) else {
            return nil
        }

        return values.remove(at: index).value
    }

    private static func aliases(for team: Team) -> [String] {
        var values = [team.name, team.abbreviation]
        if let fullName = fullTeamNames[team.abbreviation.uppercased()] {
            values.append(fullName)
        }
        return values
            .map { normalized($0) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
    }

    private static func stripHTML(_ value: String) -> String {
        var text = value
        text = replacing(
            pattern: #"(?is)<(script|style).*?>.*?</\1>"#,
            in: text,
            with: " "
        )
        text = replacing(
            pattern: #"(?is)<br\s*/?>"#,
            in: text,
            with: " "
        )
        text = replacing(
            pattern: #"(?is)<[^>]+>"#,
            in: text,
            with: " "
        )

        return text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    private static func normalized(_ value: String) -> String {
        let upper = value.uppercased()
        let scalars = upper.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar)
                || scalar == "%"
                || scalar == "." {
                return Character(String(scalar))
            }
            return " "
        }

        return String(scalars)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func regexMatches(
        pattern: String,
        in value: String
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(value.startIndex..., in: value)
        return regex.matches(in: value, range: range).compactMap {
            guard let matchRange = Range($0.range, in: value) else {
                return nil
            }
            return String(value[matchRange])
        }
    }

    private static func replacing(
        pattern: String,
        in value: String,
        with replacement: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return value
        }

        let range = NSRange(value.startIndex..., in: value)
        return regex.stringByReplacingMatches(
            in: value,
            range: range,
            withTemplate: replacement
        )
    }

    private static func predictionURLs(for date: Date) -> [URL] {
        let iso = dateString(for: date, format: "yyyy-MM-dd")
        let compact = dateString(for: date, format: "yyyyMMdd")
        let values = [iso, compact]

        var urls: [URL] = values.compactMap { value in
            guard var components = URLComponents(
                url: predictionsURL,
                resolvingAgainstBaseURL: false
            ) else {
                return nil
            }

            components.queryItems = [
                URLQueryItem(name: "date", value: value)
            ]
            return components.url
        }
        urls.append(predictionsURL)
        return urls
    }

    private static func dateString(
        for date: Date,
        format: String
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private static let fullTeamNames: [String: String] = [
        "ANA": "Anaheim Ducks",
        "BOS": "Boston Bruins",
        "BUF": "Buffalo Sabres",
        "CAR": "Carolina Hurricanes",
        "CBJ": "Columbus Blue Jackets",
        "CGY": "Calgary Flames",
        "CHI": "Chicago Blackhawks",
        "COL": "Colorado Avalanche",
        "DAL": "Dallas Stars",
        "DET": "Detroit Red Wings",
        "EDM": "Edmonton Oilers",
        "FLA": "Florida Panthers",
        "LAK": "Los Angeles Kings",
        "MIN": "Minnesota Wild",
        "MTL": "Montreal Canadiens",
        "NJD": "New Jersey Devils",
        "NSH": "Nashville Predators",
        "NYI": "New York Islanders",
        "NYR": "New York Rangers",
        "OTT": "Ottawa Senators",
        "PHI": "Philadelphia Flyers",
        "PIT": "Pittsburgh Penguins",
        "SEA": "Seattle Kraken",
        "SJS": "San Jose Sharks",
        "STL": "St. Louis Blues",
        "TBL": "Tampa Bay Lightning",
        "TOR": "Toronto Maple Leafs",
        "UTA": "Utah Mammoth",
        "VAN": "Vancouver Canucks",
        "VGK": "Vegas Golden Knights",
        "WPG": "Winnipeg Jets",
        "WSH": "Washington Capitals"
    ]
}
