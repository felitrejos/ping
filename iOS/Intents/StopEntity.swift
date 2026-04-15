import AppIntents
import Foundation

struct StopEntity: AppEntity, Identifiable, Hashable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Station")
    static let defaultQuery = StopEntityQuery()

    let id: StopID
    let name: String

    init(id: StopID, name: String) {
        self.id = id
        self.name = name
    }

    init(stop: Stop) {
        id = stop.id
        name = stop.name
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(id)"
        )
    }
}

struct StopEntityQuery: EntityStringQuery {
    func entities(for identifiers: [StopEntity.ID]) async throws -> [StopEntity] {
        let container = await PingIntentSupport.container()
        let allStops = try await container.staticService.allStops()
        let requestedIDs = Set(identifiers)
        return allStops
            .filter { requestedIDs.contains($0.id) }
            .map(StopEntity.init(stop:))
    }

    func suggestedEntities() async throws -> [StopEntity] {
        let container = await PingIntentSupport.container()
        let allStops = try await container.staticService.allStops()
        return allStops.prefix(25).map(StopEntity.init(stop:))
    }

    func defaultResult() async -> StopEntity? {
        guard let homeID = UserSettings.homeStationID() else {
            return nil
        }
        let container = await PingIntentSupport.container()
        let allStops = (try? await container.staticService.allStops()) ?? []
        guard let stop = allStops.first(where: { $0.id == homeID }) else {
            return nil
        }
        return StopEntity(stop: stop)
    }

    func entities(matching string: String) async throws -> [StopEntity] {
        let container = await PingIntentSupport.container()
        let stops = try await container.staticService.searchStops(matching: string)
        return stops.prefix(25).map(StopEntity.init(stop:))
    }
}
