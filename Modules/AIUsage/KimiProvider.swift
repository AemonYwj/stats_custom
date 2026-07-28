//
//  KimiProvider.swift
//  AIUsage
//

import Foundation
import Kit

private struct KimiCredentials: Decodable {
    let accessToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

public final class KimiProvider: AIUsageProvider {
    public let id: String = "kimi"
    public let displayName: String = "Kimi Coding Plan"
    public let requiresAPIKey: Bool = false

    private let defaultEndpoint = "https://api.kimi.com/coding/v1/user/usage"

    public init() {}

    public func fetch(apiKey: String?) async throws -> ProviderSnapshot {
        let token = try self.readToken()

        let endpoint = Store.shared.string(key: "AIUsage_kimi_endpoint", defaultValue: self.defaultEndpoint)

        var request = URLRequest(url: URL(string: endpoint)!)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIUsageErrorKimi.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw AIUsageErrorKimi.invalidCredentials
            }
            throw AIUsageErrorKimi.http(http.statusCode)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let plan = json?["plan"] as? String
            ?? json?["plan_type"] as? String
            ?? json?["subscription"] as? String

        let usage = json?["usage"] as? [String: Any]
        let remaining: String?
        if let usage {
            let used = usage["used"] as? Double ?? 0
            let limit = usage["limit"] as? Double ?? 0
            if limit > 0 {
                let pct = Int((1 - used / limit) * 100)
                remaining = "\(max(0, min(100, pct)))%"
            } else {
                remaining = nil
            }
        } else if let remainingStr = json?["remaining"] as? String {
            remaining = remainingStr
        } else {
            remaining = nil
        }

        var summary = plan ?? ""
        if let remaining {
            summary += summary.isEmpty ? remaining : " · \(remaining)"
        }
        if summary.isEmpty { summary = localizedString("Connected") }

        return ProviderSnapshot(
            providerId: self.id,
            providerName: self.displayName,
            plan: summary,
            updatedAt: Date()
        )
    }

    private func readToken() throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let path = home.appendingPathComponent(".kimi-code/credentials/kimi-code.json")

        guard FileManager.default.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let credentials = try? JSONDecoder().decode(KimiCredentials.self, from: data),
              let token = credentials.accessToken, !token.isEmpty else {
            throw AIUsageErrorKimi.missingCredentials
        }
        return token
    }
}

public enum AIUsageErrorKimi: LocalizedError {
    case missingCredentials
    case invalidCredentials
    case invalidResponse
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return localizedString("Kimi credentials not found. Run 'kimi login' first.")
        case .invalidCredentials:
            return localizedString("Kimi credentials are invalid or expired.")
        case .invalidResponse:
            return localizedString("Unable to parse the Kimi usage response.")
        case .http(let code):
            return localizedString("Kimi request failed (HTTP %0).", "\(code)")
        }
    }
}
