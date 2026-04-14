import Foundation

public actor GTFSUpdateService {
    private let fgcRemoteURL: URL
    private let fgcLocalZipURL: URL
    private let tmbRemoteURL: URL
    private let tmbLocalZipURL: URL
    private let updateInterval: TimeInterval

    public init(
        remoteURL: URL = Constants.fgcStaticGTFSURL,
        localZipURL: URL? = nil,
        tmbRemoteURL: URL = Constants.tmbStaticGTFSURL,
        tmbLocalZipURL: URL? = nil,
        updateInterval: TimeInterval = Constants.gtfsUpdateInterval
    ) {
        fgcRemoteURL = remoteURL
        fgcLocalZipURL = localZipURL ?? Self.defaultLocalZipURL()
        self.tmbRemoteURL = tmbRemoteURL
        self.tmbLocalZipURL = tmbLocalZipURL ?? Self.defaultTMBLocalZipURL()
        self.updateInterval = updateInterval
    }

    /// Returns the best available GTFS ZIP URL: downloaded version if present, otherwise the bundled fallback.
    /// This is nonisolated because `fgcLocalZipURL` is immutable.
    nonisolated public func bestAvailableZipURL(bundledURL: URL) -> URL {
        FileManager.default.fileExists(atPath: fgcLocalZipURL.path) ? fgcLocalZipURL : bundledURL
    }

    /// Returns the downloaded TMB GTFS ZIP URL if it exists.
    nonisolated public func bestAvailableTMBZipURL() -> URL? {
        guard FileManager.default.fileExists(atPath: tmbLocalZipURL.path) else {
            return nil
        }
        return tmbLocalZipURL
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
            try await downloadZip(from: fgcRemoteURL, to: fgcLocalZipURL)
            UserSettings.setGTFSLastFetched(Date())
            return true
        } catch {
            return false
        }
    }

    /// Downloads a fresh TMB GTFS ZIP if stale, trying credentials in order.
    /// Returns `true` if new data was downloaded.
    @discardableResult
    public func refreshTMBIfStale(credentials: [TMBCredentials]) async -> Bool {
        let lastFetch = UserSettings.tmbGTFSLastFetched()
        if let lastFetch, Date().timeIntervalSince(lastFetch) < updateInterval {
            return false
        }

        guard !credentials.isEmpty else {
            return false
        }

        for credential in credentials {
            guard let request = makeTMBRequest(credentials: credential) else {
                continue
            }

            do {
                let (tempURL, response) = try await URLSession.shared.download(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    try? FileManager.default.removeItem(at: tempURL)
                    return false
                }

                if httpResponse.statusCode == 200 {
                    try storeDownloadedZip(tempURL: tempURL, targetURL: tmbLocalZipURL)
                    UserSettings.setTMBGTFSLastFetched(Date())
                    return true
                }

                try? FileManager.default.removeItem(at: tempURL)
                if [401, 403, 429].contains(httpResponse.statusCode) {
                    continue
                }
                return false
            } catch {
                return false
            }
        }

        return false
    }

    private static func defaultLocalZipURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Ping", isDirectory: true)
            .appendingPathComponent("google_transit.zip")
    }

    private static func defaultTMBLocalZipURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Ping", isDirectory: true)
            .appendingPathComponent("tmb_gtfs.zip")
    }

    private func downloadZip(from remoteURL: URL, to localZipURL: URL) async throws {
        let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            try? FileManager.default.removeItem(at: tempURL)
            throw URLError(.badServerResponse)
        }

        try storeDownloadedZip(tempURL: tempURL, targetURL: localZipURL)
    }

    private func storeDownloadedZip(tempURL: URL, targetURL: URL) throws {
        let fileManager = FileManager.default
        let directory = targetURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }

        try fileManager.moveItem(at: tempURL, to: targetURL)
    }

    private func makeTMBRequest(credentials: TMBCredentials) -> URLRequest? {
        guard var components = URLComponents(url: tmbRemoteURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "app_id", value: credentials.appID),
            URLQueryItem(name: "app_key", value: credentials.appKey),
        ]
        guard let url = components.url else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/zip", forHTTPHeaderField: "Accept")
        return request
    }
}
