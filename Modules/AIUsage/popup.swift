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
        self.alignment = .centerX
        self.spacing = Constants.Popup.spacing
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func appear() {
        self.replay(self.cache, render: self.render)
    }

    internal func callback(_ snapshot: AIUsageSnapshot) {
        self.cache.apply(snapshot, visible: self.window?.isVisible ?? false, render: self.render)
    }

    private func render(_ snapshot: AIUsageSnapshot) {
        let newIDs = Set(snapshot.providers.map { $0.providerId })
        for id in Set(self.providerViews.keys).subtracting(newIDs) {
            self.providerViews.removeValue(forKey: id)?.view.removeFromSuperview()
        }

        self.arrangedSubviews.forEach {
            self.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for provider in snapshot.providers {
            let section = self.providerViews[provider.providerId]
                ?? ProviderSection(width: self.frame.width, provider: provider)
            section.update(provider)
            self.providerViews[provider.providerId] = section
            self.addArrangedSubview(section.view)
        }

        self.layoutSubtreeIfNeeded()
        self.recalculateHeight()
    }

    private func recalculateHeight() {
        let contentHeight = self.arrangedSubviews.reduce(CGFloat(0)) { $0 + $1.frame.height }
        let spacingHeight = CGFloat(max(0, self.arrangedSubviews.count - 1)) * self.spacing
        let height = contentHeight + spacingHeight
        guard self.frame.height != height else { return }

        self.setFrameSize(NSSize(width: self.frame.width, height: height))
        self.sizeCallback?(self.frame.size)
    }
}

private final class ProviderSection {
    let view: CardBackgroundView

    private let width: CGFloat
    private let stack = NSStackView()
    private var heightConstraint: NSLayoutConstraint!

    init(width: CGFloat, provider: ProviderSnapshot) {
        self.width = width
        self.view = CardBackgroundView(frame: NSRect(x: 0, y: 0, width: width, height: 0))

        self.stack.orientation = .vertical
        self.stack.distribution = .fill
        self.stack.alignment = .leading
        self.stack.spacing = 10
        self.stack.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(self.stack)
        self.heightConstraint = self.view.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            self.view.widthAnchor.constraint(equalToConstant: width),
            self.heightConstraint,
            self.stack.leadingAnchor.constraint(
                equalTo: self.view.leadingAnchor,
                constant: Constants.Popup.margins
            ),
            self.stack.trailingAnchor.constraint(
                equalTo: self.view.trailingAnchor,
                constant: -Constants.Popup.margins
            ),
            self.stack.topAnchor.constraint(
                equalTo: self.view.topAnchor,
                constant: Constants.Popup.margins
            ),
            self.stack.bottomAnchor.constraint(
                equalTo: self.view.bottomAnchor,
                constant: -Constants.Popup.margins
            )
        ])

        self.update(provider)
    }

    func update(_ provider: ProviderSnapshot) {
        self.stack.arrangedSubviews.forEach {
            self.stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        self.addHeader(provider)

        if let error = provider.error {
            let field = NSTextField(wrappingLabelWithString: error)
            field.font = NSFont.systemFont(ofSize: 11)
            field.textColor = .systemRed
            field.maximumNumberOfLines = 2
            self.addRow(field, height: 32)
        } else {
            if let short = provider.shortWindow {
                let row = QuotaComparisonView(
                    frame: NSRect(x: 0, y: 0, width: self.contentWidth, height: 68),
                    title: localizedString("5-hour quota"),
                    window: short
                )
                self.addRow(row, height: 68)
            }

            if let weekly = provider.weeklyWindow {
                let row = QuotaComparisonView(
                    frame: NSRect(x: 0, y: 0, width: self.contentWidth, height: 68),
                    title: localizedString("Weekly quota"),
                    window: weekly
                )
                self.addRow(row, height: 68)
            }

            if let monthly = provider.monthlyWindow {
                let row = QuotaComparisonView(
                    frame: NSRect(x: 0, y: 0, width: self.contentWidth, height: 68),
                    title: localizedString("Monthly quota"),
                    window: monthly
                )
                self.addRow(row, height: 68)
            }

            if let balance = provider.balance {
                let field = self.label(
                    "\(localizedString("Balance"))  \(balance)",
                    size: 12,
                    weight: .medium,
                    color: .labelColor
                )
                self.addRow(field, height: 20)
            }
        }

        let rowHeights = self.stack.arrangedSubviews.reduce(CGFloat(0)) { $0 + $1.frame.height }
        let spacing = CGFloat(max(0, self.stack.arrangedSubviews.count - 1)) * self.stack.spacing
        let height = rowHeights + spacing + Constants.Popup.margins * 2
        self.heightConstraint.constant = height
        self.view.setFrameSize(NSSize(width: self.width, height: height))
        self.view.needsDisplay = true
    }

    private var contentWidth: CGFloat {
        self.width - Constants.Popup.margins * 2
    }

    private func addHeader(_ provider: ProviderSnapshot) {
        let header = NSStackView(frame: NSRect(x: 0, y: 0, width: self.contentWidth, height: 28))
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6

        let title = self.label(provider.providerName, size: 13, weight: .semibold, color: .labelColor)
        header.addArrangedSubview(title)

        if let plan = provider.plan, !plan.isEmpty {
            let planField = self.label(plan, size: 11, weight: .regular, color: .secondaryLabelColor)
            header.addArrangedSubview(planField)
        }

        header.addArrangedSubview(NSView())

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let timestamp = self.label(
            formatter.string(from: provider.updatedAt),
            size: 10,
            weight: .regular,
            color: .tertiaryLabelColor
        )
        header.addArrangedSubview(timestamp)

        self.addRow(header, height: 28)
    }

    private func addRow(_ row: NSView, height: CGFloat) {
        row.translatesAutoresizingMaskIntoConstraints = false
        row.setFrameSize(NSSize(width: self.contentWidth, height: height))
        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: self.contentWidth),
            row.heightAnchor.constraint(equalToConstant: height)
        ])
        self.stack.addArrangedSubview(row)
    }

    private func label(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight,
        color: NSColor
    ) -> NSTextField {
        let field = TextView()
        field.stringValue = text
        field.font = NSFont.systemFont(ofSize: size, weight: weight)
        field.textColor = color
        return field
    }
}

private final class CardBackgroundView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        self.layer?.cornerRadius = Constants.Popup.radius
        self.layer?.borderWidth = 0.5
        self.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        self.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor
    }
}

private final class QuotaComparisonView: NSView {
    private let title: String
    private let rateWindow: AIRateWindow

    override var isFlipped: Bool { true }

    init(frame: NSRect, title: String, window: AIRateWindow) {
        self.title = title
        self.rateWindow = window
        super.init(frame: frame)
        self.setAccessibilityElement(true)
        self.setAccessibilityLabel(title)
        self.setAccessibilityValue("\(Int(window.remainingPercent.rounded()))%")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let remaining = self.rateWindow.remainingFraction
        let timeRemaining = 1 - (self.rateWindow.elapsedFraction() ?? 1)
        let quotaColor: NSColor = remaining + 0.05 < timeRemaining ? .systemOrange : .controlAccentColor
        let timeColor = NSColor.systemTeal

        self.drawText(
            self.title,
            at: NSPoint(x: 0, y: 0),
            font: .systemFont(ofSize: 11, weight: .semibold),
            color: .labelColor
        )

        let countdown = self.countdown()
        self.drawRightAlignedText(
            countdown,
            y: 1,
            font: .monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            color: .secondaryLabelColor
        )

        self.drawProgressRow(
            label: localizedString("Quota remaining"),
            fraction: remaining,
            y: 25,
            color: quotaColor
        )
        self.drawProgressRow(
            label: localizedString("Time remaining"),
            fraction: timeRemaining,
            y: 48,
            color: timeColor
        )
    }

    private func drawProgressRow(label: String, fraction: Double, y: CGFloat, color: NSColor) {
        let labelWidth: CGFloat = 72
        let valueWidth: CGFloat = 32
        let barX = labelWidth
        let barWidth = max(0, self.bounds.width - labelWidth - valueWidth - 7)

        self.drawText(
            label,
            at: NSPoint(x: 0, y: y - 4),
            font: .systemFont(ofSize: 10),
            color: .secondaryLabelColor
        )

        let track = NSBezierPath(
            roundedRect: NSRect(x: barX, y: y, width: barWidth, height: 7),
            xRadius: 3.5,
            yRadius: 3.5
        )
        NSColor.quaternaryLabelColor.withAlphaComponent(0.35).setFill()
        track.fill()

        if fraction > 0 {
            let fill = NSBezierPath(
                roundedRect: NSRect(
                    x: barX,
                    y: y,
                    width: max(7, barWidth * CGFloat(min(1, max(0, fraction)))),
                    height: 7
                ),
                xRadius: 3.5,
                yRadius: 3.5
            )
            color.setFill()
            fill.fill()
        }

        self.drawRightAlignedText(
            "\(Int((fraction * 100).rounded()))%",
            y: y - 4,
            font: .monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            color: color
        )
    }

    private func countdown() -> String {
        guard let reset = self.rateWindow.resetsAt else { return "" }
        let interval = max(0, Int(reset.timeIntervalSinceNow))
        let days = interval / 86_400
        let hours = (interval % 86_400) / 3_600
        let minutes = (interval % 3_600) / 60

        let value: String
        if days > 0 {
            value = "\(days)\(localizedString("d")) \(hours)\(localizedString("h"))"
        } else if hours > 0 {
            value = "\(hours)\(localizedString("h")) \(minutes)\(localizedString("m"))"
        } else {
            value = "\(minutes)\(localizedString("m"))"
        }
        return localizedString("resets in", value)
    }

    private func drawText(_ text: String, at point: NSPoint, font: NSFont, color: NSColor) {
        guard !text.isEmpty else { return }
        (text as NSString).draw(
            at: point,
            withAttributes: [
                .font: font,
                .foregroundColor: color
            ]
        )
    }

    private func drawRightAlignedText(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
        guard !text.isEmpty else { return }
        let width = text.widthOfString(usingFont: font)
        self.drawText(
            text,
            at: NSPoint(x: self.bounds.width - width, y: y),
            font: font,
            color: color
        )
    }
}
