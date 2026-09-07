import Foundation
import Synchronization

final class MealURLProtocol: URLProtocol {
    struct Fixture: Sendable {
        enum Response: Sendable {
            case http(Int, String)
            case failure(URLError.Code)
            case suspended
        }

        let response: Response
        let requests: AsyncStream<URLRequest>.Continuation
        let stops: AsyncStream<Void>.Continuation
    }

    static let fixtures = Mutex<[String: Fixture]>([:])

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let fixture, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        fixture.requests.yield(request)
        switch fixture.response {
        case .http(let status, let body):
            guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .suspended:
            break
        }
    }

    override func stopLoading() {
        fixture?.stops.yield(())
    }

    private var fixture: Fixture? {
        guard let identifier = request.value(forHTTPHeaderField: "X-Meal-Test") else { return nil }
        return Self.fixtures.withLock { $0[identifier] }
    }
}

struct MealHTTPFixture {
    let session: URLSession
    let requests: AsyncStream<URLRequest>
    let stops: AsyncStream<Void>
    private let identifier: String

    init(_ response: MealURLProtocol.Fixture.Response) {
        let identifier = UUID().uuidString
        self.identifier = identifier
        let (requests, requestContinuation) = AsyncStream<URLRequest>.makeStream()
        let (stops, stopContinuation) = AsyncStream<Void>.makeStream()
        self.requests = requests
        self.stops = stops
        let fixture = MealURLProtocol.Fixture(
            response: response, requests: requestContinuation, stops: stopContinuation)
        MealURLProtocol.fixtures.withLock { $0[identifier] = fixture }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MealURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Meal-Test": identifier]
        session = URLSession(configuration: configuration)
    }

    func close() {
        session.invalidateAndCancel()
        let fixture = MealURLProtocol.fixtures.withLock { $0.removeValue(forKey: identifier) }
        fixture?.requests.finish()
        fixture?.stops.finish()
    }
}
