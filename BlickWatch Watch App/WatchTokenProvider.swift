// WatchTokenProvider.swift
// BlickWatch Watch App
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import BlickGraph
import BlickKit
import CryptoKit
import Foundation

nonisolated struct WatchRegistration: Codable, Equatable {
    let clientID: String
    let authority: String
}

private nonisolated struct WatchCredential: Codable {
    var refreshToken: String
    let registration: WatchRegistration
    var identity: ChatIdentity?
}

enum WatchAuthError: LocalizedError {
    case notSignedIn
    case rejected(code: String, description: String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "The watch is not signed in."
        case .rejected(let code, let description): String("\(code): \(description)".prefix(300))
        }
    }
}

/// One sign-in the watch has started: it holds the PKCE verifier, which never
/// leaves the watch, and the state the returning code must match.
struct WatchSignInAttempt {
    static let callbackScheme = "msauth.\(Bundle.main.bundleIdentifier ?? "com.excelano.checkin.watchkitapp")"
    static let redirectURI = "\(callbackScheme)://auth"

    let registration: WatchRegistration
    fileprivate let verifier = WatchSignInAttempt.randomToken()
    let state = WatchSignInAttempt.randomToken()

    init(registration: WatchRegistration) {
        self.registration = registration
    }

    var authorizeURL: URL {
        var components = URLComponents(string: "\(registration.authority)/oauth2/v2.0/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: registration.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: WatchTokenProvider.scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        return components.url!
    }

    private static func randomToken() -> String {
        base64URL(Data((0..<48).map { _ in UInt8.random(in: .min ... .max) }))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Supplies the watch's own Graph access token. The refresh token lives in the
/// watch's keychain, never synced, and is redeemed here; the phone only ever
/// relays the one-time sign-in code, which is bound to a verifier it never sees.
actor WatchTokenProvider: GraphTokenProvider {
    static let shared = WatchTokenProvider()
    static let scopes = (GraphScopes.all + ["offline_access", "openid", "profile"]).joined(separator: " ")

    private static let expiryMargin: TimeInterval = 120

    private var cached: (token: String, expires: Date)?
    private var inFlight: Task<String, Error>?

    var isSignedIn: Bool { WatchKeychain.read() != nil }

    var chatIdentity: ChatIdentity? { WatchKeychain.read()?.identity }

    var registration: WatchRegistration? { WatchKeychain.read()?.registration }

    func graphAccessToken() async throws -> String {
        if let cached, cached.expires.timeIntervalSinceNow > Self.expiryMargin { return cached.token }
        if let inFlight { return try await inFlight.value }
        let task = Task { try await refresh() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    func completeSignIn(_ attempt: WatchSignInAttempt, code: String) async throws {
        let tokens = try await Self.requestTokens(attempt.registration, [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": WatchSignInAttempt.redirectURI,
            "code_verifier": attempt.verifier,
        ])
        guard let refreshToken = tokens.refreshToken else {
            throw WatchAuthError.rejected(code: "no_refresh_token", description: "The sign-in returned no refresh token.")
        }
        WatchKeychain.write(WatchCredential(refreshToken: refreshToken, registration: attempt.registration, identity: tokens.identity))
        cached = (tokens.accessToken, tokens.expires)
    }

    func signOut() {
        WatchKeychain.delete()
        cached = nil
    }

    private func refresh() async throws -> String {
        guard let credential = WatchKeychain.read() else { throw WatchAuthError.notSignedIn }
        do {
            let tokens = try await Self.requestTokens(credential.registration, [
                "grant_type": "refresh_token",
                "refresh_token": credential.refreshToken,
            ])
            if let rotated = tokens.refreshToken {
                WatchKeychain.write(WatchCredential(
                    refreshToken: rotated,
                    registration: credential.registration,
                    identity: tokens.identity ?? credential.identity
                ))
            }
            cached = (tokens.accessToken, tokens.expires)
            return tokens.accessToken
        } catch WatchAuthError.rejected(let code, _) where code == "invalid_grant" {
            signOut()
            throw WatchAuthError.notSignedIn
        }
    }

    private struct Tokens {
        let accessToken: String
        let refreshToken: String?
        let expires: Date
        let identity: ChatIdentity?
    }

    private static func requestTokens(_ registration: WatchRegistration, _ fields: [String: String]) async throws -> Tokens {
        var body = fields
        body["client_id"] = registration.clientID
        body["scope"] = scopes
        var request = URLRequest(url: URL(string: "\(registration.authority)/oauth2/v2.0/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let accessToken = json["access_token"] as? String else {
            throw WatchAuthError.rejected(
                code: json["error"] as? String ?? "token",
                description: json["error_description"] as? String ?? ""
            )
        }
        return Tokens(
            accessToken: accessToken,
            refreshToken: json["refresh_token"] as? String,
            expires: Date().addingTimeInterval(TimeInterval(json["expires_in"] as? Int ?? 0)),
            identity: (json["id_token"] as? String).flatMap(identity(fromIDToken:))
        )
    }

    private static func identity(fromIDToken token: String) -> ChatIdentity? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let userID = claims["oid"] as? String, let tenantID = claims["tid"] as? String else { return nil }
        return ChatIdentity(userID: userID, tenantID: tenantID)
    }
}

private nonisolated enum WatchKeychain {
    private static let service = "com.excelano.checkin.watch.graph"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
    }

    static func write(_ credential: WatchCredential) {
        delete()
        var item = query
        item[kSecValueData as String] = try? JSONEncoder().encode(credential)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrSynchronizable as String] = false
        SecItemAdd(item as CFDictionary, nil)
    }

    static func read() -> WatchCredential? {
        var item = query
        item[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(WatchCredential.self, from: data)
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
