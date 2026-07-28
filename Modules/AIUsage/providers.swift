//
//  providers.swift
//  AIUsage
//
//  Provider abstraction for AI quota monitoring.
//  Add new providers (DeepSeek, Kimi, ...) by implementing AIUsageProvider
//  and appending them to AIUsageProviders.all.
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

public struct AIUsageSnapshot: Codable {
    public var provider: String
    public var plan: String?
    public var shortWindow: AIRateWindow?
    public var weeklyWindow: AIRateWindow?
    public var updatedAt: Date
    public var error: String?

    public init(provider: String, plan: String? = nil, shortWindow: AIRateWindow? = nil,
                weeklyWindow: AIRateWindow? = nil, updatedAt: Date = Date(), error: String? = nil) {
        self.provider = provider
        self.plan = plan
        self.shortWindow = shortWindow
        self.weeklyWindow = weeklyWindow
        self.updatedAt = updatedAt
        self.error = error
    }

    public var remainingFraction: Double {
        let remaining = self.weeklyWindow?.remainingPercent ?? self.shortWindow?.remainingPercent ?? 0
        return remaining / 100
    }
}

public protocol AIUsageProvider {
    var id: String { get }
    var displayName: String { get }
    func fetch() async throws -> AIUsageSnapshot
}

public enum AIUsageProviders {
    public static let all: [AIUsageProvider] = [
        CodexUsageProvider()
    ]

    public static var active: AIUsageProvider {
        let id = Store.shared.string(key: "\(ModuleType.aiUsage.stringValue)_provider", defaultValue: "codex")
        return self.all.first(where: { $0.id == id }) ?? self.all[0]
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
