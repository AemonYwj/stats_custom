//
//  reader.swift
//  AIUsage
//

import Foundation
import Kit

internal class UsageReader: Reader<AIUsageSnapshot> {
    private var task: Task<Void, Never>?

    public override func setup() {
        self.defaultInterval = 300
    }

    public override func read() {
        self.task?.cancel()
        self.task = Task { [weak self] in
            guard let self else { return }
            let provider = AIUsageProviders.active
            do {
                let snapshot = try await provider.fetch()
                guard !Task.isCancelled else { return }
                self.callback(snapshot)
            } catch {
                guard !Task.isCancelled else { return }
                debug("AI Usage fetch failed: \(error.localizedDescription)", log: self.log)
                self.callback(AIUsageSnapshot(
                    provider: provider.displayName,
                    error: error.localizedDescription
                ))
            }
        }
    }

    public override func terminate() {
        self.task?.cancel()
    }

    deinit {
        self.task?.cancel()
    }
}
