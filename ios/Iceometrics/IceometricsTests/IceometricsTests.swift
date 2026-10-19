//
//  IceometricsTests.swift
//  IceometricsTests
//
//  Created by Andrew Kapetanakis on 9/27/26.
//

import Testing

struct IceometricsTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        // Swift Testing Documentation
        // https://developer.apple.com/documentation/testing
    }

}


import Foundation
@testable import Iceometrics

@MainActor
struct SettingsCloudLocalFallbackTests {
    @Test("Preferences stay local when cloud sync is unavailable")
    func preferencesPersistOffline() {
        let suite = "com.akappy.Iceometrics.test.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            Issue.record("Could not create isolated local defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppSettingsStore(defaults: defaults, syncWithICloud: false)
        first.favoriteTeamID = "NYR"
        first.appearance = .light
        first.accentMode = .custom
        first.customAccentHex = "#1177AA"
        first.showPregamePredictions = false
        first.setCompetitionVisible("PWHL", visible: false)

        let second = AppSettingsStore(defaults: defaults, syncWithICloud: false)
        #expect(second.favoriteTeamID == "NYR")
        #expect(second.appearance == .light)
        #expect(second.accentMode == .custom)
        #expect(second.customAccentHex == "#1177AA")
        #expect(second.showPregamePredictions == false)
        #expect(second.isCompetitionVisible("PWHL") == false)

        second.reset()
        let third = AppSettingsStore(defaults: defaults, syncWithICloud: false)
        #expect(third.favoriteTeamID == nil)
        #expect(third.appearance == .dark)
        #expect(third.isCompetitionVisible("PWHL") == true)
    }
}
