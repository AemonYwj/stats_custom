//
//  providers.swift
//  AIUsage
//

import Foundation
import Kit

public struct AIRateWindow: Codable {
    public var usedPercent: Double
    public var resetsAt: Date?
    public var duration: TimeInterval?

    public var remainingPercent: Double {
        max(0, min(100, 100 - self.usedPercent))
    }

    public init(usedPercent: Double, resetsAt: Date? = nil, duration: TimeInterval? = nil) {
        self.usedPercent = max(0, min(100, usedPercent))
        self.resetsAt = resetsAt
        self.duration = duration
    }
}

public struct ProviderSnapshot: Codable {
    public var providerId: String
    public var providerName: String
    public var plan: String?
    public var balance: String?
    public var shortWindow: AIRateWindow?
    public var weeklyWindow: AIRateWindow?
    public var updatedAt: Date
    public var error: String?

    public init(providerId: String, providerName: String, plan: String? = nil,
                balance: String? = nil, shortWindow: AIRateWindow? = nil,
                weeklyWindow: AIRateWindow? = nil, updatedAt: Date = Date(),
                error: String? = nil) {
        self.providerId = providerId
        self.providerName = providerName
        self.plan = plan
        self.balance = balance
        self.shortWindow = shortWindow
        self.weeklyWindow = weeklyWindow
        self.updatedAt = updatedAt
        self.error = error
    }

    public var remainingFraction: Double {
        if let remaining = self.weeklyWindow?.remainingPercent ?? self.shortWindow?.remainingPercent {
            return remaining / 100
        }
        return 0
    }
}

public struct AIUsageSnapshot: Codable {
    public var providers: [ProviderSnapshot]
    public var updatedAt: Date

    public init(providers: [ProviderSnapshot] = [], updatedAt: Date = Date()) {
        self.providers = providers
        self.updatedAt = updatedAt
    }

    public var primaryProvider: ProviderSnapshot? {
        self.providers.first(where: { $0.error == nil }) ?? self.providers.first
    }
}

public protocol AIUsageProvider {
    var id: String { get }
    var displayName: String { get }
    var requiresAPIKey: Bool { get }
    func fetch(apiKey: String?) async throws -> ProviderSnapshot
}

public enum AIUsageProviders {
    public static let all: [AIUsageProvider] = [
        CodexUsageProvider(),
        DeepSeekProvider(),
        KimiProvider()
    ]

    public static func enabledProviders() -> [AIUsageProvider] {
        return all.filter {
            Store.shared.bool(key: "AIUsage_\($0.id)_enabled", defaultValue: $0.id == "codex")
        }
    }

    public static func apiKey(for providerId: String) -> String? {
        let key = Store.shared.string(key: "AIUsage_\(providerId)_apiKey", defaultValue: "")
        return key.isEmpty ? nil : key
    }

    public static func setAPIKey(_ key: String, for providerId: String) {
        Store.shared.set(key: "AIUsage_\(providerId)_apiKey", value: key)
    }

    public static func isEnabled(_ providerId: String) -> Bool {
        Store.shared.bool(key: "AIUsage_\(providerId)_enabled", defaultValue: providerId == "codex")
    }

    public static func setEnabled(_ enabled: Bool, for providerId: String) {
        Store.shared.set(key: "AIUsage_\(providerId)_enabled", value: enabled)
    }
}

public let AIUsageUpdateIntervals: [KeyValue_t] = [
    KeyValue_t(key: "60", value: "1 min"),
    KeyValue_t(key: "120", value: "2 min"),
    KeyValue_t(key: "300", value: "5 min"),
    KeyValue_t(key: "600", value: "10 min"),
    KeyValue_t(key: "1800", value: "30 min"),
    KeyValue_t(key: "3600", value: "1 hour")
]
