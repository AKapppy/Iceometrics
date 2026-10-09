
import Foundation

nonisolated struct ModelsSnapshot: Sendable {
    let generatedAt: Date
    let season: String
    let teams: [ModelTeam]
    let playoffPicture: ModelPlayoffPicture?
    let magicTragic: ModelMagicTragic?
    let pointProbabilities: ModelPointProbabilities?
    let playoffWinProbabilities: ModelPlayoffWinProbabilities?

    var hasData: Bool {
        playoffPicture != nil
            || magicTragic != nil
            || pointProbabilities != nil
            || playoffWinProbabilities != nil
    }

    func team(_ code: String) -> ModelTeam? {
        teams.first {
            $0.code.caseInsensitiveCompare(code) == .orderedSame
        }
    }
}

nonisolated struct ModelTeam: Identifiable, Hashable, Sendable {
    let code: String
    let name: String
    let logoURL: URL?
    let colorHex: String

    var id: String { code }
}

nonisolated struct ModelPlayoffPicture: Sendable {
    let day: String
    let seedDay: String
    let mode: String
    let west: ModelBracket
    let east: ModelBracket
    let cupFinal: [String]
    let champion: String
}

nonisolated struct ModelBracket: Sendable {
    let round1: [[String]]
    let round2: [[String]]
    let finalMatchup: [String]
    let champion: String
}

nonisolated struct ModelMagicTragic: Sendable {
    let day: String
    let gamesPerTeam: Int
    let conferences: [ModelMagicTragicConference]
}

nonisolated struct ModelMagicTragicConference: Identifiable, Sendable {
    let name: String
    let columns: [String]
    let rows: [ModelMagicTragicRow]

    var id: String { name }
}

nonisolated struct ModelMagicTragicRow: Identifiable, Sendable {
    let team: String
    let points: Double
    let gamesPlayed: Int
    let gamesRemaining: Int
    let magic: [String]
    let tragic: [String]

    var id: String { team }
}

nonisolated struct ModelPointProbabilities: Sendable {
    let day: String
    let values: [Int]
    let rows: [ModelPointProbabilityRow]
}

nonisolated struct ModelPointProbabilityRow: Identifiable, Sendable {
    let team: String
    let prediction: Int
    let probabilities: [Double]

    var id: String { team }
}

nonisolated struct ModelPlayoffWinProbabilities: Sendable {
    let day: String
    let seedDay: String
    let rounds: [ModelWinRound]
}

nonisolated struct ModelWinRound: Identifiable, Sendable {
    let title: String
    let series: [ModelSeriesProbability]

    var id: String { title }
}

nonisolated struct ModelSeriesProbability: Identifiable, Sendable {
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

    var id: String {
        "\(a)|\(b)|\(prediction)"
    }
}
