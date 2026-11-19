import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import HanaProviderCore

enum Fixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }
}

/// Records requests and answers them from a route table (path → status/body).
nonisolated final class StubTransport: ProviderHTTPTransport, @unchecked Sendable {
    struct Response {
        var status: Int
        var body: Data
    }

    private let lock = NSLock()
    private var routes: [String: [Response]] = [:]
    private(set) var requests: [URLRequest] = []

    func on(_ method: String, _ path: String, status: Int = 200, body: Data = Data("{}".utf8)) {
        lock.lock(); defer { lock.unlock() }
        routes["\(method) \(path)", default: []].append(Response(status: status, body: body))
    }

    var recordedRequests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let key = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")"
        let response: Response = {
            lock.lock(); defer { lock.unlock() }
            requests.append(request)
            guard var queue = routes[key], !queue.isEmpty else { return Response(status: 404, body: Data()) }
            let next = queue.removeFirst()
            // Keep the last response sticky so repeated calls keep working.
            routes[key] = queue.isEmpty ? [next] : queue
            return next
        }()
        let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: nil, headerFields: nil)!
        return (response.body, http)
    }
}

func makeDefaults(_ name: String = #function) -> UserDefaults {
    let suite = "hana.tests.\(name).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}
