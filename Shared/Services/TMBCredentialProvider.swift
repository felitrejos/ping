import Foundation

public struct TMBCredentials: Sendable, Equatable {
    public let appID: String
    public let appKey: String

    public init(appID: String, appKey: String) {
        self.appID = appID
        self.appKey = appKey
    }
}

public struct TMBCredentialProvider: Sendable {
    private let primaryCredentials: TMBCredentials?
    private let backupCredentials: TMBCredentials?

    public init(bundle: Bundle = .main) {
        primaryCredentials = Self.readCredentials(
            appIDKey: Constants.tmbInfoPlistPrimaryAppIDKey,
            appKeyKey: Constants.tmbInfoPlistPrimaryAppKeyKey,
            bundle: bundle
        )
        backupCredentials = Self.readCredentials(
            appIDKey: Constants.tmbInfoPlistBackupAppIDKey,
            appKeyKey: Constants.tmbInfoPlistBackupAppKeyKey,
            bundle: bundle
        )
    }

    public init(primary: TMBCredentials?, backup: TMBCredentials?) {
        primaryCredentials = primary
        backupCredentials = backup
    }

    public var primary: TMBCredentials? {
        primaryCredentials
    }

    public var backup: TMBCredentials? {
        backupCredentials
    }

    public var ordered: [TMBCredentials] {
        [primaryCredentials, backupCredentials].compactMap { $0 }
    }

    public var hasAny: Bool {
        !ordered.isEmpty
    }

    private static func readCredentials(
        appIDKey: String,
        appKeyKey: String,
        bundle: Bundle
    ) -> TMBCredentials? {
        guard
            let appID = normalized(bundle.object(forInfoDictionaryKey: appIDKey) as? String),
            let appKey = normalized(bundle.object(forInfoDictionaryKey: appKeyKey) as? String)
        else {
            return nil
        }

        return TMBCredentials(appID: appID, appKey: appKey)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
