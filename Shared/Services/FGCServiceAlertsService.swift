import Foundation
import SwiftProtobuf

public struct FGCServiceAlertsService: ServiceAlertsProviding {
    private struct FeedEnvelope: Decodable {
        struct Result: Decodable {
            struct FileReference: Decodable {
                let url: URL
            }

            let file: FileReference
        }

        let results: [Result]
    }

    private let feedURL: URL
    private let session: URLSession

    public init(
        feedURL: URL = Constants.fgcServiceAlertsFeedURL,
        session: URLSession = .shared
    ) {
        self.feedURL = feedURL
        self.session = session
    }

    public func fetchAlerts() async throws -> [ServiceAlert] {
        let feedData = try await fetchFeedData()
        let feed = try TransitRealtime_FeedMessage(serializedBytes: feedData)
        return buildAlerts(from: feed)
    }
}

// MARK: - Feed decoding
extension FGCServiceAlertsService {
    private func fetchFeedData() async throws -> Data {
        let (data, response) = try await session.data(from: feedURL)
        let contentType = (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Type")?
            .lowercased() ?? ""

        if contentType.contains("application/json") || feedURL.absoluteString.contains("/records") {
            let envelope = try JSONDecoder().decode(FeedEnvelope.self, from: data)
            guard let fileURL = envelope.results.first?.file.url else {
                throw RealtimeServiceError.missingFileReference
            }
            let (protobufData, _) = try await session.data(from: fileURL)
            return protobufData
        }

        return data
    }

    private func buildAlerts(from feed: TransitRealtime_FeedMessage) -> [ServiceAlert] {
        let alerts = feed.entity.compactMap { entity -> ServiceAlert? in
            guard entity.hasAlert else {
                return nil
            }

            let alert = entity.alert
            let title = translatedText(from: alert.headerText)
            guard !title.isEmpty else {
                return nil
            }

            let affectedLines = Array(
                Set(
                    alert.informedEntity.compactMap { informed in
                        let routeID = informed.routeID.trimmingCharacters(in: .whitespacesAndNewlines)
                        return routeID.isEmpty ? nil : routeID
                    }
                )
            )
            .sorted()

            let activePeriod = alert.activePeriod.first
            let startDate: Date? = activePeriod?.hasStart == true ? Date(timeIntervalSince1970: TimeInterval(activePeriod?.start ?? 0)) : nil
            let endDate: Date? = activePeriod?.hasEnd == true ? Date(timeIntervalSince1970: TimeInterval(activePeriod?.end ?? 0)) : nil

            return ServiceAlert(
                id: entity.id.isEmpty ? UUID().uuidString : entity.id,
                title: title,
                details: translatedText(from: alert.descriptionText),
                affectedLines: affectedLines,
                severity: severity(for: alert),
                startDate: startDate,
                endDate: endDate
            )
        }

        return alerts.sorted { first, second in
            if first.severity != second.severity {
                return severityRank(first.severity) > severityRank(second.severity)
            }
            return first.title.localizedStandardCompare(second.title) == .orderedAscending
        }
    }

    private func translatedText(from translated: TransitRealtime_TranslatedString) -> String {
        let value = translated.translation.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "" : value
    }

    private func severity(for alert: TransitRealtime_Alert) -> ServiceAlertSeverity {
        let text = String(describing: alert.effect).lowercased()
        if text.contains("no") && text.contains("service") {
            return .closure
        }
        if text.contains("detour") || text.contains("significant") {
            return .major
        }
        if text.contains("reduced") || text.contains("modified") || text.contains("stopmoved") {
            return .minor
        }
        return .info
    }

    private func severityRank(_ severity: ServiceAlertSeverity) -> Int {
        switch severity {
        case .closure:
            return 4
        case .major:
            return 3
        case .minor:
            return 2
        case .info:
            return 1
        }
    }
}
