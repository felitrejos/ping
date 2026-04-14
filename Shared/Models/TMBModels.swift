import Foundation

public struct TMBStop: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let code: String?
    public let name: String
    public let coordinate: TransitCoordinate
    public let routeShortNames: [String]

    public init(
        id: String,
        code: String?,
        name: String,
        coordinate: TransitCoordinate,
        routeShortNames: [String]
    ) {
        self.id = id
        self.code = code
        self.name = name
        self.coordinate = coordinate
        self.routeShortNames = routeShortNames
    }
}

public struct TMBArrival: Equatable, Sendable {
    public let routeShortName: String
    public let destination: String
    public let arrivalDate: Date
    public let minutesAway: Int
    public let isRealtime: Bool

    public init(
        routeShortName: String,
        destination: String,
        arrivalDate: Date,
        minutesAway: Int,
        isRealtime: Bool
    ) {
        self.routeShortName = routeShortName
        self.destination = destination
        self.arrivalDate = arrivalDate
        self.minutesAway = minutesAway
        self.isRealtime = isRealtime
    }
}

public struct TMBBoundingBox: Equatable, Sendable {
    public let minLatitude: Double
    public let maxLatitude: Double
    public let minLongitude: Double
    public let maxLongitude: Double

    public init(
        minLatitude: Double,
        maxLatitude: Double,
        minLongitude: Double,
        maxLongitude: Double
    ) {
        self.minLatitude = min(minLatitude, maxLatitude)
        self.maxLatitude = max(minLatitude, maxLatitude)
        self.minLongitude = min(minLongitude, maxLongitude)
        self.maxLongitude = max(minLongitude, maxLongitude)
    }

    public func contains(_ coordinate: TransitCoordinate) -> Bool {
        coordinate.latitude >= minLatitude
            && coordinate.latitude <= maxLatitude
            && coordinate.longitude >= minLongitude
            && coordinate.longitude <= maxLongitude
    }
}
