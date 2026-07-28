//
//  popup.swift
//  AIUsage
//

import Cocoa
import Kit

internal class Popup: PopupWrapper {
    private let cache = PopupCache<AIUsageSnapshot>()
    private var providerViews: [String: ProviderSection] = [:]

    public init(_ module: ModuleType) {
        super.init(module, frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))
        self.orientation = .vertical
        self.distribution = .fill
        self.spacing = 0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func appear() {
        self.replay(self.cache, render: self.render)
    }

    private func recalculateHeight() {
        let h = self.arrangedSubviews.map({ $0.bounds.height + self.spacing }).reduce(0, +) - self.spacing
        if self.frame.size.height != h {
            self.setFrameSize(NSSize(width: self.frame.width, height: h))
            self.sizeCallback?(self.frame.size)
        }
    }

    internal func callback(_ snapshot: AIUsageSnapshot) {
        self.cache.apply(snapshot, visible: self.window?.isVisible ?? false, render: self.render)
    }

    private func render(_ snapshot: AIUsageSnapshot) {
        let existingIDs = Set(self.providerViews.keys)
        let newIDs = Set(snapshot.providers.map { $0.providerId })

        for id in existingIDs.subtracting(newIDs) {
            self.providerViews.removeValue(forKey: id)?.view.removeFromSuperview()
        }

        for (i, provider) in snapshot.providers.enumerated() {
            let section: ProviderSection
            if let existing = self.providerViews[provider.providerId] {
                section = existing
                if section.view.superview == nil {
                    if i > 0, let prev = self.providerViews[snapshot.providers[i-1].providerId] {
                        self.insertArrangedSubview(section.view, at: self.arrangedSubviews.firstIndex(of: prev.view)! + 1)
                    } else {
                        self.insertArrangedSubview(section.view, at: 0)
                    }
                }
                section.update(provider)
            } else {
                section = ProviderSection(width: self.frame.width, provider: provider)
                self.providerViews[provider.providerId] = section
                self.addArrangedSubview(section.view)
            }
        }

        self.recalculateHeight()
    }
}

private class ProviderSection {
    let view: NSView

    private let planField: NSTextField = TextView()
    private let weeklyField: NSTextField = TextView()
    private let shortField: NSTextField = TextView()
    private let balanceField: NSTextField = TextView()
    private let errorField: NSTextField = TextView()
    private let timestampField: NSTextField = TextView()

    private let sectionHeight: CGFloat = (22 * 4) + (Constants.Popup.margins * 2)

    init(width: CGFloat, provider: ProviderSnapshot) {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: self.sectionHeight))
        self.view.heightAnchor.constraint(equalToConstant: self.sectionHeight).isActive = true
        self.view.wantsLayer = true
        self.view.layer?.cornerRadius = Constants.Popup.radius

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.distribution = .fillEqually
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        self.planField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        self.weeklyField.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        self.shortField.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        self.balanceField.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        self.errorField.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        self.errorField.textColor = .systemRed
        self.timestampField.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        self.timestampField.textColor = .secondaryLabelColor
        self.timestampField.alignment = .right

        stack.addArrangedSubview(self.planField)
        stack.addArrangedSubview(self.weeklyField)
        stack.addArrangedSubview(self.shortField)
        stack.addArrangedSubview(self.balanceField)

        let footerStack = NSStackView()
        footerStack.orientation = .horizontal
        footerStack.spacing = 0
        footerStack.addArrangedSubview(self.errorField)
        footerStack.addArrangedSubview(NSView())
        footerStack.addArrangedSubview(self.timestampField)
        stack.addArrangedSubview(footerStack)

        self.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: Constants.Popup.margins),
            stack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -Constants.Popup.margins),
            stack.topAnchor.constraint(equalTo: self.view.topAnchor, constant: Constants.Popup.margins),
            stack.bottomAnchor.constraint(equalTo: self.view.bottomAnchor, constant: -Constants.Popup.margins)
        ])

        self.update(provider)
    }

    func update(_ provider: ProviderSnapshot) {
        self.planField.stringValue = provider.plan.map { "\(provider.providerName) \($0)" } ?? provider.providerName

        self.weeklyField.stringValue = format(localizedString("Weekly quota"), window: provider.weeklyWindow)
        self.weeklyField.isHidden = provider.weeklyWindow == nil

        self.shortField.stringValue = format(localizedString("Session quota"), window: provider.shortWindow)
        self.shortField.isHidden = provider.shortWindow == nil

        if let balance = provider.balance {
            self.balanceField.stringValue = "\(localizedString("Balance")): \(balance)"
            self.balanceField.isHidden = false
        } else {
            self.balanceField.isHidden = true
        }

        if let error = provider.error {
            self.errorField.stringValue = error
            self.errorField.isHidden = false
        } else {
            self.errorField.isHidden = true
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        self.timestampField.stringValue = formatter.string(from: provider.updatedAt)
    }

    private func format(_ title: String, window: AIRateWindow?) -> String {
        guard let window else { return "" }
        let remaining = Int(window.remainingPercent.rounded())
        guard let reset = window.resetsAt else { return "\(title): \(remaining)%" }

        let interval = max(0, Int(reset.timeIntervalSinceNow))
        let days = interval / 86_400
        let hours = (interval % 86_400) / 3_600
        let minutes = (interval % 3_600) / 60

        let countdown: String
        if days > 0 {
            countdown = "\(days)\(localizedString("d")) \(hours)\(localizedString("h"))"
        } else if hours > 0 {
            countdown = "\(hours)\(localizedString("h")) \(minutes)\(localizedString("m"))"
        } else {
            countdown = "\(minutes)\(localizedString("m"))"
        }

        return "\(title): \(remaining)% · \(localizedString("resets in", countdown))"
    }
}
