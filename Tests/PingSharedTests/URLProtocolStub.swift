import Foundation

enum StubbedResponse {
    case protobuf(Data)
    case jsonRecords(fileURL: URL)

    var body: Data {
        switch self {
        case let .protobuf(data):
            data
        case let .jsonRecords(fileURL):
            """
            {"results":[{"file":{"url":"\(fileURL.absoluteString)"}}]}
            """.data(using: .utf8) ?? Data()
        }
    }

    var contentType: String {
        switch self {
        case .protobuf:
            "application/octet-stream"
        case .jsonRecords:
            "application/json"
        }
    }
}

final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [URL: StubbedResponse] = [:]

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let response = Self.responses[url] else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": response.contentType]
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

extension URLSession {
    static func stubbed(with responses: [URL: StubbedResponse]) -> URLSession {
        URLProtocolStub.responses.merge(responses) { _, new in new }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
}
