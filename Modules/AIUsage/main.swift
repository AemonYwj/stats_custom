//
//  main.swift
//  AIUsage
//

import Foundation
import Kit

public class AIUsage: Module {
    private let popupView: Popup = Popup(.aiUsage)
    private let settingsView: Settings = Settings(.aiUsage)

    private var reader: UsageReader?

    public init() {
        super.init(
            moduleType: .aiUsage,
            popup: self.popupView,
            settings: self.settingsView
        )
        guard self.available else { return }

        self.reader = UsageReader(.aiUsage) { [weak self] value in
            self?.callback(value)
        }

        self.settingsView.setInterval = { [weak self] value in
            self?.reader?.setInterval(value)
        }
        self.settingsView.callback = { [weak self] in
            guard let self, self.enabled, let reader = self.reader else { return }
            reader.stop()
            reader.start()
        }

        self.setReaders([self.reader])
    }

    private func callback(_ snapshot: AIUsageSnapshot?) {
        guard let snapshot, self.enabled else { return }

        DispatchQueue.main.async(execute: {
            self.popupView.callback(snapshot)
        })

        let primary = snapshot.primaryProvider
        guard let primary, primary.error == nil else { return }

        let remaining = primary.remainingFraction
        self.menuBar.widgets.filter{ $0.isActive }.forEach { (w: SWidget) in
            switch w.item {
            case let widget as Mini:
                widget.setValue(remaining)
            case let widget as BarChart:
                widget.setValue([[ColorValue(remaining)]])
            case let widget as Tachometer:
                widget.setValue([ColorValue(remaining)])
            case let widget as TextWidget:
                widget.setValue("\(Int((remaining*100).rounded()))%")
            default: break
            }
        }
    }
}
