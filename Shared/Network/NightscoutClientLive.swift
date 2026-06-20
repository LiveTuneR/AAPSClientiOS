import Foundation

final class NightscoutClientLive: NightscoutClient {
    private let nsURL: String
    private let accessToken: String
    private let transport: HttpTransport
    private let decoder = JSONDecoder()
    private var jwtToken: String = ""

    init(baseURL: URL, accessToken: String, transport: HttpTransport) {
        let urlString = baseURL.absoluteString
        self.nsURL = urlString.hasSuffix("/") ? urlString : "\(urlString)/"
        self.accessToken = accessToken
        self.transport = transport
    }

    func authorize() async throws {
        let urlString = "\(nsURL)api/v2/authorization/request/\(accessToken)"
        guard let url = URL(string: urlString) else { throw NsError.badURL }
        let request = URLRequest(url: url)
        let (data, response) = try await execute(request, authenticated: false)
        if response.statusCode == 401 || response.statusCode == 403 {
            throw NsError.unauthorized
        }
        guard response.statusCode == 200 else {
            throw NsError.server(response.statusCode)
        }
        guard let auth = try? decoder.decode(RemoteAuthResponse.self, from: data),
              !auth.token.isEmpty else {
            throw NsError.decoding("Invalid auth response")
        }
        jwtToken = auth.token
    }

    func fetchEntries(limit: Int) async throws -> [GlucoseReading] {
        let path = "api/v3/entries?sort$desc=date&limit=\(limit)"
        let data = try await get(path)
        return try NsMapping.glucose(from: data)
    }

    func fetchTreatments(since: Date? = nil) async throws -> [Treatment] {
        var path = "api/v3/treatments?sort$desc=date&limit=100"
        if let since {
            path += "&srvModified$gte=\(Int64(since.timeIntervalSince1970 * 1000))"
        }
        let data = try await get(path)
        return try NsMapping.treatments(from: data)
    }

    func fetchDeviceStatus() async throws -> LoopStatus? {
        let path = "api/v3/devicestatus?sort$desc=date&limit=1"
        let data = try await get(path)
        return try NsMapping.loopStatus(from: data)
    }

    func fetchProfile() async throws -> NsProfile {
        let path = "api/v3/profile?sort$desc=date&limit=1"
        let data = try await get(path)
        return try NsMapping.profile(from: data)
    }

    func fetchProfileStore() async throws -> NsProfileStore {
        let path = "api/v3/profile?sort$desc=date&limit=1"
        let data = try await get(path)
        return try NsMapping.profileStore(from: data)
    }

    /// Paginated entries covering `days` back.
    /// Uses skip-based pagination + server-side date$gt filter (NS v3 ignores date$lt cursors).
    func fetchEntries(sinceDays days: Int) async throws -> [GlucoseReading] {
        let cutoffMs = Int64(Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970 * 1000)
        let pageSize = 1000
        var all: [GlucoseReading] = []
        var skip = 0
        for _ in 0..<200 {  // safety cap: 200 pages × server-limit ≈ 100k readings
            let path = "api/v3/entries?sort$desc=date&limit=\(pageSize)&skip=\(skip)&date$gt=\(cutoffMs)"
            let data = try await get(path)
            let page = try NsMapping.glucose(from: data)
            if page.isEmpty { break }
            all.append(contentsOf: page)
            skip += page.count
        }
        return all
    }

    func fetchDeviceStatusHistory(since: Date) async throws -> [DeviceStatusEntry] {
        let cutoffMs = Int64(since.timeIntervalSince1970 * 1000)
        let path = "api/v3/devicestatus?sort$desc=date&limit=288&date$gt=\(cutoffMs)"
        let data = try await get(path)
        return try NsMapping.deviceStatusHistory(from: data)
    }

    func fetchCareEvents() async throws -> [Treatment] {
        let types = ["Site Change", "Sensor Change", "Sensor Start", "Insulin Change", "Pump Battery Change", "Profile Switch"]
        let inValue = types.joined(separator: "|")
        let encoded = inValue.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? inValue
        let path = "api/v3/treatments?sort$desc=date&limit=50&eventType$in=\(encoded)"
        let data = try await get(path)
        return try NsMapping.treatments(from: data)
    }

    func postTreatment(_ payload: [String: Any]) async throws {
        let path = "api/v3/treatments"
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await post(path, body: body)
    }

    // MARK: - Private

    private func get(_ path: String) async throws -> Data {
        let urlString = "\(nsURL)\(path)"
        guard let url = URL(string: urlString) else { throw NsError.badURL }
        let request = URLRequest(url: url)
        return try await authenticatedData(request)
    }

    private func post(_ path: String, body: Data) async throws -> Data {
        let urlString = "\(nsURL)\(path)"
        guard let url = URL(string: urlString) else { throw NsError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await authenticatedData(request)
    }

    private func authenticatedData(_ request: URLRequest) async throws -> Data {
        if jwtToken.isEmpty {
            try await authorize()
        }
        let (data, response) = try await execute(request, authenticated: true)
        if response.statusCode == 401 || response.statusCode == 403 {
            try await refreshJWT()
            let (retryData, retryResponse) = try await execute(request, authenticated: true)
            if retryResponse.statusCode >= 400 {
                throw httpError(retryResponse.statusCode, retryData, request)
            }
            return retryData
        }
        if response.statusCode >= 400 {
            throw httpError(response.statusCode, data, request)
        }
        return data
    }

    /// Diagnostic error carrying HTTP status + server body + method/path.
    private func httpError(_ code: Int, _ body: Data, _ request: URLRequest) -> NsError {
        let bodyText = String(data: body, encoding: .utf8)?.prefix(300) ?? ""
        let method = request.httpMethod ?? "?"
        let path = request.url?.path ?? "?"
        return .decoding("HTTP \(code) \(method) \(path) — \(bodyText)")
    }

    private func execute(_ request: URLRequest, authenticated: Bool) async throws -> (Data, HTTPURLResponse) {
        var req = request
        if authenticated {
            req.setValue("Bearer \(jwtToken)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await transport.execute(req)
            return (data, response)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            throw NsError.noNetwork
        }
    }

    private func refreshJWT() async throws {
        try await authorize()
    }
}

private struct RemoteAuthResponse: Decodable {
    let token: String
    let iat: Int64
    let exp: Int64
}
