import Foundation

public actor GTFSUpdateService {
    private let remoteURL: URL
    private let localZipURL: URL
    private let updateInterval: TimeInterval

    public init(
        remoteURL: URL = Constants.fgcStaticGTFSURL,
        localZipURL: URL? = nil,
        updateInterval: TimeInterval = Constants.gtfsUpdateInterval
    ) {
        self.remoteURL = remoteURL
        self.localZipURL = localZipURL ?? Self.defaultLocalZipURL()
        self.updateInterval = updateInterval
    }

    /// Returns the best available GTFS ZIP URL: downloaded version if present, otherwise the bundled fallback.
    /// This is nonisolated because `localZipURL` is immutable.
    nonisolated public func bestAvailableZipURL(bundledURL: URL) -> URL {
        FileManager.default.fileExists(atPath: localZipURL.path) ? localZipURL : bundledURL
    }

    /// Downloads a fresh GTFS ZIP if the update interval has elapsed since the last fetch.
    /// Returns `true` if new data was downloaded.
    @discardableResult
    public func updateIfNeeded() async -> Bool {
        let lastFetch = UserSettings.gtfsLastFetched()
        if let lastFetch, Date().timeIntervalSince(lastFetch) < updateInterval {
            return false
        }

        do {
            let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }

            let fileManager = FileManager.default
            let directory = localZipURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }

            if fileManager.fileExists(atPath: localZipURL.path) {
                try fileManager.removeItem(at: localZipURL)
            }
            try fileManager.moveItem(at: tempURL, to: localZipURL)

            UserSettings.setGTFSLastFetched(Date())
            return true
        } catch {
            return false
        }
    }

    private static func defaultLocalZipURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Ping", isDirectory: true)
            .appendingPathComponent("google_transit.zip")
    }
}
