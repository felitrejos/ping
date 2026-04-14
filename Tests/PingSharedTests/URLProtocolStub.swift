import Foundation

enum StubbedResponse {
    case protobuf(Data)
    case jsonRecords(fileURL: URL)
    case http(statusCode: Int, contentType: String, body: Data)

    var body: Data {
        switch self {
        case let .protobuf(data):
            data
        case let .jsonRecords(fileURL):
            """
            {"results":[{"file":{"url":"\(fileURL.absoluteString)"}}]}
            """.data(using: .utf8) ?? Data()
        case let .http(_, _, body):
            body
        }
    }

    var contentType: String {
        switch self {
        case .protobuf:
            "application/octet-stream"
        case .jsonRecords:
            "application/json"
        case let .http(_, contentType, _):
            contentType
        }
    }

    var statusCode: Int {
        switch self {
        case .protobuf, .jsonRecords:
            200
        case let .http(statusCode, _, _):
            statusCode
        }
    }

    var responseBody: Data {
        switch self {
        case .protobuf, .jsonRecords:
            body
        case let .http(_, _, body):
            body
        }
    }
}

final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    fileprivate static let stubIDHeader = "X-URLProtocol-Stub-ID"
    nonisolated(unsafe) private static var responsesByStubID: [String: [URL: StubbedResponse]] = [:]
    private static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard
            let url = request.url,
            let stubID = request.value(forHTTPHeaderField: Self.stubIDHeader),
            let response = Self.response(for: stubID, url: url)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": response.contentType]
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func response(for stubID: String, url: URL) -> StubbedResponse? {
        lock.lock()
        defer { lock.unlock() }
        return responsesByStubID[stubID]?[url]
    }

    fileprivate static func setResponses(_ responses: [URL: StubbedResponse], for stubID: String) {
        lock.lock()
        responsesByStubID[stubID] = responses
        lock.unlock()
    }
}

extension URLSession {
    static func stubbed(with responses: [URL: StubbedResponse]) -> URLSession {
        let stubID = UUID().uuidString
        URLProtocolStub.setResponses(responses, for: stubID)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        configuration.httpAdditionalHeaders = [
            URLProtocolStub.stubIDHeader: stubID,
        ]
        return URLSession(configuration: configuration)
    }
}
