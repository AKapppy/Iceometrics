import Foundation

nonisolated struct Team: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let abbreviation: String
    let name: String
    let logoURL: URL?
    let league: String?

    init(
        id: String,
        abbreviation: String,
        name: String,
        logoURL: URL?,
        league: String? = nil
    ) {
        self.id = id
        self.abbreviation = abbreviation
        self.name = name
        self.logoURL = logoURL
        self.league = league
    }

    var leagueCode: String {
        league?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .nilIfEmpty
            ?? "NHL"
    }
}

private nonisolated extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
