import Foundation
import Testing
@testable import PingShared

struct UserSettingsTests {
    @Test
    func legacyDefaultRouteMigrationClearsOnlyOldPresetStations() {
        let suiteName = "UserSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set("VO", forKey: UserSettings.Keys.homeStationID)
        defaults.set("SR", forKey: UserSettings.Keys.destinationStationID)

        UserSettings.migrateLegacyDefaultRouteIfNeeded(defaults: defaults)

        #expect(UserSettings.homeStationID(defaults: defaults) == nil)
        #expect(UserSettings.destinationStationID(defaults: defaults) == nil)
    }

    @Test
    func legacyDefaultRouteMigrationKeepsUserSelectedStations() {
        let suiteName = "UserSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set("PC", forKey: UserSettings.Keys.homeStationID)
        defaults.set("SC", forKey: UserSettings.Keys.destinationStationID)

        UserSettings.migrateLegacyDefaultRouteIfNeeded(defaults: defaults)

        #expect(UserSettings.homeStationID(defaults: defaults) == "PC")
        #expect(UserSettings.destinationStationID(defaults: defaults) == "SC")
    }

    @Test
    func favoriteStationsPersistenceDeduplicatesAndSkipsInvalidValues() {
        let suiteName = "UserSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        UserSettings.setFavoriteStationIDs(["VO", "", "SR", "VO"], defaults: defaults)

        #expect(UserSettings.favoriteStationIDs(defaults: defaults) == ["VO", "SR"])
    }

    @Test
    func tmbToggleDefaultsToEnabledAndPersists() {
        let suiteName = "UserSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        #expect(UserSettings.tmbEnabled(defaults: defaults))

        UserSettings.setTMBEnabled(false, defaults: defaults)
        #expect(!UserSettings.tmbEnabled(defaults: defaults))
    }

}
