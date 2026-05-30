// GraphCore.swift
// CheckInGraph
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import os

/// Supplies a Microsoft Graph access token to `GraphCore`. The concrete
/// conformer differs by process: the app wraps its `AuthService`, the widget
/// extension does its own silent MSAL acquire from the shared keychain cache,
/// and a future watch tier would do its own. Keeping token acquisition behind
/// a protocol is what lets `GraphCore` live in a framework without importing
/// MSAL, so each token source stays on the device that owns it and no token
/// ever crosses a process or device boundary it shouldn't.
public protocol GraphTokenProvider {
    func graphAccessToken() async throws -> String
}

/// The single Microsoft Graph access layer shared by the app and the widget
/// extension. It owns the HTTP plumbing: URL building, auth-header injection
/// from a `GraphTokenProvider`, status checking, and a one-shot retry on the
/// transient connection drops that happen when iOS resumes an app with stale
/// sockets in its pool. Presence/OOO writes and the widget snapshot reads are
/// added in extensions on this type. The app's `GraphClient` rides it for its
/// own rich reads, and the widget rides it directly, so there is exactly one
/// implementation of each Graph call instead of a copy per process.
public final class GraphCore {
    private let tokenProvider: GraphTokenProvider
    private let session: URLSession
    let baseURL = "https://graph.microsoft.com/v1.0"
    let logger = Logger(subsystem: "com.excelano.checkin", category: "graph-core")

    public init(tokenProvider: GraphTokenProvider, session: URLSession = .shared) {
        self.tokenProvider = tokenProvider
        self.session = session
    }

    // MARK: - HTTP primitives

    public func get<T: Decodable>(
        _ path: String,
        query: [String: String] = [:],
        headers: [String: String] = [:]
    ) async throws -> T {
        var request = URLRequest(url: try makeURL(path: path, query: query))
        request.httpMethod = "GET"
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request = try await authorize(request)
        let (data, response) = try await perform(request, retryOnTransient: true)
        try check(response, data: data, method: "GET", path: path)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Retry is OFF for `post`. A `POST` may be non-idempotent (send a reply,
    /// post a chat message), and `.networkConnectionLost` can't tell "never
    /// arrived" from "response lost", so double-sending is the worse default.
    /// Idempotent POSTs (presence sets) accept that they may need a manual
    /// retry, which the caller already tolerates.
    public func post(_ path: String, body: some Encodable) async throws {
        var request = URLRequest(url: try makeURL(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request = try await authorize(request)
        let (data, response) = try await perform(request, retryOnTransient: false)
        try check(response, data: data, method: "POST", path: path)
    }

    public func postDecoded<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        var request = URLRequest(url: try makeURL(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request = try await authorize(request)
        let (data, response) = try await perform(request, retryOnTransient: false)
        try check(response, data: data, method: "POST", path: path)
        return try JSONDecoder().decode(T.self, from: data)
    }

    public func emptyPost(_ path: String) async throws {
        var request = URLRequest(url: try makeURL(path: path))
        request.httpMethod = "POST"
        request = try await authorize(request)
        let (data, response) = try await perform(request, retryOnTransient: true)
        try check(response, data: data, method: "POST", path: path)
    }

    public func patch(_ path: String, body: some Encodable) async throws {
        var request = URLRequest(url: try makeURL(path: path))
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request = try await authorize(request)
        let (data, response) = try await perform(request, retryOnTransient: true)
        try check(response, data: data, method: "PATCH", path: path)
    }

    public func delete(_ path: String) async throws {
        var request = URLRequest(url: try makeURL(path: path))
        request.httpMethod = "DELETE"
        request = try await authorize(request)
        let (data, response) = try await perform(request, retryOnTransient: true)
        try check(response, data: data, method: "DELETE", path: path)
    }

    // MARK: - Internals

    private func makeURL(path: String, query: [String: String] = [:]) throws -> URL {
        guard var components = URLComponents(string: baseURL + path) else {
            throw GraphError.invalidURL(path: path)
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw GraphError.invalidURL(path: path) }
        return url
    }

    private func authorize(_ request: URLRequest) async throws -> URLRequest {
        let token = try await tokenProvider.graphAccessToken()
        var authorized = request
        authorized.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return authorized
    }

    private func check(_ response: URLResponse, data: Data, method: String, path: String) throws {
        guard let http = response as? HTTPURLResponse else { throw GraphError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GraphError.httpError(method: method, path: path, status: http.statusCode, body: body)
        }
    }

    private func perform(_ request: URLRequest, retryOnTransient: Bool) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where retryOnTransient && Self.isTransient(error.code) {
            try await Task.sleep(for: .milliseconds(250))
            return try await session.data(for: request)
        }
    }

    private static func isTransient(_ code: URLError.Code) -> Bool {
        switch code {
        case .networkConnectionLost, .timedOut, .cannotConnectToHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }
}

public enum GraphError: LocalizedError {
    case invalidURL(path: String)
    case invalidResponse
    case httpError(method: String, path: String, status: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            return "Could not construct Graph URL for path \(path)."
        case .invalidResponse:
            return "Invalid response from Microsoft Graph."
        case .httpError(let method, let path, let status, let body):
            return "Graph API \(method) \(path) returned \(status): \(body)"
        }
    }
}

/// Graph's standard list envelope. `count` decodes `@odata.count`, present
/// only when a query asks for it with `$count=true` plus the
/// `ConsistencyLevel: eventual` header.
public struct GraphList<T: Decodable>: Decodable {
    public let value: [T]
    public let count: Int?

    enum CodingKeys: String, CodingKey {
        case value
        case count = "@odata.count"
    }
}

/// Parse the ISO8601 timestamps Graph returns, tolerating the fractional
/// seconds the default `ISO8601DateFormatter` rejects (Graph sends both
/// "2026-04-08T18:55:28.844Z" and the trimmed "…:51Z").
public func parseISO8601(_ dateString: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: dateString) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: dateString)
}

/// Parse the naive-datetime-plus-separate-timezone form Graph uses for
/// calendar event start/end. Falls back to now (logged) on a malformed
/// string so a bad date renders at the wrong time rather than crashing.
public func parseGraphDate(_ dateString: String, timeZone: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS"
    formatter.timeZone = TimeZone(identifier: timeZone) ?? .current
    if let date = formatter.date(from: dateString) { return date }
    Logger(subsystem: "com.excelano.checkin", category: "graph-core")
        .error("parseGraphDate failed: '\(dateString, privacy: .public)' tz='\(timeZone, privacy: .public)'")
    return Date()
}
