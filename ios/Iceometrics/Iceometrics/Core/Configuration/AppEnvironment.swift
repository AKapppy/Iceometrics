import Foundation

nonisolated enum AppEnvironment {
    static func makeRepository(season requestedSeason: String? = nil) -> any HockeyRepositoryProtocol {
        let cache = CacheStore(
            filename: requestedSeason.map { "iceometrics-shared-scoreboard-\($0).json" }
                ?? AppConfiguration.cacheFilename
        )

        switch AppConfiguration.dataMode {
        case .fixture:
            return HockeyRepository(
                service: FixtureHockeyDataService(),
                cache: cache,
                successfulFetchOrigin: .fixture
            )

        case .sharedWebSnapshot(let baseURL, let season):
            return HockeyRepository(
                service: SharedWebHockeyDataService(
                    baseURL: baseURL,
                    season: requestedSeason ?? season
                ),
                cache: cache,
                successfulFetchOrigin: .network
            )

        case .live(let baseURL):
            return HockeyRepository(
                service: LiveHockeyDataService(
                    baseURL: baseURL,
                    snapshotPath: AppConfiguration.liveSnapshotPath
                ),
                cache: cache,
                successfulFetchOrigin: .network
            )
        }
    }
}
