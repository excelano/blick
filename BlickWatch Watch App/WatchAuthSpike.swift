// WatchAuthSpike.swift
// BlickWatch Watch App
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

#if DEBUG
import BlickKit
import CryptoKit
import SwiftUI

@MainActor @Observable
final class SpikeRelayState {
    static let shared = SpikeRelayState()
    var lines: [String] = []
    fileprivate var pending: (verifier: String, state: String, registration: SpikeRegistration)?

    func log(_ line: String) {
        lines.append(line)
    }

    fileprivate func report(_ tokens: SpikeTokens) {
        log("ok: access token \(tokens.expiresIn)s, refresh token stored")
        log("scopes: \(tokens.scope)")
    }
}

@MainActor
func spikeHandleRelay(_ message: [String: Any]) async -> [String: Any] {
    let relay = SpikeRelayState.shared
    switch message["spike"] as? String {
    case "begin":
        let verifier = SpikeOAuth.randomVerifier()
        let state = SpikeOAuth.randomVerifier()
        let registration = SpikeRegistration(
            clientID: message["clientID"] as? String ?? PublishedConfig.clientID,
            authority: message["authority"] as? String ?? PublishedConfig.authority
        )
        relay.pending = (verifier, state, registration)
        relay.log("phone started a sign-in against \(registration.authority)")
        return ["url": SpikeOAuth.authorizeURL(registration: registration, verifier: verifier, state: state).absoluteString]
    case "code":
        guard let pending = relay.pending, message["state"] as? String == pending.state,
              let code = message["code"] as? String else {
            relay.log("code from phone did not match")
            return ["result": "state mismatch"]
        }
        relay.pending = nil
        relay.log("got code from phone")
        do {
            let tokens = try await SpikeOAuth.redeem(registration: pending.registration, code: code, verifier: pending.verifier)
            relay.report(tokens)
            return ["result": "ok: access token \(tokens.expiresIn)s, refresh token stored"]
        } catch {
            relay.log("FAILED: \(error.localizedDescription)")
            return ["result": "FAILED: \(error.localizedDescription)"]
        }
    default:
        return [:]
    }
}

struct WatchAuthSpikeView: View {
    private let relay = SpikeRelayState.shared
    @State private var working = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Start the sign-in from Settings on the iPhone.").font(.caption2)
                Button("Refresh token") { run { try await refresh() } }
                Button("Call Graph") { run { try await callGraph() } }
                Button("Forget", role: .destructive) { run { forget() } }
                ForEach(Array(relay.lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption2)
                }
            }
        }
        .disabled(working)
        .navigationTitle("Tier 2 spike")
    }

    private func run(_ step: @escaping () async throws -> Void) {
        working = true
        Task {
            do { try await step() } catch { relay.log("FAILED: \(error.localizedDescription)") }
            working = false
        }
    }

    private func refresh() async throws {
        guard let stored = SpikeKeychain.read() else { throw SpikeError.server("no refresh token stored") }
        relay.report(try await SpikeOAuth.refresh(stored))
    }

    private func callGraph() async throws {
        guard let stored = SpikeKeychain.read() else { throw SpikeError.server("no refresh token stored") }
        let tokens = try await SpikeOAuth.refresh(stored)
        relay.report(tokens)
        let me = try await SpikeOAuth.get("/me?$select=displayName,userPrincipalName", token: tokens.accessToken)
        relay.log("me: \(me)")
        let inbox = try await SpikeOAuth.get("/me/mailFolders/inbox?$select=unreadItemCount", token: tokens.accessToken)
        relay.log("inbox: \(inbox)")
    }

    private func forget() {
        SpikeKeychain.delete()
        relay.log("refresh token deleted")
    }
}

private enum SpikeError: LocalizedError {
    case server(String)
    case oauth(code: String, description: String)
    var errorDescription: String? {
        switch self {
        case .server(let message): String(message.prefix(300))
        case .oauth(let code, let description): String("\(code): \(description)".prefix(300))
        }
    }
}

struct SpikeRegistration: Codable {
    let clientID: String
    let authority: String
}

private struct SpikeCredential: Codable {
    let refreshToken: String
    let registration: SpikeRegistration
}

private struct SpikeTokens {
    let accessToken: String
    let expiresIn: Int
    let scope: String
}

private enum SpikeOAuth {
    static let callbackScheme = "msauth.com.excelano.checkin.watchkitapp"
    static let redirectURI = "\(callbackScheme)://auth"
    static let scopes = (GraphScopes.all + ["offline_access", "openid", "profile"]).joined(separator: " ")

    static func randomVerifier() -> String {
        let bytes = (0..<48).map { _ in UInt8.random(in: .min ... .max) }
        return base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func authorizeURL(registration: SpikeRegistration, verifier: String, state: String) -> URL {
        var components = URLComponents(string: "\(registration.authority)/oauth2/v2.0/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: registration.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        return components.url!
    }

    static func redeem(registration: SpikeRegistration, code: String, verifier: String) async throws -> SpikeTokens {
        try await token(registration, [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
        ])
    }

    fileprivate static func refresh(_ credential: SpikeCredential) async throws -> SpikeTokens {
        try await token(credential.registration, [
            "grant_type": "refresh_token",
            "refresh_token": credential.refreshToken,
        ])
    }

    private static func form(_ endpoint: String, _ registration: SpikeRegistration, _ fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "\(registration.authority)/oauth2/v2.0/\(endpoint)")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = fields
        body["client_id"] = registration.clientID
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private static func token(_ registration: SpikeRegistration, _ fields: [String: String]) async throws -> SpikeTokens {
        var body = fields
        body["scope"] = scopes
        let json = try await form("token", registration, body)
        guard let access = json["access_token"] as? String else {
            throw SpikeError.oauth(code: json["error"] as? String ?? "token", description: json["error_description"] as? String ?? "")
        }
        if let refresh = json["refresh_token"] as? String {
            SpikeKeychain.write(SpikeCredential(refreshToken: refresh, registration: registration))
        }
        return SpikeTokens(
            accessToken: access,
            expiresIn: json["expires_in"] as? Int ?? 0,
            scope: json["scope"] as? String ?? ""
        )
    }

    static func get(_ path: String, token: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0\(path)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8) ?? ""
        guard status == 200 else { throw SpikeError.server("graph \(status): \(text)") }
        return text
    }
}

private enum SpikeKeychain {
    private static let service = "com.excelano.checkin.watch.spike"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
    }

    static func write(_ credential: SpikeCredential) {
        delete()
        var item = query
        item[kSecValueData as String] = try? JSONEncoder().encode(credential)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrSynchronizable as String] = false
        SecItemAdd(item as CFDictionary, nil)
    }

    static func read() -> SpikeCredential? {
        var item = query
        item[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(SpikeCredential.self, from: data)
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
#endif
