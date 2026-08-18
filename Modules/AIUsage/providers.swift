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

    public var usedFraction: Double {
        max(0, min(1, self.usedPercent / 100))
    }

    public var remainingPercent: Double {
        max(0, min(100, 100 - self.usedPercent))
    }

    public var remainingFraction: Double {
        self.remainingPercent / 100
    }

    public func elapsedFraction(at date: Date = Date()) -> Double? {
        guard let resetsAt, let duration, duration > 0 else { return nil }
        let startedAt = resetsAt.addingTimeInterval(-duration)
        return max(0, min(1, date.timeIntervalSince(startedAt) / duration))
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
    public var monthlyWindow: AIRateWindow?
    public var updatedAt: Date
    public var error: String?

    public init(providerId: String, providerName: String, plan: String? = nil,
                balance: String? = nil, shortWindow: AIRateWindow? = nil,
                weeklyWindow: AIRateWindow? = nil, monthlyWindow: AIRateWindow? = nil,
                updatedAt: Date = Date(),
                error: String? = nil) {
        self.providerId = providerId
        self.providerName = providerName
        self.plan = plan
        self.balance = balance
        self.shortWindow = shortWindow
        self.weeklyWindow = weeklyWindow
        self.monthlyWindow = monthlyWindow
        self.updatedAt = updatedAt
        self.error = error
    }

    public var remainingFraction: Double {
        self.weeklyWindow?.remainingFraction ?? self.shortWindow?.remainingFraction ?? 0
    }

    public var usedFraction: Double {
        self.weeklyWindow?.usedFraction ?? self.shortWindow?.usedFraction ?? 0
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
        KimiProvider(),
        OpenCodeGoProvider()
    ]

    public static func enabledProviders() -> [AIUsageProvider] {
        return all.filter {
            Store.shared.bool(key: "AIUsage_\($0.id)_enabled", defaultValue: $0.id == "codex")
        }
    }

    public static func apiKey(for providerId: String) -> String? {
        let key = Store.shared.string(key: "AIUsage_\(providerId)_apiKey", defaultValue: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    public static func setAPIKey(_ key: String, for providerId: String) {
        Store.shared.set(
            key: "AIUsage_\(providerId)_apiKey",
            value: key.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    public static func isEnabled(_ providerId: String) -> Bool {
        Store.shared.bool(key: "AIUsage_\(providerId)_enabled", defaultValue: providerId == "codex")
    }

    public static func setEnabled(_ enabled: Bool, for providerId: String) {
        Store.shared.set(key: "AIUsage_\(providerId)_enabled", value: enabled)
    }

    public static var menuBarMetric: AIUsageMenuBarMetric {
        let raw = Store.shared.string(
            key: "AIUsage_menuBarMetric",
            defaultValue: AIUsageMenuBarMetric.codexWeekly.rawValue
        )
        return AIUsageMenuBarMetric(rawValue: raw) ?? .codexWeekly
    }

    public static func setMenuBarMetric(_ metric: AIUsageMenuBarMetric) {
        Store.shared.set(key: "AIUsage_menuBarMetric", value: metric.rawValue)
        self.setEnabled(true, for: metric.providerID)
    }

    public static func menuBarValue(from snapshot: AIUsageSnapshot) -> AIUsageMenuBarValue {
        let metric = self.menuBarMetric
        guard let provider = snapshot.providers.first(where: { $0.providerId == metric.providerID }),
              provider.error == nil else {
            return AIUsageMenuBarValue(fraction: nil, text: "--")
        }

        if metric == .deepSeekBalance {
            return AIUsageMenuBarValue(fraction: nil, text: provider.balance ?? "--")
        }

        guard let window = metric.window(from: provider) else {
            return AIUsageMenuBarValue(fraction: nil, text: "--")
        }
        let remaining = window.remainingFraction
        return AIUsageMenuBarValue(
            fraction: remaining,
            text: "\(Int((remaining * 100).rounded()))%"
        )
    }
}

public struct AIUsageMenuBarValue {
    public let fraction: Double?
    public let text: String
}

public enum AIUsageMenuBarMetric: String, CaseIterable {
    case codexWeekly = "codex.weekly"
    case deepSeekBalance = "deepseek.balance"
    case kimiShort = "kimi.short"
    case kimiWeekly = "kimi.weekly"
    case openCodeGoShort = "opencode-go.short"
    case openCodeGoWeekly = "opencode-go.weekly"
    case openCodeGoMonthly = "opencode-go.monthly"

    public var providerID: String {
        switch self {
        case .codexWeekly: return "codex"
        case .deepSeekBalance: return "deepseek"
        case .kimiShort, .kimiWeekly: return "kimi"
        case .openCodeGoShort, .openCodeGoWeekly, .openCodeGoMonthly: return "opencode-go"
        }
    }

    public var displayName: String {
        switch self {
        case .codexWeekly:
            return localizedString("ChatGPT weekly remaining")
        case .deepSeekBalance:
            return localizedString("DeepSeek balance")
        case .kimiShort:
            return localizedString("Kimi 5-hour remaining")
        case .kimiWeekly:
            return localizedString("Kimi weekly remaining")
        case .openCodeGoShort:
            return localizedString("OpenCode Go 5-hour remaining")
        case .openCodeGoWeekly:
            return localizedString("OpenCode Go weekly remaining")
        case .openCodeGoMonthly:
            return localizedString("OpenCode Go monthly remaining")
        }
    }

    public func window(from provider: ProviderSnapshot) -> AIRateWindow? {
        switch self {
        case .codexWeekly, .kimiWeekly, .openCodeGoWeekly:
            return provider.weeklyWindow
        case .kimiShort, .openCodeGoShort:
            return provider.shortWindow
        case .openCodeGoMonthly:
            return provider.monthlyWindow
        case .deepSeekBalance:
            return nil
        }
    }
}

public let AIUsageMenuBarMetrics: [KeyValue_t] = AIUsageMenuBarMetric.allCases.map {
    KeyValue_t(key: $0.rawValue, value: $0.displayName)
}

public let AIUsageUpdateIntervals: [KeyValue_t] = [
    KeyValue_t(key: "60", value: "1 min"),
    KeyValue_t(key: "120", value: "2 min"),
    KeyValue_t(key: "300", value: "5 min"),
    KeyValue_t(key: "600", value: "10 min"),
    KeyValue_t(key: "1800", value: "30 min"),
    KeyValue_t(key: "3600", value: "1 hour")
]
