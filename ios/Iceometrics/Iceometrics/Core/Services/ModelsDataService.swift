
import Foundation

actor ModelsDataService {
    private let baseURL: URL
    private let season: String
    private let client: APIClient
    private let exportStore: SharedSeasonExportDataStore

    init(
        baseURL: URL = URL(string: "https://akapppy.github.io/Iceometrics/")!,
        season: String = "2026-2027",
        client: APIClient = APIClient(),
        exportStore: SharedSeasonExportDataStore = .shared
    ) {
        self.baseURL = baseURL
        self.season = season
        self.client = client
        self.exportStore = exportStore
    }

    func cachedSnapshot() async -> ModelsSnapshot? {
        guard let data = await exportStore.cachedData(
            baseURL: baseURL,
            season: season
        ) else {
            return nil
        }

        return try? decode(data)
    }

    func fetchSnapshot(
        forceRefresh: Bool = false
    ) async throws -> ModelsSnapshot {
        let data = try await exportStore.freshData(
            baseURL: baseURL,
            season: season,
            client: client,
            forceRefresh: forceRefresh
        )

        return try decode(data)
    }

    private func decode(_ data: Data) throws -> ModelsSnapshot {
        do {
            let export = try IceometicsJSON.decoder.decode(
                ModelsExportPayload.self,
                from: data
            )

            return export.makeSnapshot(
                baseURL: baseURL,
                fallbackSeason: season
            )
        } catch {
            throw IceometicsError.decoding(error.localizedDescription)
        }
    }
}

private nonisolated struct ModelsExportPayload: Decodable, Sendable {
    let metadata: Metadata
    let teamRegistry: [RegistryTeam]?
    let teams: [ColorTeam]?
    let desktop: Desktop

    nonisolated struct Metadata: Decodable, Sendable {
        let season: String
        let generatedAt: Date
    }

    nonisolated struct RegistryTeam: Decodable, Sendable {
        let league: String
        let code: String
        let name: String
        let logo: String?
    }

    nonisolated struct ColorTeam: Decodable, Sendable {
        let code: String
        let name: String
        let logo: String?
        let color: String?
    }

    nonisolated struct Desktop: Decodable, Sendable {
        let models: Models
    }

    nonisolated struct Models: Decodable, Sendable {
        let playoffPicture: PlayoffPictureHistory?
        let magicTragic: MagicTragicPayload?
        let pointProbabilities: PointProbabilitiesPayload?
        let playoffWinProbabilities: PlayoffWinHistory?
    }

    nonisolated struct PlayoffPictureHistory: Decodable, Sendable {
        let snapshots: [PlayoffPicturePayload?]
    }

    nonisolated struct PlayoffPicturePayload: Decodable, Sendable {
        let day: String
        let seedDay: String
        let mode: String
        let brackets: Brackets
        let cup: Cup
    }

    nonisolated struct Brackets: Decodable, Sendable {
        let west: BracketPayload
        let east: BracketPayload
    }

    nonisolated struct BracketPayload: Decodable, Sendable {
        let round1: [[String]]
        let round2: [[String]]
        let finalMatchup: [String]
        let champion: String

        enum CodingKeys: String, CodingKey {
            case round1
            case round2
            case finalMatchup = "final"
            case champion
        }
    }

    nonisolated struct Cup: Decodable, Sendable {
        let finalTeams: [String]
        let champion: String

        enum CodingKeys: String, CodingKey {
            case finalTeams = "final"
            case champion
        }
    }

    nonisolated struct MagicTragicPayload: Decodable, Sendable {
        let day: String
        let gamesPerTeam: Int
        let conferences: [MagicConferencePayload]
    }

    nonisolated struct MagicConferencePayload: Decodable, Sendable {
        let name: String
        let columns: [String]
        let rows: [MagicRowPayload]
    }

    nonisolated struct MagicRowPayload: Decodable, Sendable {
        let team: String
        let points: Double
        let gamesPlayed: Int
        let gamesRemaining: Int
        let magic: [String]
        let tragic: [String]
    }

    nonisolated struct PointProbabilitiesPayload: Decodable, Sendable {
        let day: String
        let values: [Int]
        let rows: [PointProbabilityRowPayload]
    }

    nonisolated struct PointProbabilityRowPayload: Decodable, Sendable {
        let team: String
        let prediction: Int
        let probabilities: [Double]
    }

    nonisolated struct PlayoffWinHistory: Decodable, Sendable {
        let snapshots: [PlayoffWinPayload?]
    }

    nonisolated struct PlayoffWinPayload: Decodable, Sendable {
        let day: String
        let seedDay: String
        let rounds: [WinRoundPayload]
    }

    nonisolated struct WinRoundPayload: Decodable, Sendable {
        let title: String
        let series: [SeriesPayload]
    }

    nonisolated struct SeriesPayload: Decodable, Sendable {
        let a: String
        let b: String
        let aProbabilities: [Double]
        let bProbabilities: [Double]
        let aWin: Double
        let bWin: Double
        let prediction: String
        let winner: String
        let predictionProbability: Double
        let aWins: Int
        let bWins: Int

        enum CodingKeys: String, CodingKey {
            case a
            case b
            case aProbabilities = "a_probs"
            case bProbabilities = "b_probs"
            case aWin = "a_win"
            case bWin = "b_win"
            case prediction = "pred"
            case winner
            case predictionProbability = "pred_p"
            case aWins = "a_wins"
            case bWins = "b_wins"
        }
    }

    func makeSnapshot(
        baseURL: URL,
        fallbackSeason: String
    ) -> ModelsSnapshot {
        let colorRows = teams ?? []
        let colorByCode = Dictionary(
            uniqueKeysWithValues: colorRows.map {
                ($0.code.uppercased(), $0.color ?? "")
            }
        )
        let colorLogoByCode: [String: String] = Dictionary(
            uniqueKeysWithValues: colorRows.compactMap { row -> (String, String)? in
                guard let logo = row.logo else {
                    return nil
                }

                return (
                    row.code.uppercased(),
                    logo
                )
            }
        )

        let registryRows = (teamRegistry ?? []).filter {
            $0.league.uppercased() == "NHL"
        }

        let mappedTeams: [ModelTeam]
        if !registryRows.isEmpty {
            mappedTeams = registryRows.map { team in
                let code = team.code.uppercased()
                let rawLogo = team.logo
                    ?? colorLogoByCode[code]

                return ModelTeam(
                    code: code,
                    name: team.name,
                    logoURL: rawLogo.flatMap {
                        URL(
                            string: $0,
                            relativeTo: baseURL
                        )?.absoluteURL
                    },
                    colorHex: colorByCode[code] ?? ""
                )
            }
        } else {
            mappedTeams = colorRows.map { team in
                ModelTeam(
                    code: team.code.uppercased(),
                    name: team.name,
                    logoURL: team.logo.flatMap {
                        URL(
                            string: $0,
                            relativeTo: baseURL
                        )?.absoluteURL
                    },
                    colorHex: team.color ?? ""
                )
            }
        }

        let picturePayload = desktop.models.playoffPicture?
            .snapshots
            .compactMap { $0 }
            .max {
                $0.day < $1.day
            }

        let picture = picturePayload.map {
            ModelPlayoffPicture(
                day: $0.day,
                seedDay: $0.seedDay,
                mode: $0.mode,
                west: ModelBracket(
                    round1: $0.brackets.west.round1,
                    round2: $0.brackets.west.round2,
                    finalMatchup: $0.brackets.west.finalMatchup,
                    champion: $0.brackets.west.champion
                ),
                east: ModelBracket(
                    round1: $0.brackets.east.round1,
                    round2: $0.brackets.east.round2,
                    finalMatchup: $0.brackets.east.finalMatchup,
                    champion: $0.brackets.east.champion
                ),
                cupFinal: $0.cup.finalTeams,
                champion: $0.cup.champion
            )
        }

        let magicTragic = desktop.models.magicTragic.map {
            ModelMagicTragic(
                day: $0.day,
                gamesPerTeam: $0.gamesPerTeam,
                conferences: $0.conferences.map { conference in
                    ModelMagicTragicConference(
                        name: conference.name,
                        columns: conference.columns,
                        rows: conference.rows.map { row in
                            ModelMagicTragicRow(
                                team: row.team,
                                points: row.points,
                                gamesPlayed: row.gamesPlayed,
                                gamesRemaining: row.gamesRemaining,
                                magic: row.magic,
                                tragic: row.tragic
                            )
                        }
                    )
                }
            )
        }

        let pointProbabilities = desktop.models.pointProbabilities.map {
            ModelPointProbabilities(
                day: $0.day,
                values: $0.values,
                rows: $0.rows.map { row in
                    ModelPointProbabilityRow(
                        team: row.team,
                        prediction: row.prediction,
                        probabilities: row.probabilities
                    )
                }
            )
        }

        let winPayload = desktop.models.playoffWinProbabilities?
            .snapshots
            .compactMap { $0 }
            .max {
                $0.day < $1.day
            }

        let playoffWinProbabilities = winPayload.map {
            ModelPlayoffWinProbabilities(
                day: $0.day,
                seedDay: $0.seedDay,
                rounds: $0.rounds.map { round in
                    ModelWinRound(
                        title: round.title,
                        series: round.series.map { series in
                            ModelSeriesProbability(
                                a: series.a,
                                b: series.b,
                                aProbabilities: series.aProbabilities,
                                bProbabilities: series.bProbabilities,
                                aWin: series.aWin,
                                bWin: series.bWin,
                                prediction: series.prediction,
                                winner: series.winner,
                                predictionProbability: series.predictionProbability,
                                aWins: series.aWins,
                                bWins: series.bWins
                            )
                        }
                    )
                }
            )
        }

        return ModelsSnapshot(
            generatedAt: metadata.generatedAt,
            season: metadata.season.isEmpty
                ? fallbackSeason
                : metadata.season,
            teams: mappedTeams.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name)
                    == .orderedAscending
            },
            playoffPicture: picture,
            magicTragic: magicTragic,
            pointProbabilities: pointProbabilities,
            playoffWinProbabilities: playoffWinProbabilities
        )
    }
}
