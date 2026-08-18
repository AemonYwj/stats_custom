//
//  settings.swift
//  AIUsage
//

import Cocoa
import Kit

internal class Settings: NSStackView, Settings_v, NSTextFieldDelegate {
    private var updateIntervalValue: Int = 300

    private let title: String

    public var callback: (() -> Void) = {}
    public var setInterval: ((_ value: Int) -> Void) = {_ in }

    private let providers = AIUsageProviders.all
    private var apiKeyFields: [String: NSSecureTextField] = [:]

    public init(_ module: ModuleType) {
        self.title = module.stringValue
        self.updateIntervalValue = Store.shared.int(key: "\(self.title)_updateInterval", defaultValue: self.updateIntervalValue)

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
        self.apiKeyFields.removeAll()

        self.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Update interval"), component: selectView(
                action: #selector(self.changeUpdateInterval),
                items: AIUsageUpdateIntervals,
                selected: "\(self.updateIntervalValue)"
            )),
            PreferencesRow(localizedString("Menu bar display"), component: selectView(
                action: #selector(self.changeMenuBarMetric),
                items: AIUsageMenuBarMetrics,
                selected: AIUsageProviders.menuBarMetric.rawValue
            ))
        ]))

        for provider in self.providers {
            var rows: [NSView] = []

            let toggle = switchView(
                action: #selector(self.toggleProvider(_:)),
                state: AIUsageProviders.isEnabled(provider.id)
            )
            toggle.identifier = NSUserInterfaceItemIdentifier(provider.id)

            rows.append(PreferencesRow(
                provider.displayName,
                component: toggle
            ))

            if provider.requiresAPIKey {
                let field = NSSecureTextField()
                field.placeholderString = localizedString("API Key")
                field.stringValue = AIUsageProviders.apiKey(for: provider.id) ?? ""
                field.widthAnchor.constraint(equalToConstant: 180).isActive = true
                field.font = NSFont.systemFont(ofSize: 11)
                field.target = self
                field.action = #selector(self.apiKeyChanged(_:))
                field.delegate = self
                field.identifier = NSUserInterfaceItemIdentifier(provider.id)
                self.apiKeyFields[provider.id] = field
                rows.append(PreferencesRow(component: field))
            }

            self.addArrangedSubview(PreferencesSection(rows))
        }

        self.addArrangedSubview(PreferencesSection([
            PreferencesRow(
                localizedString("Privacy"),
                localizedString("AIUsage reads local CLI credentials and only sends requests to the official provider endpoints."),
                component: NSView()
            )
        ]))
    }

    @objc private func changeUpdateInterval(_ sender: NSPopUpButton) {
        guard let key = sender.selectedItem?.representedObject as? String, let value = Int(key) else { return }
        self.updateIntervalValue = value
        Store.shared.set(key: "\(self.title)_updateInterval", value: value)
        self.setInterval(value)
    }

    @objc private func changeMenuBarMetric(_ sender: NSPopUpButton) {
        guard let key = sender.selectedItem?.representedObject as? String,
              let metric = AIUsageMenuBarMetric(rawValue: key) else { return }
        AIUsageProviders.setMenuBarMetric(metric)
        self.callback()
    }

    @objc private func toggleProvider(_ sender: NSControl) {
        guard let id = sender.identifier?.rawValue,
              let provider = self.providers.first(where: { $0.id == id }) else { return }
        self.saveAPIKeys()
        AIUsageProviders.setEnabled(controlState(sender), for: provider.id)
        self.callback()
    }

    @objc private func apiKeyChanged(_ sender: NSSecureTextField) {
        guard let id = sender.identifier?.rawValue else { return }
        AIUsageProviders.setAPIKey(sender.stringValue, for: id)
        if AIUsageProviders.isEnabled(id) {
            self.callback()
        }
    }

    public func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSecureTextField,
              let id = field.identifier?.rawValue else { return }
        AIUsageProviders.setAPIKey(field.stringValue, for: id)
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSSecureTextField else { return }
        self.apiKeyChanged(field)
    }

    private func saveAPIKeys() {
        self.apiKeyFields.forEach { id, field in
            AIUsageProviders.setAPIKey(field.stringValue, for: id)
        }
    }
}
