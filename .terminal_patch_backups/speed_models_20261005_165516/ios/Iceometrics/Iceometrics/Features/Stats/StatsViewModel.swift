import Foundation
import Combine

@MainActor
final class StatsViewModel: ObservableObject {
    @Published private(set) var snapshot: StatsSnapshot?
    @Published private(set) var playerStats: [StatsPhase: PlayerStatsSnapshot] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var loadingPlayerPhases: Set<StatsPhase> = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var playerErrorMessage: String?

    private let service: StatsDataService
    private let playerService: PlayerStatsService
    private let liveUpdates: LiveGameUpdateCenter

    private var baseSnapshot: StatsSnapshot?
    private var hasLoaded = false
    private var cancellables: Set<AnyCancellable> = []

    init(
        service: StatsDataService = StatsDataService(),
        playerService: PlayerStatsService = PlayerStatsService(),
        liveUpdates: LiveGameUpdateCenter = .shared
    ) {
        self.service = service
        self.playerService = playerService
        self.liveUpdates = liveUpdates

        liveUpdates.$games
            .sink { [weak self] games in
                Task { @MainActor in
                    self?.applyLiveGames(games)
                }
            }
            .store(in: &cancellables)
    }

    var updatedText: String {
        guard let generatedAt = snapshot?.generatedAt else {
            return "Not updated yet"
        }

        return "Updated \(generatedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await load()
    }

    func refresh() async {
        playerStats = [:]
        playerErrorMessage = nil
        await load()
    }

    func loadPlayers(
        for phase: StatsPhase,
        force: Bool = false
    ) async {
        guard let snapshot else { return }

        if !force,
           playerStats[phase] != nil
        {
            return
        }

        if loadingPlayerPhases.contains(phase) {
            return
        }

        loadingPlayerPhases.insert(phase)
        playerErrorMessage = nil

        defer {
            loadingPlayerPhases.remove(phase)
        }

        do {
            playerStats[phase] = try await playerService.fetch(
                season: snapshot.season,
                phase: phase
            )
        } catch {
            playerErrorMessage =
                (error as? LocalizedError)?
                    .errorDescription
                ?? error.localizedDescription
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            let loaded = try await service.fetchSnapshot()

            baseSnapshot = loaded
            snapshot = Self.mergedSnapshot(
                loaded,
                with: liveUpdates.games
            )

            await loadPlayers(
                for: snapshot?.defaultPhase
                    ?? loaded.defaultPhase
            )
        } catch {
            errorMessage =
                (error as? LocalizedError)?
                    .errorDescription
                ?? error.localizedDescription
        }
    }

    private func applyLiveGames(
        _ games: [HockeyGame]
    ) {
        guard let baseSnapshot else {
            return
        }

        snapshot = Self.mergedSnapshot(
            baseSnapshot,
            with: games
        )
    }

    private static func mergedSnapshot(
        _ base: StatsSnapshot,
        with liveGames: [HockeyGame]
    ) -> StatsSnapshot {
        guard !liveGames.isEmpty else {
            return base
        }

        let liveByID = Dictionary(
            uniqueKeysWithValues:
                liveGames.map {
                    ($0.id, $0)
                }
        )

        let mergedGames = base.games.map {
            statGame -> StatsGame in

            guard let liveGame =
                    liveByID[statGame.id]
            else {
                return statGame
            }

            return StatsGame(
                id: statGame.id,
                day: statGame.day,
                gameTypeID: statGame.gameTypeID,
                state: statsState(
                    for: liveGame.status,
                    fallback: statGame.state
                ),
                status: liveGame.status.rawValue,
                awayCode: statGame.awayCode,
                homeCode: statGame.homeCode,
                awayScore:
                    liveGame.awayScore
                    ?? statGame.awayScore,
                homeScore:
                    liveGame.homeScore
                    ?? statGame.homeScore,
                periodType:
                    liveGame.periodType
                    ?? statGame.periodType
            )
        }

        return StatsSnapshot(
            generatedAt: base.generatedAt,
            season: base.season,
            teams: base.teams,
            games: mergedGames
        )
    }

    private static func statsState(
        for status: GameStatus,
        fallback: String
    ) -> String {
        switch status {
        case .scheduled:
            return "FUT"
        case .live:
            return "LIVE"
        case .final:
            return "FINAL"
        case .postponed:
            return "PPD"
        case .unknown:
            return fallback
        }
    }
}
