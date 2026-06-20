import Foundation

protocol HttpTransport {
    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
