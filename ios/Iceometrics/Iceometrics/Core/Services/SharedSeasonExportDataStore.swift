import Foundation

/// One raw copy of the shared season export serves Scoreboard, Stats,
/// Predictions, and Models. Keeping the raw JSON avoids downloading the same
/// multi-feature payload once per tab, while still letting each feature decode
/// only the shape it needs.
actor SharedSeasonExportDataStore {
    static let shared = SharedSeasonExportDataStore()

    private var memoryData: Data?
    private var memoryKey: String?
    private var lastNetworkFetchAt: Date?
    private var inFlightTask: Task<Data, Error>?
    private var inFlightKey: String?

    /// Reuse a just-fetched network payload when several tabs open together.
    private let networkReuseInterval: TimeInterval = 60

    private init() {}

    // Historical season snapshots are bundled with the app to avoid any
    // GitHub publishing requirement. Current-season data stays network-driven.
    private func localHistoricalData(for season: String) -> Data? {
        guard season != "2026-2027", season >= "2019-2020", season <= "2025-2026" else { return nil }
        let file = Bundle.main.url(forResource: season, withExtension: "json")
            ?? Bundle.main.url(forResource: season, withExtension: "json", subdirectory: "SeasonArchives")
        guard let file else { return nil }
        return try? Data(contentsOf: file)
    }

    func cachedData(
        baseURL: URL,
        season: String
    ) -> Data? {
        if let historical = localHistoricalData(for: season) { return historical }
        let key = cacheKey(baseURL: baseURL, season: season)
        if memoryKey == key, let memoryData {
            return memoryData
        }

        let fileURL = cacheFileURL(for: key)
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            return nil
        }

        memoryKey = key
        memoryData = data
        return data
    }

    func freshData(
        baseURL: URL,
        season: String,
        client: APIClient,
        forceRefresh: Bool
    ) async throws -> Data {
        if let historical = localHistoricalData(for: season) { return historical }
        let key = cacheKey(baseURL: baseURL, season: season)

        if !forceRefresh,
           memoryKey == key,
           let memoryData,
           let lastNetworkFetchAt,
           Date().timeIntervalSince(lastNetworkFetchAt) < networkReuseInterval {
            return memoryData
        }

        if !forceRefresh, inFlightKey == key, let inFlightTask {
            return try await inFlightTask.value
        }

        var request = APIRequest(path: "seasons/\(season)/data.json")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.headers["Cache-Control"] = "no-cache, no-store, max-age=0"
        request.headers["Pragma"] = "no-cache"
        request.queryItems = [
            URLQueryItem(
                name: "app_v",
                value: UUID().uuidString
            )
        ]

        let task = Task<Data, Error> {
            try await client.data(request, baseURL: baseURL)
        }

        if !forceRefresh {
            inFlightTask = task
            inFlightKey = key
        }

        do {
            let data = try await task.value
            if !forceRefresh, inFlightKey == key {
                inFlightTask = nil
                inFlightKey = nil
            }
            memoryKey = key
            memoryData = data
            lastNetworkFetchAt = Date()
            persist(data, key: key)
            return data
        } catch {
            if !forceRefresh, inFlightKey == key {
                inFlightTask = nil
                inFlightKey = nil
            }
            throw error
        }
    }

    private func persist(_ data: Data, key: String) {
        let fileURL = cacheFileURL(for: key)
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // This is an acceleration cache. A write failure must never make
            // otherwise-valid network data unusable.
        }
    }

    private func cacheKey(baseURL: URL, season: String) -> String {
        "\(baseURL.absoluteString)|\(season)"
    }

    private func cacheFileURL(for key: String) -> URL {
        let directory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        // Swift's Hashable seed changes between launches, so use a tiny
        // deterministic FNV-1a hash for a stable on-disk cache filename.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }

        return directory
            .appendingPathComponent("SharedSeasonExport", isDirectory: true)
            .appendingPathComponent("\(String(hash, radix: 16)).json")
    }
}
