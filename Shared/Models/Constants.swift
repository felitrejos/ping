import Foundation

public enum Constants {
    public static let bundledStaticGTFSName = "google_transit"
    public static let bundledStaticGTFSExtension = "zip"

    public static let fgcStaticGTFSURL = URL(
        string: "https://www.fgc.cat/google/google_transit.zip"
    )!

    // FGC exposes the realtime protobuf file through a stable records endpoint.
    public static let fgcRealtimeFeedURL = URL(
        string: "https://dadesobertes.fgc.cat/api/explore/v2.1/catalog/datasets/trip-updates-gtfs_realtime/records?limit=1"
    )!

    public static let fgcServiceAlertsFeedURL = URL(
        string: "https://dadesobertes.fgc.cat/api/explore/v2.1/catalog/datasets/alerts-gtfs_realtime/records?limit=1"
    )!

    public static let tmbStaticGTFSURL = URL(
        string: "https://api.tmb.cat/v1/static/datasets/gtfs.zip"
    )!

    public static let tmbIBusStopsBaseURL = URL(
        string: "https://api.tmb.cat/v1/ibus/stops"
    )!

    public static let tmbInfoPlistPrimaryAppIDKey = "TMB_APP_ID_PRIMARY"
    public static let tmbInfoPlistPrimaryAppKeyKey = "TMB_APP_KEY_PRIMARY"
    public static let tmbInfoPlistBackupAppIDKey = "TMB_APP_ID_BACKUP"
    public static let tmbInfoPlistBackupAppKeyKey = "TMB_APP_KEY_BACKUP"

    /// How often to check for a new GTFS static ZIP (seconds). Default: weekly.
    public static let gtfsUpdateInterval: TimeInterval = 7 * 24 * 60 * 60
}
