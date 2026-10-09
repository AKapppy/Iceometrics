import Foundation
import Combine

@MainActor
final class LiveGameUpdateCenter: ObservableObject {
    static let shared = LiveGameUpdateCenter()

    @Published private(set) var games: [HockeyGame] = []

    private init() {}

    func publish(_ games: [HockeyGame]) {
        self.games = games
    }
}
