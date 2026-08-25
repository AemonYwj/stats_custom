//
//  CodexUsageClient.swift
//  AIUsage
//

import Foundation
import Kit

public enum AIUsageErrorCodex: LocalizedError {
    case missingCredentials
    case invalidCredentials
    case invalidResponse
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return localizedString("Codex credentials not found. Run 'codex login' first.")
        case .invalidCredentials:
            return localizedString("Codex credentials are invalid or expired. Run 'codex login' again.")
        case .invalidResponse:
            return localizedString("Unable to parse the ChatGPT quota response.")
        case .http(let code):
            return localizedString("ChatGPT quota request failed (HTTP %0).", "\(code)")
        }
    }
}

private struct CodexAuthFile: Decodable {
    let tokens: CodexTokens?
}

private struct CodexTokens: Decodable {
    let accessToken: String?
    let accountID: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case accountID = "account_id"
    }
}

private struct UsageResponse: Decodable {
    let planType: String?
    let rateLimit: RateLimit?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
    }
}

private struct RateLimit: Decodable {
    let primaryWindow: UsageWindow?
    let secondaryWindow: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct UsageWindow: Decodable {
    let usedPercent: Double?
    let resetAt: Int?
    let limitWindowSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetAt = "reset_at"
        case limitWindowSeconds = "limit_window_seconds"
    }

    var normalized: AIRateWindow {
        AIRateWindow(
            usedPercent: self.usedPercent ?? 0,
            resetsAt: self.resetAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            duration: self.limitWindowSeconds.map(TimeInterval.init)
        )
    }
}

public final class CodexUsageProvider: AIUsageProvider {
    public let id: String = "codex"
    public let displayName: String = "ChatGPT (Codex)"
    public let requiresAPIKey: Bool = false

    public init() {}

    public func fetch(apiKey: String?) async throws -> ProviderSnapshot {
        let tokens = try self.readTokens()

        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.timeoutInterval = 15
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        if let accountID = tokens.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIUsageErrorCodex.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw AIUsageErrorCodex.invalidCredentials
            }
            throw AIUsageErrorCodex.http(http.statusCode)
        }

        let payload = try JSONDecoder().decode(UsageResponse.self, from: data)
        let windows = [
            payload.rateLimit?.primaryWindow,
            payload.rateLimit?.secondaryWindow
        ].compactMap { $0 }

        let oneDay = 86_400
        let short = windows.first { ($0.limitWindowSeconds ?? 0) < oneDay }
        let weekly = windows.first { ($0.limitWindowSeconds ?? 0) >= oneDay }

        return ProviderSnapshot(
            providerId: self.id,
            providerName: self.displayName,
            plan: self.formatPlan(payload.planType),
            shortWindow: short?.normalized,
            weeklyWindow: weekly?.normalized,
            updatedAt: Date()
        )
    }

    private func readTokens() throws -> (accessToken: String, accountID: String?) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var paths: [URL] = []

        if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"], !codexHome.isEmpty {
            paths.append(URL(fileURLWithPath: codexHome).appendingPathComponent("auth.json"))
        }
        paths.append(home.appendingPathComponent(".config/codex/auth.json"))
        paths.append(home.appendingPathComponent(".codex/auth.json"))

        for p in paths where FileManager.default.fileExists(atPath: p.path) {
            guard let data = try? Data(contentsOf: p),
                  let auth = try? JSONDecoder().decode(CodexAuthFile.self, from: data),
                  let token = auth.tokens?.accessToken, !token.isEmpty else { continue }
            return (token, auth.tokens?.accountID)
        }

        throw AIUsageErrorCodex.missingCredentials
    }

    private func formatPlan(_ plan: String?) -> String? {
        guard let plan, !plan.isEmpty else { return nil }
        switch plan.lowercased() {
        case "prolite": return "Pro 5x"
        case "pro": return "Pro"
        case "plus": return "Plus"
        case "free": return "Free"
        case "team": return "Team"
        case "enterprise": return "Enterprise"
        default: return plan.capitalized
        }
    }
}
