import Foundation

final class URLSessionTransport: HttpTransport {
    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NsError.noNetwork
        }
        return (data, httpResponse)
    }
}
