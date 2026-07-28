//
//  popup.swift
//  AIUsage
//

import Cocoa
import Kit

internal class Popup: PopupWrapper {
    private let detailsHeight: CGFloat = (22*4) + (Constants.Popup.margins*2)

    private let cache = PopupCache<AIUsageSnapshot>()

    private var planField: NSTextField = TextView()
    private var weeklyField: NSTextField = TextView()
    private var shortField: NSTextField = TextView()
    private var updatedField: NSTextField = TextView()

    public init(_ module: ModuleType) {
        super.init(module, frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))

        self.orientation = .vertical
        self.distribution = .fill
        self.spacing = 0

        self.addArrangedSubview(self.initDetails())

        self.recalculateHeight()
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

    private func initDetails() -> NSView {
        let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.detailsHeight))
        view.heightAnchor.constraint(equalToConstant: self.detailsHeight).isActive = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.distribution = .fillEqually
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        self.planField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        self.weeklyField.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        self.shortField.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        self.updatedField.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        self.updatedField.textColor = .secondaryLabelColor

        stack.addArrangedSubview(self.planField)
        stack.addArrangedSubview(self.weeklyField)
        stack.addArrangedSubview(self.shortField)
        stack.addArrangedSubview(self.updatedField)

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.Popup.margins),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Popup.margins),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: Constants.Popup.margins),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Constants.Popup.margins)
        ])

        return view
    }

    internal func callback(_ snapshot: AIUsageSnapshot) {
        self.cache.apply(snapshot, visible: self.window?.isVisible ?? false, render: self.render)
    }

    private func render(_ snapshot: AIUsageSnapshot) {
        self.planField.stringValue = snapshot.plan.map { "\(snapshot.provider) \($0)" } ?? snapshot.provider

        if let error = snapshot.error {
            self.weeklyField.stringValue = localizedString("Weekly quota") + ": --"
            self.shortField.stringValue = localizedString("Session quota") + ": --"
            self.updatedField.textColor = .systemRed
            self.updatedField.stringValue = error
            return
        }

        self.weeklyField.stringValue = self.format(localizedString("Weekly quota"), window: snapshot.weeklyWindow)
        self.shortField.stringValue = self.format(localizedString("Session quota"), window: snapshot.shortWindow)

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        self.updatedField.textColor = .secondaryLabelColor
        self.updatedField.stringValue = localizedString("Updated at", formatter.string(from: snapshot.updatedAt))
    }

    private func format(_ title: String, window: AIRateWindow?) -> String {
        guard let window else { return "\(title): --" }

        let remaining = Int(window.remainingPercent.rounded())
        guard let reset = window.resetsAt else {
            return "\(title): \(remaining)%"
        }

        let interval = max(0, Int(reset.timeIntervalSinceNow))
        let days = interval / 86_400
        let hours = (interval % 86_400) / 3_600
        let minutes = (interval % 3_600) / 60

        let countdown: String
        if days > 0 {
            countdown = localizedString("resets in", "\(days)\(localizedString("d")) \(hours)\(localizedString("h"))")
        } else if hours > 0 {
            countdown = localizedString("resets in", "\(hours)\(localizedString("h")) \(minutes)\(localizedString("m"))")
        } else {
            countdown = localizedString("resets in", "\(minutes)\(localizedString("m"))")
        }

        return "\(title): \(remaining)% · \(countdown)"
    }
}
