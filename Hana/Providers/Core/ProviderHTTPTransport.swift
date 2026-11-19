import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Injectable HTTP layer so providers can be unit-tested with fixtures.
nonisolated protocol ProviderHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

nonisolated struct URLSessionProviderTransport: ProviderHTTPTransport {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw VideoProviderError.invalidResponse }
        return (data, http)
    }
}
