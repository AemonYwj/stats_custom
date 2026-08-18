//
//  OpenCodeGoProvider.swift
//  AIUsage
//

import Foundation
import Kit

private struct OpenCodeGoUsageRow: Decodable {
    let createdMs: Int64
    let cost: Double
}

public final class OpenCodeGoProvider: AIUsageProvider {
    public let id: String = "opencode-go"
    public let displayName: String = "OpenCode Go"
    public let requiresAPIKey: Bool = false

    private let fiveHours: TimeInterval = 5 * 60 * 60
    private let week: TimeInterval = 7 * 24 * 60 * 60
    private let limits = (short: 12.0, weekly: 30.0, monthly: 60.0)

    public init() {}

    public func fetch(apiKey: String?) async throws -> ProviderSnapshot {
        guard self.hasCredentials() else {
            throw AIUsageErrorOpenCodeGo.missingCredentials
        }

        let rows = try self.readUsageRows()
        let now = Date()
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let shortStartMs = nowMs - Int64(self.fiveHours * 1000)
        let weekStart = self.startOfUTCWeek(now)
        let weekEnd = weekStart.addingTimeInterval(self.week)
        let month = self.monthBounds(now: now, earliestMs: rows.map(\.createdMs).min())

        var shortCost = 0.0
        var weeklyCost = 0.0
        var monthlyCost = 0.0
        var oldestShortMs: Int64?

        for row in rows where row.cost.isFinite && row.cost >= 0 {
            if row.createdMs >= shortStartMs && row.createdMs <= nowMs {
                shortCost += row.cost
                if oldestShortMs.map({ row.createdMs < $0 }) ?? true {
                    oldestShortMs = row.createdMs
                }
            }

            let date = Date(timeIntervalSince1970: TimeInterval(row.createdMs) / 1000)
            if date >= weekStart && date < weekEnd {
                weeklyCost += row.cost
            }
            if date >= month.start && date < month.end {
                monthlyCost += row.cost
            }
        }

        let shortReset = oldestShortMs.map {
            Date(timeIntervalSince1970: TimeInterval($0) / 1000 + self.fiveHours)
        } ?? now.addingTimeInterval(self.fiveHours)

        return ProviderSnapshot(
            providerId: self.id,
            providerName: self.displayName,
            plan: localizedString("Go · local estimate"),
            shortWindow: AIRateWindow(
                usedPercent: self.percent(used: shortCost, limit: self.limits.short),
                resetsAt: shortReset,
                duration: self.fiveHours
            ),
            weeklyWindow: AIRateWindow(
                usedPercent: self.percent(used: weeklyCost, limit: self.limits.weekly),
                resetsAt: weekEnd,
                duration: self.week
            ),
            monthlyWindow: AIRateWindow(
                usedPercent: self.percent(used: monthlyCost, limit: self.limits.monthly),
                resetsAt: month.end,
                duration: month.end.timeIntervalSince(month.start)
            ),
            updatedAt: now
        )
    }

    private var openCodeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode", isDirectory: true)
    }

    private func hasCredentials() -> Bool {
        let url = self.openCodeDirectory.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = object[self.id] as? [String: Any],
              let key = entry["key"] as? String else {
            return false
        }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func readUsageRows() throws -> [OpenCodeGoUsageRow] {
        let database = self.openCodeDirectory.appendingPathComponent("opencode.db")
        guard FileManager.default.fileExists(atPath: database.path) else {
            throw AIUsageErrorOpenCodeGo.missingDatabase
        }

        let modernSQL = """
            WITH provider_messages AS (
              SELECT
                id AS messageID,
                CAST(COALESCE(json_extract(data, '$.time.created'), time_created) AS INTEGER) AS createdMs,
                CAST(json_extract(data, '$.cost') AS REAL) AS cost,
                json_type(data, '$.cost') IN ('integer', 'real') AS hasCost
              FROM message
              WHERE json_valid(data)
                AND json_extract(data, '$.providerID') = 'opencode-go'
                AND json_extract(data, '$.role') = 'assistant'
            )
            SELECT
              CAST(COALESCE(json_extract(p.data, '$.time.created'), p.time_created, m.createdMs) AS INTEGER)
                AS createdMs,
              CAST(json_extract(p.data, '$.cost') AS REAL) AS cost
            FROM part p
            JOIN provider_messages m ON m.messageID = p.message_id
            WHERE json_valid(p.data)
              AND json_extract(p.data, '$.type') = 'step-finish'
              AND json_type(p.data, '$.cost') IN ('integer', 'real')
            UNION ALL
            SELECT createdMs, cost
            FROM provider_messages m
            WHERE hasCost
              AND NOT EXISTS (
                SELECT 1 FROM part p
                WHERE p.message_id = m.messageID
                  AND json_valid(p.data)
                  AND json_extract(p.data, '$.type') = 'step-finish'
                  AND json_type(p.data, '$.cost') IN ('integer', 'real')
              )
            """

        do {
            return try self.query(database: database, sql: modernSQL)
        } catch {
            let legacySQL = """
                SELECT
                  CAST(COALESCE(json_extract(data, '$.time.created'), time_created) AS INTEGER) AS createdMs,
                  CAST(json_extract(data, '$.cost') AS REAL) AS cost
                FROM message
                WHERE json_valid(data)
                  AND json_extract(data, '$.providerID') = 'opencode-go'
                  AND json_extract(data, '$.role') = 'assistant'
                  AND json_type(data, '$.cost') IN ('integer', 'real')
                """
            return try self.query(database: database, sql: legacySQL)
        }
    }

    private func query(database: URL, sql: String) throws -> [OpenCodeGoUsageRow] {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-json", database.path, sql]
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw AIUsageErrorOpenCodeGo.unreadableDatabase
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw AIUsageErrorOpenCodeGo.sqlite(message ?? "unknown error")
        }
        guard !data.isEmpty else { return [] }

        do {
            return try JSONDecoder().decode([OpenCodeGoUsageRow].self, from: data)
        } catch {
            throw AIUsageErrorOpenCodeGo.unreadableDatabase
        }
    }

    private func percent(used: Double, limit: Double) -> Double {
        guard used.isFinite && limit > 0 else { return 0 }
        return max(0, min(100, used / limit * 100))
    }

    private func startOfUTCWeek(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }

    private func monthBounds(now: Date, earliestMs: Int64?) -> (start: Date, end: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        guard let earliestMs else {
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            return (start, calendar.date(byAdding: .month, value: 1, to: start) ?? start)
        }

        let anchor = Date(timeIntervalSince1970: TimeInterval(earliestMs) / 1000)
        let anchorDay = calendar.component(.day, from: anchor)
        var current = calendar.dateComponents([.year, .month], from: now)
        var start = self.anchoredDate(calendar: calendar, month: current, day: anchorDay)
        if start > now, let previous = calendar.date(byAdding: .month, value: -1, to: start) {
            current = calendar.dateComponents([.year, .month], from: previous)
            start = self.anchoredDate(calendar: calendar, month: current, day: anchorDay)
        }
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        let nextComponents = calendar.dateComponents([.year, .month], from: nextMonth)
        return (start, self.anchoredDate(calendar: calendar, month: nextComponents, day: anchorDay))
    }

    private func anchoredDate(calendar: Calendar, month: DateComponents, day: Int) -> Date {
        var components = month
        components.day = day
        components.timeZone = calendar.timeZone
        if let date = calendar.date(from: components), calendar.component(.month, from: date) == month.month {
            return date
        }
        let monthStart = calendar.date(from: month) ?? Date()
        components.day = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 28
        return calendar.date(from: components) ?? monthStart
    }
}

public enum AIUsageErrorOpenCodeGo: LocalizedError {
    case missingCredentials
    case missingDatabase
    case unreadableDatabase
    case sqlite(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return localizedString("OpenCode Go is not connected. Connect it in OpenCode first.")
        case .missingDatabase:
            return localizedString("OpenCode usage database was not found.")
        case .unreadableDatabase:
            return localizedString("Unable to read OpenCode Go local usage.")
        case .sqlite(let message):
            return localizedString("Unable to read OpenCode Go local usage: %0", message)
        }
    }
}
