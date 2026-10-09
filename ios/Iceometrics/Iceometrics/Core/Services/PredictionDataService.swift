import Foundation

actor PredictionDataService {
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

    func cachedSnapshot() async -> PredictionSnapshot? {
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
    ) async throws -> PredictionSnapshot {
        let data = try await exportStore.freshData(
            baseURL: baseURL,
            season: season,
            client: client,
            forceRefresh: forceRefresh
        )

        return try decode(data)
    }

    private func decode(_ data: Data) throws -> PredictionSnapshot {
        do {
            let export = try IceometicsJSON.decoder.decode(
                PredictionExport.self,
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

private nonisolated struct PredictionExport: Decodable, Sendable {
    let metadata: Metadata
    let metrics: [Metric]
    let teams: [TeamRow]
    let tables: [String: Table]

    nonisolated struct Metadata: Decodable, Sendable {
        let season: String
        let generatedAt: Date
        let predictions: PredictionStatus?
    }

    nonisolated struct PredictionStatus: Decodable, Sendable {
        let status: String?
        let error: String?
    }

    nonisolated struct Metric: Decodable, Sendable {
        let key: String
        let label: String
        let title: String
    }

    nonisolated struct TeamRow: Decodable, Sendable {
        let code: String
        let name: String
        let division: String?
        let conference: String?
        let logo: String?
        let color: String?
        let sortValue: Double?
    }

    nonisolated struct Table: Decodable, Sendable {
        let columns: [String]
        let rows: [String: [Double?]]
    }

    func makeSnapshot(
        baseURL: URL,
        fallbackSeason: String
    ) -> PredictionSnapshot {
        let mappedMetrics = metrics.map {
            PredictionMetric(
                key: $0.key,
                label: $0.label,
                title: $0.title
            )
        }

        let mappedTeams = teams.map { team in
            PredictionTeam(
                code: team.code,
                name: team.name,
                division: team.division ?? "",
                conference: team.conference ?? "",
                logoURL: team.logo.flatMap {
                    URL(string: $0, relativeTo: baseURL)?.absoluteURL
                },
                colorHex: team.color ?? "",
                sortValue: team.sortValue ?? 0
            )
        }

        let mappedTables = tables.mapValues {
            PredictionTable(
                columns: $0.columns,
                rows: $0.rows
            )
        }

        return PredictionSnapshot(
            generatedAt: metadata.generatedAt,
            season: metadata.season.isEmpty ? fallbackSeason : metadata.season,
            status: metadata.predictions?.status ?? "unknown",
            errorMessage: metadata.predictions?.error,
            metrics: mappedMetrics,
            teams: mappedTeams,
            tables: mappedTables,
            cupURL: URL(string: "assets/stanley_cup.png", relativeTo: baseURL)?.absoluteURL
        )
    }
}
