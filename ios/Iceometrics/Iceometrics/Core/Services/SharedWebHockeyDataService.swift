import Foundation

nonisolated struct SharedWebHockeyDataService: HockeyDataService {
    private let client: APIClient
    private let baseURL: URL
    private let season: String
    private let exportStore: SharedSeasonExportDataStore

    init(
        client: APIClient = APIClient(),
        baseURL: URL,
        season: String,
        exportStore: SharedSeasonExportDataStore = .shared
    ) {
        self.client = client
        self.baseURL = baseURL
        self.season = season
        self.exportStore = exportStore
    }

    func fetchSnapshot() async throws -> AppSnapshot {
        let data = try await exportStore.freshData(
            baseURL: baseURL,
            season: season,
            client: client,
            forceRefresh: true
        )

        let payload: SharedWebExport
        do {
            payload = try IceometicsJSON.decoder.decode(
                SharedWebExport.self,
                from: data
            )
        } catch {
            throw IceometicsError.decoding(error.localizedDescription)
        }

        return SharedWebSnapshotAdapter.makeSnapshot(
            from: payload,
            baseURL: baseURL
        )
    }
}

nonisolated struct SharedWebExport: Decodable, Sendable {
    let metadata: SharedWebMetadata
    let teamRegistry: [SharedWebTeamRegistryEntry]?
    let desktop: SharedWebDesktop
}

nonisolated struct SharedWebMetadata: Decodable, Sendable {
    let season: String
    let generatedAt: Date
    let source: String
}

nonisolated struct SharedWebTeamRegistryEntry: Decodable, Sendable {
    let league: String
    let code: String
    let name: String
    let assetCode: String?
    let logo: String?
}

nonisolated struct SharedWebDesktop: Decodable, Sendable {
    let scoreboard: SharedWebScoreboard
}

nonisolated struct SharedWebScoreboard: Decodable, Sendable {
    let days: [String: [SharedWebGame]]
}

nonisolated struct SharedWebGameID: Decodable, Sendable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(String.self) {
            self.value = value
        } else if let value = try? container.decode(Int.self) {
            self.value = String(value)
        } else {
            self.value = ""
        }
    }
}

nonisolated struct SharedWebGame: Decodable, Sendable {
    let id: SharedWebGameID
    let league: String
    let gameTypeId: Int?
    let state: String
    let status: String
    let startUtc: String
    let clock: SharedWebClock?
    let periodDescriptor: SharedWebPeriodDescriptor?
    let venue: SharedWebVenue?
    let away: SharedWebTeam
    let home: SharedWebTeam
}

nonisolated struct SharedWebClock: Decodable, Sendable {
    let timeRemaining: String?
    let inIntermission: Bool?
}

nonisolated struct SharedWebPeriodDescriptor: Decodable, Sendable {
    let number: Int?
    let periodType: String?
}

nonisolated struct SharedWebTeam: Decodable, Sendable {
    let code: String
    let name: String
    let score: Int?
    let shots: Int?
}

nonisolated struct SharedWebVenue: Decodable, Sendable {
    let name: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            name = nil
            return
        }

        if let value = try? container.decode(String.self) {
            name = value.isEmpty ? nil : value
            return
        }

        if let value = try? container.decode([String: String].self) {
            let candidate = value["default"] ?? value["name"]
            name = candidate?.isEmpty == false ? candidate : nil
            return
        }

        name = nil
    }
}

nonisolated enum SharedWebSnapshotAdapter {
    static func makeSnapshot(
        from payload: SharedWebExport,
        baseURL: URL
    ) -> AppSnapshot {
        let registry = Dictionary(
            uniqueKeysWithValues: (payload.teamRegistry ?? []).map {
                (registryKey(league: $0.league, code: $0.code), $0)
            }
        )

        let games = payload.desktop.scoreboard.days
            .sorted { $0.key < $1.key }
            .flatMap { day, rows in
                rows
                    .filter {
                        ["NHL", "PWHL"].contains($0.league.uppercased())
                    }
                    .compactMap {
                        makeGame(
                            from: $0,
                            day: day,
                            registry: registry,
                            baseURL: baseURL
                        )
                    }
            }
            .sorted { $0.startTime < $1.startTime }

        return AppSnapshot(
            generatedAt: payload.metadata.generatedAt,
            source: "Shared \(payload.metadata.season) snapshot • \(payload.metadata.source)",
            games: games,
            standings: []
        )
    }

    private static func makeGame(
        from game: SharedWebGame,
        day: String,
        registry: [String: SharedWebTeamRegistryEntry],
        baseURL: URL
    ) -> HockeyGame? {
        let league = game.league.uppercased()
        guard let startTime = parseDate(game.startUtc)
            ?? parseFallbackDate(day: day, status: game.status) else {
            return nil
        }

        let awayCode = game.away.code.uppercased()
        let homeCode = game.home.code.uppercased()

        guard !awayCode.isEmpty, !homeCode.isEmpty else {
            return nil
        }

        let rawID = game.id.value.isEmpty
            ? "\(awayCode)-\(homeCode)-\(day)"
            : game.id.value

        let id = league == "NHL"
            ? rawID
            : "\(league)-\(rawID)"

        return HockeyGame(
            id: id,
            startTime: startTime,
            status: status(for: game),
            awayTeam: makeTeam(
                code: awayCode,
                name: game.away.name,
                league: league,
                registry: registry,
                baseURL: baseURL
            ),
            homeTeam: makeTeam(
                code: homeCode,
                name: game.home.name,
                league: league,
                registry: registry,
                baseURL: baseURL
            ),
            awayScore: game.away.score,
            homeScore: game.home.score,
            venue: game.venue?.name,
            gameTypeId: game.gameTypeId,
            awayShots: game.away.shots,
            homeShots: game.home.shots,
            periodNumber: game.periodDescriptor?.number,
            periodType: game.periodDescriptor?.periodType,
            timeRemaining: game.clock?.timeRemaining,
            isIntermission: game.clock?.inIntermission,
            league: league
        )
    }

    private static func makeTeam(
        code: String,
        name: String,
        league: String,
        registry: [String: SharedWebTeamRegistryEntry],
        baseURL: URL
    ) -> Team {
        let entry = registry[registryKey(league: league, code: code)]
        let displayName = name.isEmpty
            ? (entry?.name ?? code)
            : name

        let logoURL: URL?
        if let logo = entry?.logo, !logo.isEmpty {
            logoURL = URL(string: logo, relativeTo: baseURL)?.absoluteURL
        } else if league == "NHL" {
            logoURL = baseURL
                .appendingPathComponent("assets")
                .appendingPathComponent("nhl_logos")
                .appendingPathComponent("\(code).png")
        } else {
            logoURL = nil
        }

        let id = league == "NHL"
            ? code.lowercased()
            : "\(league.lowercased())-\(code.lowercased())"

        return Team(
            id: id,
            abbreviation: code,
            name: displayName,
            logoURL: logoURL,
            league: league
        )
    }

    private static func registryKey(
        league: String,
        code: String
    ) -> String {
        "\(league.uppercased()):\(code.uppercased())"
    }

    private static func status(for game: SharedWebGame) -> GameStatus {
        switch game.state.uppercased() {
        case "FUT", "PRE":
            return .scheduled
        case "LIVE", "CRIT":
            return .live
        case "FINAL", "OFF":
            return .final
        case "POSTPONED", "PPD":
            return .postponed
        default:
            let status = game.status.lowercased()
            if status.contains("postpon") {
                return .postponed
            }
            if status.contains("final") {
                return .final
            }
            return .unknown
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        return formatter.date(from: value)
    }

    private static func parseFallbackDate(
        day: String,
        status: String
    ) -> Date? {
        let status = status
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !status.isEmpty {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = "yyyy-MM-dd h:mm a zzz"

            if let date = formatter.date(from: "\(day) \(status)") {
                return date
            }
        }

        let pieces = day.split(separator: "-")
        guard pieces.count == 3,
              let year = Int(pieces[0]),
              let month = Int(pieces[1]),
              let day = Int(pieces[2]) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current

        return calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: 12
            )
        )
    }
}
