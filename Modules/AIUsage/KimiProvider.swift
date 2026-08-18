//
//  KimiProvider.swift
//  AIUsage
//

import Foundation
import Kit

private struct KimiCredentials: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Double?
    var scope: String?
    var tokenType: String?
    var expiresIn: Double?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case scope
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }

    var needsRefresh: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date().timeIntervalSince1970 + 60
    }
}

private struct KimiTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Double
    let scope: String?
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
        case tokenType = "token_type"
    }
}

public final class KimiProvider: AIUsageProvider {
    public let id: String = "kimi"
    public let displayName: String = "Kimi Coding Plan"
    public let requiresAPIKey: Bool = false

    private let usageEndpoint = URL(string: "https://api.kimi.com/coding/v1/usages")!
    private let tokenEndpoint = URL(string: "https://auth.kimi.com/api/oauth/token")!
    private let oauthClientID = "17e5f671-d194-4dfb-9706-5516cb48c098"

    public init() {}

    public func fetch(apiKey: String?) async throws -> ProviderSnapshot {
        var credentials = try self.readCredentials()
        if credentials.needsRefresh {
            credentials = try await self.refresh(credentials)
        }

        var response = try await self.requestUsage(accessToken: credentials.accessToken)
        if response.http.statusCode == 401 || response.http.statusCode == 403 {
            // Kimi CLI may have rotated the token since this read. Prefer the newest
            // on-disk token before attempting another refresh-token exchange.
            let latest = try self.readCredentials()
            if latest.accessToken != credentials.accessToken {
                credentials = latest
                response = try await self.requestUsage(accessToken: credentials.accessToken)
            }
        }

        if response.http.statusCode == 401 || response.http.statusCode == 403 {
            credentials = try await self.refresh(credentials)
            response = try await self.requestUsage(accessToken: credentials.accessToken)
        }

        guard (200..<300).contains(response.http.statusCode) else {
            if response.http.statusCode == 401 || response.http.statusCode == 403 {
                throw AIUsageErrorKimi.invalidCredentials
            }
            throw AIUsageErrorKimi.http(response.http.statusCode)
        }

        let windows = try KimiUsageParser.parse(response.data)
        return ProviderSnapshot(
            providerId: self.id,
            providerName: self.displayName,
            shortWindow: windows.short,
            weeklyWindow: windows.weekly,
            updatedAt: Date()
        )
    }

    private var credentialsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kimi-code/credentials/kimi-code.json")
    }

    private func readCredentials() throws -> KimiCredentials {
        let path = self.credentialsURL
        guard FileManager.default.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let credentials = try? JSONDecoder().decode(KimiCredentials.self, from: data),
              !credentials.accessToken.isEmpty else {
            throw AIUsageErrorKimi.missingCredentials
        }
        return credentials
    }

    private func requestUsage(accessToken: String) async throws -> (data: Data, http: HTTPURLResponse) {
        var request = URLRequest(url: self.usageEndpoint)
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIUsageErrorKimi.invalidResponse
        }
        return (data, http)
    }

    private func refresh(_ credentials: KimiCredentials) async throws -> KimiCredentials {
        guard let refreshToken = credentials.refreshToken, !refreshToken.isEmpty else {
            throw AIUsageErrorKimi.invalidCredentials
        }

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: self.oauthClientID),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken)
        ]

        var request = URLRequest(url: self.tokenEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIUsageErrorKimi.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw AIUsageErrorKimi.invalidCredentials
            }
            throw AIUsageErrorKimi.refreshFailed(http.statusCode)
        }

        guard let token = try? JSONDecoder().decode(KimiTokenResponse.self, from: data),
              !token.accessToken.isEmpty, !token.refreshToken.isEmpty,
              token.expiresIn > 0 else {
            throw AIUsageErrorKimi.invalidResponse
        }

        let refreshed = KimiCredentials(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: Date().timeIntervalSince1970 + token.expiresIn,
            scope: token.scope,
            tokenType: token.tokenType ?? "Bearer",
            expiresIn: token.expiresIn
        )
        try self.saveCredentials(refreshed)
        return refreshed
    }

    private func saveCredentials(_ credentials: KimiCredentials) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(credentials)
            try data.write(to: self.credentialsURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: self.credentialsURL.path
            )
        } catch {
            throw AIUsageErrorKimi.credentialUpdateFailed
        }
    }
}

internal enum KimiUsageParser {
    static func parse(_ data: Data) throws -> (short: AIRateWindow?, weekly: AIRateWindow?) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIUsageErrorKimi.invalidResponse
        }
        let payload = root["data"] as? [String: Any] ?? root

        let weekly = (payload["usage"] as? [String: Any]).flatMap {
            self.window(from: $0, duration: 7 * 24 * 60 * 60)
        }

        var short: AIRateWindow?
        if let limits = payload["limits"] as? [[String: Any]] {
            for item in limits {
                let detail = item["detail"] as? [String: Any] ?? item
                let windowInfo = item["window"] as? [String: Any] ?? [:]
                let duration = self.duration(item: item, detail: detail, window: windowInfo)
                let label = [
                    item["name"] as? String,
                    detail["name"] as? String,
                    item["title"] as? String,
                    detail["title"] as? String
                ].compactMap { $0 }.joined(separator: " ").lowercased()

                let isFiveHour = duration.map { abs($0 - 5 * 60 * 60) < 60 } ?? label.contains("5h")
                if isFiveHour || short == nil {
                    short = self.window(
                        from: detail,
                        duration: duration ?? 5 * 60 * 60
                    )
                }
                if isFiveHour { break }
            }
        }

        guard weekly != nil || short != nil else {
            throw AIUsageErrorKimi.invalidResponse
        }
        return (short, weekly)
    }

    private static func window(from raw: [String: Any], duration: TimeInterval) -> AIRateWindow? {
        guard let limit = self.number(raw["limit"]), limit > 0 else { return nil }
        let used: Double
        if let value = self.number(raw["used"]) {
            used = value
        } else if let remaining = self.number(raw["remaining"]) {
            used = limit - remaining
        } else {
            return nil
        }

        let resetValue = raw["resetAt"] ?? raw["reset_at"] ?? raw["resetTime"] ?? raw["reset_time"]
        return AIRateWindow(
            usedPercent: (used / limit) * 100,
            resetsAt: self.date(resetValue),
            duration: duration
        )
    }

    private static func duration(
        item: [String: Any],
        detail: [String: Any],
        window: [String: Any]
    ) -> TimeInterval? {
        guard let value = self.number(
            window["duration"] ?? item["duration"] ?? detail["duration"]
        ) else { return nil }
        let unit = (
            window["timeUnit"] as? String
            ?? item["timeUnit"] as? String
            ?? detail["timeUnit"] as? String
            ?? "SECOND"
        ).uppercased()

        if unit.contains("MINUTE") { return value * 60 }
        if unit.contains("HOUR") { return value * 60 * 60 }
        if unit.contains("DAY") { return value * 24 * 60 * 60 }
        return value
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        if let number = self.number(value) {
            let seconds = number >= 1_000_000_000_000 ? number / 1000 : number
            return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
        }
        guard let string = value as? String else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}

public enum AIUsageErrorKimi: LocalizedError {
    case missingCredentials
    case invalidCredentials
    case invalidResponse
    case credentialUpdateFailed
    case refreshFailed(Int)
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return localizedString("Kimi credentials not found. Run 'kimi login' first.")
        case .invalidCredentials:
            return localizedString("Kimi credentials are invalid or expired.")
        case .invalidResponse:
            return localizedString("Unable to parse the Kimi usage response.")
        case .credentialUpdateFailed:
            return localizedString("Unable to update the refreshed Kimi credentials.")
        case .refreshFailed(let code):
            return localizedString("Kimi credential refresh failed (HTTP %0).", "\(code)")
        case .http(let code):
            return localizedString("Kimi request failed (HTTP %0).", "\(code)")
        }
    }
}
