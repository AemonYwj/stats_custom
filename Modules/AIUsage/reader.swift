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
        let providers = AIUsageProviders.enabledProviders()
        guard !providers.isEmpty else {
            self.callback(AIUsageSnapshot(providers: [], updatedAt: Date()))
            return
        }

        self.task?.cancel()
        self.task = Task { [weak self] in
            guard let self else { return }

            var results: [ProviderSnapshot] = []
            for provider in providers {
                guard !Task.isCancelled else { return }
                do {
                    let apiKey = AIUsageProviders.apiKey(for: provider.id)
                    let snapshot = try await provider.fetch(apiKey: apiKey)
                    results.append(snapshot)
                } catch {
                    guard !Task.isCancelled else { return }
                    debug("AI Usage [\(provider.id)]: \(error.localizedDescription)", log: self.log)
                    results.append(ProviderSnapshot(
                        providerId: provider.id,
                        providerName: provider.displayName,
                        error: error.localizedDescription
                    ))
                }
            }

            guard !Task.isCancelled else { return }
            self.callback(AIUsageSnapshot(providers: results, updatedAt: Date()))
        }
    }

    public override func terminate() {
        self.task?.cancel()
    }

    deinit {
        self.task?.cancel()
    }
}
