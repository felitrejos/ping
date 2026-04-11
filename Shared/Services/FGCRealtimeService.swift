import Foundation
import SwiftProtobuf

public actor FGCRealtimeService: RealtimeServiceProviding {
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
    private let pollIntervalNanoseconds: UInt64
    private var delaysByTripAndStop: [String: [StopID: Int]] = [:]
    private var continuations: [UUID: AsyncStream<RealtimeSnapshot>.Continuation] = [:]
    private var pollingTask: Task<Void, Never>?

    public init(
        feedURL: URL = Constants.fgcRealtimeFeedURL,
        session: URLSession = .shared,
        pollIntervalNanoseconds: UInt64 = 30_000_000_000
    ) {
        self.feedURL = feedURL
        self.session = session
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
    }

    public func startPolling() async {
        guard pollingTask == nil else {
            return
        }

        pollingTask = Task { [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            }
        }
    }

    public func stopPolling() async {
        pollingTask?.cancel()
        pollingTask = nil
    }

    public func refresh() async {
        do {
            let feedData = try await fetchFeedData()
            let feed = try TransitRealtime_FeedMessage(serializedBytes: feedData)
            delaysByTripAndStop = buildSnapshot(from: feed)
            yieldSnapshot()
        } catch {
            yieldSnapshot()
        }
    }

    public func delayFor(tripID: String, stopID: String) async -> Int? {
        delaysByTripAndStop[tripID]?[stopID]
    }

    public func updates() async -> AsyncStream<RealtimeSnapshot> {
        let identifier = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: RealtimeSnapshot.self)
        continuations[identifier] = continuation
        continuation.yield(RealtimeSnapshot(delaysByTripAndStop: delaysByTripAndStop))
        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removeContinuation(id: identifier)
            }
        }
        return stream
    }
}

// MARK: - Feed decoding
extension FGCRealtimeService {
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

    private func buildSnapshot(from feed: TransitRealtime_FeedMessage) -> [String: [StopID: Int]] {
        var snapshot: [String: [StopID: Int]] = [:]

        for entity in feed.entity {
            guard entity.hasTripUpdate else {
                continue
            }

            let tripUpdate = entity.tripUpdate
            let tripID = tripUpdate.trip.tripID
            guard !tripID.isEmpty else {
                continue
            }

            var stopDelays: [StopID: Int] = [:]
            for stopTimeUpdate in tripUpdate.stopTimeUpdate {
                let stopID = stopTimeUpdate.stopID
                guard !stopID.isEmpty else {
                    continue
                }

                if stopTimeUpdate.hasDeparture {
                    stopDelays[stopID] = Int(stopTimeUpdate.departure.delay)
                } else if stopTimeUpdate.hasArrival {
                    stopDelays[stopID] = Int(stopTimeUpdate.arrival.delay)
                }
            }

            if !stopDelays.isEmpty {
                snapshot[tripID] = stopDelays
            }
        }

        return snapshot
    }

    private func yieldSnapshot() {
        let snapshot = RealtimeSnapshot(delaysByTripAndStop: delaysByTripAndStop)
        continuations.values.forEach { continuation in
            continuation.yield(snapshot)
        }
    }

    private func removeContinuation(id: UUID) {
        continuations[id] = nil
    }
}

public enum RealtimeServiceError: Error, Equatable {
    case missingFileReference
}

public actor MockRealtimeService: RealtimeServiceProviding {
    private var snapshot: RealtimeSnapshot
    private var continuations: [UUID: AsyncStream<RealtimeSnapshot>.Continuation] = [:]

    public init(snapshot: RealtimeSnapshot = RealtimeSnapshot(delaysByTripAndStop: [:])) {
        self.snapshot = snapshot
    }

    public func startPolling() async {}

    public func stopPolling() async {}

    public func refresh() async {
        continuations.values.forEach { continuation in
            continuation.yield(snapshot)
        }
    }

    public func delayFor(tripID: String, stopID: String) async -> Int? {
        snapshot.delaysByTripAndStop[tripID]?[stopID]
    }

    public func updates() async -> AsyncStream<RealtimeSnapshot> {
        let identifier = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: RealtimeSnapshot.self)
        continuations[identifier] = continuation
        continuation.yield(snapshot)
        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removeContinuation(id: identifier)
            }
        }
        return stream
    }

    public func setSnapshot(_ snapshot: RealtimeSnapshot) {
        self.snapshot = snapshot
        continuations.values.forEach { continuation in
            continuation.yield(snapshot)
        }
    }

    private func removeContinuation(id: UUID) {
        continuations[id] = nil
    }
}
