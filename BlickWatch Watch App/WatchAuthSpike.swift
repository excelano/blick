// WatchAuthSpike.swift
// BlickWatch Watch App
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

#if DEBUG
import AuthenticationServices
import BlickKit
import CryptoKit
import SwiftUI

struct WatchAuthSpikeView: View {
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var lines: [String] = []
    @State private var working = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Button("Sign in") { run { try await signIn() } }
                Button("Render test") { run { try await renderTest() } }
                Button("Device code") { run { try await deviceCode() } }
                Button("Refresh token") { run { try await refresh() } }
                Button("Call Graph") { run { try await callGraph() } }
                Button("Forget", role: .destructive) { run { forget() } }
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
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
            do { try await step() } catch { log("FAILED: \(error.localizedDescription)") }
            working = false
        }
    }

    private func log(_ line: String) {
        lines.append(line)
    }

    private func signIn() async throws {
        let verifier = SpikeOAuth.randomVerifier()
        let state = SpikeOAuth.randomVerifier()
        let url = SpikeOAuth.authorizeURL(verifier: verifier, state: state)
        log("opening sign-in")
        let callback = try await webAuthenticationSession.authenticate(
            using: url,
            callbackURLScheme: SpikeOAuth.callbackScheme
        )
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") {
            throw SpikeError.server("\(error): \(value("error_description") ?? "")")
        }
        guard value("state") == state, let code = value("code") else {
            throw SpikeError.server("callback had no matching code")
        }
        log("got code")
        let tokens = try await SpikeOAuth.redeem(code: code, verifier: verifier)
        report(tokens)
    }

    private func renderTest() async throws {
        log("opening a plain page; close it with X")
        do {
            _ = try await webAuthenticationSession.authenticate(
                using: URL(string: "https://example.com")!,
                callbackURLScheme: "blick-render-test"
            )
        } catch {
            log("sheet closed: \(error.localizedDescription)")
        }
    }

    private func deviceCode() async throws {
        let challenge = try await SpikeOAuth.startDeviceCode()
        log("go to \(challenge.verificationURI) and enter \(challenge.userCode)")
        let tokens = try await SpikeOAuth.pollDeviceCode(challenge)
        report(tokens)
    }

    private func refresh() async throws {
        guard let stored = SpikeKeychain.read() else { throw SpikeError.server("no refresh token stored") }
        let tokens = try await SpikeOAuth.refresh(stored)
        report(tokens)
    }

    private func callGraph() async throws {
        guard let stored = SpikeKeychain.read() else { throw SpikeError.server("no refresh token stored") }
        let tokens = try await SpikeOAuth.refresh(stored)
        report(tokens)
        let me = try await SpikeOAuth.get("/me?$select=displayName,userPrincipalName", token: tokens.accessToken)
        log("me: \(me)")
        let inbox = try await SpikeOAuth.get("/me/mailFolders/inbox?$select=unreadItemCount", token: tokens.accessToken)
        log("inbox: \(inbox)")
    }

    private func forget() {
        SpikeKeychain.delete()
        log("refresh token deleted")
    }

    private func report(_ tokens: SpikeTokens) {
        log("ok: access token \(tokens.expiresIn)s, refresh token stored")
        log("scopes: \(tokens.scope)")
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

private struct SpikeDeviceCode {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let interval: Int
    let expiresIn: Int
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

    static func authorizeURL(verifier: String, state: String) -> URL {
        var components = URLComponents(string: "\(PublishedConfig.authority)/oauth2/v2.0/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: PublishedConfig.clientID),
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

    static func redeem(code: String, verifier: String) async throws -> SpikeTokens {
        try await token([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
        ])
    }

    static func refresh(_ refreshToken: String) async throws -> SpikeTokens {
        try await token([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])
    }

    static func startDeviceCode() async throws -> SpikeDeviceCode {
        let json = try await form("devicecode", ["scope": scopes])
        guard let deviceCode = json["device_code"] as? String,
              let userCode = json["user_code"] as? String,
              let uri = json["verification_uri"] as? String else {
            throw SpikeError.oauth(code: json["error"] as? String ?? "devicecode", description: json["error_description"] as? String ?? "")
        }
        return SpikeDeviceCode(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURI: uri,
            interval: json["interval"] as? Int ?? 5,
            expiresIn: json["expires_in"] as? Int ?? 900
        )
    }

    static func pollDeviceCode(_ challenge: SpikeDeviceCode) async throws -> SpikeTokens {
        var interval = challenge.interval
        let deadline = Date().addingTimeInterval(TimeInterval(challenge.expiresIn))
        while Date() < deadline {
            try await Task.sleep(for: .seconds(interval))
            do {
                return try await token([
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                    "device_code": challenge.deviceCode,
                ])
            } catch SpikeError.oauth(let code, _) where code == "authorization_pending" {
                continue
            } catch SpikeError.oauth(let code, _) where code == "slow_down" {
                interval += 5
            }
        }
        throw SpikeError.server("device code expired")
    }

    private static func form(_ endpoint: String, _ fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "\(PublishedConfig.authority)/oauth2/v2.0/\(endpoint)")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = fields
        body["client_id"] = PublishedConfig.clientID
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private static func token(_ fields: [String: String]) async throws -> SpikeTokens {
        var body = fields
        body["scope"] = scopes
        let json = try await form("token", body)
        guard let access = json["access_token"] as? String else {
            throw SpikeError.oauth(code: json["error"] as? String ?? "token", description: json["error_description"] as? String ?? "")
        }
        if let refresh = json["refresh_token"] as? String { SpikeKeychain.write(refresh) }
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

    static func write(_ value: String) {
        delete()
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrSynchronizable as String] = false
        SecItemAdd(item as CFDictionary, nil)
    }

    static func read() -> String? {
        var item = query
        item[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
#endif
