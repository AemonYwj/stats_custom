//
//  DeepSeekProvider.swift
//  AIUsage
//

import Foundation
import Kit

private struct DeepSeekBalance: Decodable {
    let isAvailable: Bool?
    let balanceInfos: [BalanceInfo]?

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

private struct BalanceInfo: Decodable {
    let currency: String?
    let totalBalance: String?
    let grantedBalance: String?
    let toppedUpBalance: String?

    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
        case grantedBalance = "granted_balance"
        case toppedUpBalance = "topped_up_balance"
    }
}

public final class DeepSeekProvider: AIUsageProvider {
    public let id: String = "deepseek"
    public let displayName: String = "DeepSeek"
    public let requiresAPIKey: Bool = true

    public init() {}

    public func fetch(apiKey: String?) async throws -> ProviderSnapshot {
        guard let apiKey, !apiKey.isEmpty else {
            throw AIUsageErrorDeepSeek.missingAPIKey
        }

        var request = URLRequest(url: URL(string: "https://api.deepseek.com/user/balance")!)
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIUsageErrorDeepSeek.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw AIUsageErrorDeepSeek.invalidAPIKey
            }
            throw AIUsageErrorDeepSeek.http(http.statusCode)
        }

        let payload = try JSONDecoder().decode(DeepSeekBalance.self, from: data)
        let info = payload.balanceInfos?.first
        let balanceStr: String
        if let info, let total = info.totalBalance, let currency = info.currency {
            balanceStr = "\(total) \(currency)"
        } else {
            balanceStr = localizedString("Unknown")
        }

        return ProviderSnapshot(
            providerId: self.id,
            providerName: self.displayName,
            balance: balanceStr,
            updatedAt: Date()
        )
    }
}

public enum AIUsageErrorDeepSeek: LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case invalidResponse
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return localizedString("DeepSeek API key not configured. Add it in settings.")
        case .invalidAPIKey:
            return localizedString("DeepSeek API key is invalid.")
        case .invalidResponse:
            return localizedString("Unable to parse the DeepSeek balance response.")
        case .http(let code):
            return localizedString("DeepSeek request failed (HTTP %0).", "\(code)")
        }
    }
}
