import Foundation

public enum Constants {
    public static let bundledStaticGTFSName = "google_transit"
    public static let bundledStaticGTFSExtension = "zip"

    public static let homeStopID: StopID = UserSettings.defaultHomeStationID
    public static let destinationStopIDs: [StopID] = UserSettings.defaultDestinationStopIDs

    // FGC exposes the realtime protobuf file through a stable records endpoint.
    public static let fgcRealtimeFeedURL = URL(
        string: "https://dadesobertes.fgc.cat/api/explore/v2.1/catalog/datasets/trip-updates-gtfs_realtime/records?limit=1"
    )!
}
