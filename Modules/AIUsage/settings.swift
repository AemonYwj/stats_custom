//
//  settings.swift
//  AIUsage
//

import Cocoa
import Kit

internal class Settings: NSStackView, Settings_v {
    private var updateIntervalValue: Int = 300
    private var provider: String = "codex"

    private let title: String

    public var callback: (() -> Void) = {}
    public var setInterval: ((_ value: Int) -> Void) = {_ in }

    public init(_ module: ModuleType) {
        self.title = module.stringValue
        self.updateIntervalValue = Store.shared.int(key: "\(self.title)_updateInterval", defaultValue: self.updateIntervalValue)
        self.provider = Store.shared.string(key: "\(self.title)_provider", defaultValue: self.provider)

        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: 0))

        self.wantsLayer = true
        self.orientation = .vertical
        self.distribution = .gravityAreas
        self.spacing = Constants.Settings.margin
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func load(widgets: [widget_t]) {
        self.subviews.forEach{ $0.removeFromSuperview() }

        self.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Provider"), component: selectView(
                action: #selector(self.changeProvider),
                items: AIUsageProviders.all.map { KeyValue_t(key: $0.id, value: $0.displayName) },
                selected: self.provider
            )),
            PreferencesRow(localizedString("Update interval"), component: selectView(
                action: #selector(self.changeUpdateInterval),
                items: AIUsageUpdateIntervals,
                selected: "\(self.updateIntervalValue)"
            ))
        ]))

        self.addArrangedSubview(PreferencesSection([
            PreferencesRow(
                localizedString("Privacy"),
                localizedString("AIUsage reads the local Codex CLI credentials and only sends requests to the official chatgpt.com quota endpoint."),
                component: NSView()
            )
        ]))
    }

    @objc private func changeProvider(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.provider = key
        Store.shared.set(key: "\(self.title)_provider", value: key)
        self.callback()
    }
    @objc private func changeUpdateInterval(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let value = Int(key) else { return }
        self.updateIntervalValue = value
        Store.shared.set(key: "\(self.title)_updateInterval", value: value)
        self.setInterval(value)
    }
}
