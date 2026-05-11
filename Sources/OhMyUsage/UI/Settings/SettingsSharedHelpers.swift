import AppKit
import SwiftUI

enum SettingsThresholdValueStyle {
    case percent
    case number

    var suffix: String? {
        switch self {
        case .percent:
            return "%"
        case .number:
            return nil
        }
    }

    func displayText(for value: Double) -> String {
        switch self {
        case .percent:
            return "\(Int(round(value)))"
        case .number:
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 0
            return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        }
    }

    func parse(_ text: String) -> Double? {
        var normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: " ", with: "")

        switch self {
        case .percent:
            normalized = normalized.replacingOccurrences(of: ",", with: ".")
        case .number:
            normalized = normalized.replacingOccurrences(of: ",", with: "")
        }
        return Double(normalized)
    }
}

struct SettingsCompactThresholdSlider: NSViewRepresentable {
    @Binding var value: Double
    var onEditingChanged: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> SliderView {
        let slider = SliderView()
        configure(slider)
        return slider
    }

    func updateNSView(_ nsView: SliderView, context: Context) {
        configure(nsView)
    }

    private func configure(_ slider: SliderView) {
        slider.value = min(max(value, 0), 100)
        slider.onValueChanged = { newValue in
            value = newValue
        }
        slider.onEditingChanged = onEditingChanged
    }

    final class SliderView: NSView {
        var value: Double = 0 {
            didSet { needsDisplay = true }
        }
        var onValueChanged: (Double) -> Void = { _ in }
        var onEditingChanged: (Bool) -> Void = { _ in }

        private var isEditing = false

        override var isFlipped: Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: 20)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)

            let width = max(bounds.width, 1)
            let clampedValue = min(max(value, 0), 100)
            let fillWidth = width * CGFloat(clampedValue / 100)
            let trackHeight: CGFloat = 4
            let trackY = (bounds.height - trackHeight) / 2
            let trackRect = NSRect(x: 0, y: trackY, width: width, height: trackHeight)

            NSColor(calibratedWhite: 1, alpha: 0.15).setFill()
            NSBezierPath(
                roundedRect: trackRect,
                xRadius: trackHeight / 2,
                yRadius: trackHeight / 2
            ).fill()

            let fillRect = NSRect(x: 0, y: trackY, width: max(0, fillWidth), height: trackHeight)
            NSColor(calibratedWhite: 1, alpha: 0.80).setFill()
            NSBezierPath(
                roundedRect: fillRect,
                xRadius: trackHeight / 2,
                yRadius: trackHeight / 2
            ).fill()

            let thumbSize = NSSize(width: 32, height: 20)
            let thumbX = min(max(fillWidth - thumbSize.width / 2, 0), max(width - thumbSize.width, 0))
            let thumbRect = NSRect(
                x: thumbX,
                y: (bounds.height - thumbSize.height) / 2,
                width: thumbSize.width,
                height: thumbSize.height
            )
            NSColor(
                calibratedRed: 208 / 255,
                green: 208 / 255,
                blue: 208 / 255,
                alpha: 1
            ).setFill()
            NSBezierPath(
                roundedRect: thumbRect,
                xRadius: thumbSize.height / 2,
                yRadius: thumbSize.height / 2
            ).fill()
        }

        override func mouseDown(with event: NSEvent) {
            beginEditingIfNeeded()
            updateValue(with: event)
        }

        override func mouseDragged(with event: NSEvent) {
            updateValue(with: event)
        }

        override func mouseUp(with event: NSEvent) {
            updateValue(with: event)
            endEditingIfNeeded()
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil {
                endEditingIfNeeded()
            }
            super.viewWillMove(toWindow: newWindow)
        }

        private func updateValue(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            let nextValue = min(max(Double(point.x / max(bounds.width, 1)) * 100, 0), 100)
            value = nextValue
            onValueChanged(nextValue)
        }

        private func beginEditingIfNeeded() {
            guard !isEditing else { return }
            isEditing = true
            onEditingChanged(true)
        }

        private func endEditingIfNeeded() {
            guard isEditing else { return }
            isEditing = false
            onEditingChanged(false)
        }
    }
}

struct SettingsThresholdControlRowSlider: NSViewRepresentable {
    @Binding var value: Double
    var onEditingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, onEditingChanged: onEditingChanged)
    }

    func makeNSView(context: Context) -> SliderView {
        let slider = SliderView(
            value: min(max(value, 0), 100),
            minValue: 0,
            maxValue: 100,
            target: context.coordinator,
            action: #selector(Coordinator.valueChanged(_:))
        )
        slider.isContinuous = true
        slider.controlSize = .small
        slider.trackFillColor = NSColor(calibratedWhite: 1, alpha: 0.80)
        slider.onEditingChanged = { [weak coordinator = context.coordinator] editing in
            coordinator?.onEditingChanged(editing)
        }
        return slider
    }

    func updateNSView(_ nsView: SliderView, context: Context) {
        context.coordinator.value = $value
        context.coordinator.onEditingChanged = onEditingChanged
        let clampedValue = min(max(value, 0), 100)
        if abs(nsView.doubleValue - clampedValue) > 0.0001 {
            nsView.doubleValue = clampedValue
        }
        nsView.onEditingChanged = { [weak coordinator = context.coordinator] editing in
            coordinator?.onEditingChanged(editing)
        }
    }

    final class Coordinator: NSObject {
        var value: Binding<Double>
        var onEditingChanged: (Bool) -> Void

        init(value: Binding<Double>, onEditingChanged: @escaping (Bool) -> Void) {
            self.value = value
            self.onEditingChanged = onEditingChanged
        }

        @MainActor @objc func valueChanged(_ sender: NSSlider) {
            value.wrappedValue = min(max(sender.doubleValue, 0), 100)
        }
    }

    final class SliderView: NSSlider {
        var onEditingChanged: (Bool) -> Void = { _ in }

        override var mouseDownCanMoveWindow: Bool { false }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            onEditingChanged(true)
            defer { onEditingChanged(false) }
            super.mouseDown(with: event)
        }
    }
}

struct SettingsThresholdValueField: View {
    @Binding var value: Double
    var style: SettingsThresholdValueStyle
    var displayTextOverride: String? = nil
    var step: Double = 1
    var range: ClosedRange<Double> = 0...100
    var onValueCommit: ((Double) -> Void)? = nil
    var onEditingChanged: (Bool) -> Void

    @FocusState private var isFocused: Bool
    @State private var draftText = ""

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 1) {
                TextField("", text: $draftText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.80))
                    .lineLimit(1)
                    .frame(width: textFieldWidth, alignment: .leading)
                    .focused($isFocused)
                    .onSubmit {
                        applyDraft()
                        isFocused = false
                    }

                if let suffix = style.suffix {
                    Text(suffix)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.80))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                Button {
                    adjust(by: step)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.40))
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)

                Button {
                    adjust(by: -step)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.40))
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(width: 80, height: 28, alignment: .leading)
        .background(
            SettingsSmoothedRoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.15))
        )
        .onAppear(perform: syncDraftText)
        .onChange(of: value) { _, _ in
            if !isFocused {
                syncDraftText()
            }
        }
        .onChange(of: displayTextOverride) { _, _ in
            if !isFocused {
                syncDraftText()
            }
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                onEditingChanged(true)
                draftText = style.displayText(for: value)
            } else {
                applyDraft()
            }
        }
        .onDisappear {
            applyDraft()
        }
    }

    private func syncDraftText() {
        draftText = displayTextOverride ?? style.displayText(for: value)
    }

    private func adjust(by delta: Double) {
        let base = style.parse(draftText) ?? value
        let nextValue = clamped(base + delta)
        onEditingChanged(true)
        commitValue(nextValue)
    }

    private func applyDraft() {
        guard let parsedValue = style.parse(draftText) else {
            syncDraftText()
            onEditingChanged(false)
            return
        }
        let nextValue = clamped(parsedValue)
        commitValue(nextValue)
    }

    private func commitValue(_ nextValue: Double) {
        value = nextValue
        draftText = style.displayText(for: nextValue)
        onValueCommit?(nextValue)
        onEditingChanged(false)
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private var textFieldWidth: CGFloat? {
        guard style.suffix != nil else { return nil }
        let measuredText = draftText.isEmpty ? "0" : draftText
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let width = (measuredText as NSString).size(withAttributes: [.font: font]).width
        return min(max(ceil(width) + 4, 12), 44)
    }
}

extension SettingsView {
    struct SettingsCompactRecordMetric: Identifiable {
        var id: String
        var title: String
        var valueText: String
        var resetText: String?
    }

    struct SettingsCompactRecordAction: Identifiable {
        var id: String
        var title: String
        var destructive: Bool = false
        var action: () -> Void
    }

    func settingsCompactSection<Actions: View, Content: View>(
        title: String,
        spacing: CGFloat = 12,
        headerWidth: CGFloat = 566,
        headerHeight: CGFloat = 22,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack(alignment: .center) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(settingsBodyColor)

                Spacer(minLength: 0)

                actions()
            }
            .frame(width: headerWidth, height: headerHeight, alignment: .center)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    func settingsConfigurationSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.80))
                .frame(width: 566, height: 12, alignment: .leading)

            settingsOutlineCard(
                padding: 0,
                cornerRadius: 8,
                strokeOpacity: 0.15,
                content: content
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    func settingsConfigurationRows<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            content()
        }
        .padding(.top, 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    func settingsConfigRow<Content: View>(
        title: String,
        nested: Bool = false,
        rowHeight: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let labelWidth = nested ? settingsNestedConfigLabelWidth : thirdPartyConfigLabelWidth
        let leadingOffset = nested ? thirdPartyConfigLabelWidth - labelWidth : 0

        return HStack(alignment: .center, spacing: thirdPartyConfigLabelSpacing) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.80))
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .trailing)

            content()
        }
        .padding(.leading, leadingOffset)
        .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .leading)
    }

    func settingsConfigToggleRow(
        title: String,
        isOn: Binding<Bool>
    ) -> some View {
        settingsConfigRow(title: title) {
            SettingsToggleSwitch(
                isOn: isOn,
                offTrackColor: Color.white.opacity(0.15),
                onTrackColor: Color.white.opacity(0.40),
                knobColor: Color.white.opacity(0.88)
            )
        }
    }

    func settingsConfigSegmentedControl<ID: Hashable>(
        options: [SettingsPillSegmentOption<ID>],
        selection: ID,
        width: CGFloat,
        segmentWidths: [ID: CGFloat]? = nil,
        onSelect: @escaping (ID) -> Void
    ) -> some View {
        SettingsPillSegmentedControl(
            options: options,
            selection: selection,
            backgroundColor: Color.white.opacity(0.15),
            selectedFillColor: Color.white.opacity(0.80),
            selectedTextColor: Color.black.opacity(0.88),
            textColor: Color.white.opacity(0.80),
            segmentWidths: segmentWidths,
            onSelect: onSelect
        )
        .frame(width: width, height: 24)
    }

    func settingsConfigSecureField(
        _ placeholder: String,
        text: Binding<String>
    ) -> some View {
        SecureField("", text: text, prompt: Text(placeholder)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.white.opacity(0.40)))
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.white.opacity(0.80))
            .padding(.horizontal, 8)
            .frame(width: thirdPartyConfigControlWidth, height: 24)
            .background(
                SettingsSmoothedRoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.15))
            )
    }

    func settingsConfigTextField(
        _ placeholder: String,
        text: Binding<String>
    ) -> some View {
        TextField("", text: text, prompt: Text(placeholder)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.white.opacity(0.40)))
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.white.opacity(0.80))
            .padding(.horizontal, 8)
            .frame(width: thirdPartyConfigControlWidth, height: 24)
            .background(
                SettingsSmoothedRoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.15))
            )
    }

    func settingsConfigThresholdRow(
        title: String,
        value: Binding<Double>,
        valueStyle: SettingsThresholdValueStyle = .percent,
        displayTextOverride: String? = nil,
        onValueCommit: ((Double) -> Void)? = nil,
        onEditingChanged: @escaping (Bool) -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.80))
                .lineLimit(1)
                .frame(width: thirdPartyConfigLabelWidth, alignment: .trailing)

            Spacer()
                .frame(width: thirdPartyConfigLabelSpacing)

            SettingsCompactThresholdSlider(
                value: value,
                onEditingChanged: onEditingChanged
            )
            .frame(width: thirdPartyConfigSliderWidth, height: 20)

            Spacer(minLength: 16)

            SettingsThresholdValueField(
                value: value,
                style: valueStyle,
                displayTextOverride: displayTextOverride,
                onValueCommit: onValueCommit,
                onEditingChanged: onEditingChanged
            )
        }
        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .leading)
    }

    func settingsConfigThresholdStaticRow(
        title: String,
        value: Double,
        displayText: String,
        valueStyle: SettingsThresholdValueStyle = .number
    ) -> some View {
        settingsConfigThresholdRow(
            title: title,
            value: .constant(value),
            valueStyle: valueStyle,
            displayTextOverride: displayText,
            onEditingChanged: { _ in }
        )
        .allowsHitTesting(false)
    }

    func settingsOutlineCard<Content: View>(
        padding: CGFloat = 24,
        cornerRadius: CGFloat = 12,
        strokeOpacity: Double = 0.12,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(padding)
        .background(
            SettingsSmoothedRoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.clear)
        )
        .overlay(
            SettingsSmoothedRoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white.opacity(strokeOpacity), lineWidth: 1)
        )
    }

    func settingsSmallOutlineButton(
        _ title: String,
        width: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.80))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(minWidth: width)
                .frame(height: 22)
                .background(Color.clear)
                .overlay(
                    SettingsSmoothedRoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.80), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    func settingsCompactRecordRow(
        title: String,
        currentText: String? = nil,
        statusText: String,
        statusColor: Color,
        errorText: String? = nil,
        metrics: [SettingsCompactRecordMetric],
        actions: [SettingsCompactRecordAction]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.80))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let currentText, !currentText.isEmpty {
                    Text(currentText)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color(hex: 0x69BD65))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(statusText)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            .frame(height: 12)

            if let errorText, !errorText.isEmpty {
                Text(errorText)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color(hex: 0xD05858))
                    .lineSpacing(3)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .center, spacing: 12) {
                settingsCompactRecordMetricsLine(metrics)

                Spacer(minLength: 0)

                ForEach(actions) { action in
                    settingsCompactRecordTextActionButton(
                        action.title,
                        destructive: action.destructive,
                        action: action.action
                    )
                }
            }
            .frame(height: 10)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    func settingsCompactRecordMetricsLine(
        _ metrics: [SettingsCompactRecordMetric],
        firstColumnWidth: CGFloat? = nil,
        columnSpacing: CGFloat = 24
    ) -> some View {
        HStack(spacing: columnSpacing) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                settingsCompactRecordMetricView(metric)
                    .frame(width: index == 0 ? firstColumnWidth : nil, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    func settingsCompactRecordMetricView(_ metric: SettingsCompactRecordMetric) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(metric.title)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)

                Text(metric.valueText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.80))
                    .lineLimit(1)
            }

            if let resetText = metric.resetText, !resetText.isEmpty {
                HStack(spacing: 2) {
                    if let image = bundledImage(named: "menu_reset_clock_icon") {
                        Image(nsImage: image)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 10, height: 10)
                            .foregroundStyle(Color.white.opacity(0.40))
                    } else {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.40))
                            .frame(width: 10, height: 10)
                    }

                    Text(resetText)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.40))
                        .lineLimit(1)
                }
            }
        }
    }

    func settingsCompactRecordTextActionButton(
        _ title: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(destructive ? Color(hex: 0xD05858) : Color.white.opacity(0.55))
                .lineLimit(1)
                .frame(height: 10, alignment: .center)
        }
        .buttonStyle(.plain)
    }

    func settingsCapsuleButton(
        _ title: String,
        destructive: Bool = false,
        disabled: Bool = false,
        dismissInputFocus: Bool = false,
        textOpacity: Double = 0.80,
        borderOpacity: Double = 0.55,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            if dismissInputFocus {
                dismissEditingFocus()
            }
            action()
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(
                    destructive
                        ? Color(hex: 0xEB654F).opacity(disabled ? 0.38 : textOpacity)
                        : Color.white.opacity(disabled ? 0.38 : textOpacity)
                )
                .padding(.horizontal, 16)
                .frame(height: 24)
                .background(Color.clear)
                .overlay(
                    SettingsSmoothedRoundedRectangle(cornerRadius: 12)
                        .stroke(
                            destructive
                                ? Color(hex: 0xEB654F).opacity(disabled ? 0.24 : borderOpacity)
                                : Color.white.opacity(disabled ? 0.24 : borderOpacity),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    func dismissEditingFocus() {
        focusedThresholdProviderID = nil
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            window.makeFirstResponder(nil)
        }
    }

    func settingsInputPrompt(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(settingsInputPlaceholderColor)
    }

    func relayProminentTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: settingsInputPrompt(placeholder))
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.primary.opacity(0.80))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
    }

    func relayProminentSecureField(_ placeholder: String, text: Binding<String>) -> some View {
        SecureField("", text: text, prompt: settingsInputPrompt(placeholder))
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.primary.opacity(0.80))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
    }

    func relayCompactTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: settingsInputPrompt(placeholder))
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.primary.opacity(0.80))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
    }

    @ViewBuilder
    func quotaMetricLayout(
        metrics: [CodexQuotaMetricDisplay],
        twoByTwo: Bool
    ) -> some View {
        if twoByTwo {
            VStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 24) {
                        ForEach(metricsForRow(metrics: metrics, row: row), id: \.id) { metric in
                            codexQuotaMetricView(metric)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        } else {
            HStack(spacing: 24) {
                ForEach(metrics.prefix(2)) { metric in
                    codexQuotaMetricView(metric)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    func metricsForRow(metrics: [CodexQuotaMetricDisplay], row: Int) -> [CodexQuotaMetricDisplay] {
        let start = row * 2
        guard start < metrics.count else { return [] }
        let end = min(start + 2, metrics.count)
        return Array(metrics[start..<end])
    }

    func codexQuotaMetricView(_ metric: CodexQuotaMetricDisplay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(metric.title)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(settingsHintColor)
                    .lineSpacing(0)
                    .lineLimit(1)

                Spacer(minLength: 4)

                HStack(spacing: 2) {
                    if let image = bundledImage(named: "menu_reset_clock_icon") {
                        Image(nsImage: image)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 10, height: 10)
                            .foregroundStyle(settingsHintColor)
                    } else {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(settingsHintColor)
                    }

                    Text(metric.resetText)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(settingsMutedHintColor)
                        .monospacedDigit()
                        .lineSpacing(0)
                        .frame(minWidth: 42, alignment: .trailing)
                        .fixedSize(horizontal: true, vertical: false)
                        .lineLimit(1)
                }
                .frame(minWidth: 54, alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
                .frame(height: 10)
            }
            .frame(height: 10)

            HStack(spacing: 5) {
                Text(metric.valueText)
                    .font(AppFonts.numeric(size: 16, fallbackWeight: .semibold))
                    .foregroundStyle(settingsBodyColor)
                    .lineSpacing(0)
                    .frame(width: MetricValueLayoutFormatter.metricValueColumnWidth, alignment: .leading)
                    .lineLimit(1)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(settingsQuotaTrackColor)
                        if let percent = metric.percent, percent > 0 {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(metric.barColor)
                                .frame(width: max(1, proxy.size.width * percent / 100))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        if metric.isBlockedByDepletedQuota {
                            QuotaBlockedStripePattern()
                                .fill(Color(hex: 0x4D4D4D))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .frame(height: 4)
            }
        }
    }

    func codexAccountActionButton(
        _ title: String,
        destructive: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .tint(destructive ? Color(hex: 0xD05757) : settingsAccentBlue)
        .disabled(disabled)
    }

    func codexAccountIcon(size: CGFloat) -> some View {
        Group {
            if let image = themedBundledImage(named: "menu_codex_icon") {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "terminal.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(settingsBodyColor)
            }
        }
        .frame(width: size, height: size)
    }

    func claudeAccountIcon(size: CGFloat) -> some View {
        Group {
            if let image = themedBundledImage(named: "menu_claude_icon") {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "bolt.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(settingsBodyColor)
            }
        }
        .frame(width: size, height: size)
    }

    func officialMonitoringProvider(for type: ProviderType) -> ProviderDescriptor {
        Self.resolvedOfficialMonitoringProvider(
            type: type,
            providers: viewModel.config.providers
        )
    }

    func localizedOfficialMonitoringStatus(
        _ status: OfficialMonitoringHealthStatus
    ) -> (text: String, color: Color) {
        switch status {
        case .unknown:
            return (viewModel.language == .zhHans ? "未知" : "Unknown", settingsHintColor)
        case .authError:
            return (viewModel.language == .zhHans ? "认证故障" : "Auth Error", Color(hex: 0xD05757))
        case .configError:
            return (viewModel.language == .zhHans ? "配置异常" : "Config Error", Color(hex: 0xD05757))
        case .rateLimited:
            return (viewModel.language == .zhHans ? "限流" : "Rate Limited", Color(hex: 0xE88B2D))
        case .disconnected:
            return (viewModel.language == .zhHans ? "连接失败" : "Disconnected", Color(hex: 0xD05757))
        case .sufficient:
            return (viewModel.text(.statusSufficient), Color(hex: 0x69BD64))
        case .tight:
            return (viewModel.text(.statusTight), Color(hex: 0xE88B2D))
        case .exhausted:
            return (viewModel.text(.statusExhausted), Color(hex: 0xD05757))
        }
    }

    func codexSlotStatus(provider: ProviderDescriptor, snapshot: UsageSnapshot?) -> (text: String, color: Color) {
        let healthPercents = codexQuotaMetrics(provider: provider, snapshot: snapshot).compactMap(\.healthPercent)
        let status = Self.officialMonitoringHealthStatus(
            snapshot: snapshot,
            healthPercents: healthPercents
        )
        return localizedOfficialMonitoringStatus(status)
    }

    func officialMonitorSubtitle(snapshot: UsageSnapshot?) -> String? {
        guard viewModel.showOfficialAccountEmailInMenuBar else { return nil }
        return OfficialValueParser.nonPlaceholderString(snapshot?.accountLabel)
    }

    func officialMonitorPlanType(providerType: ProviderType, snapshot: UsageSnapshot?) -> String? {
        PlanTypeDisplayFormatter.resolvedPlanType(
            providerType: providerType,
            extrasPlanType: snapshot?.extras["planType"],
            rawPlanType: snapshot?.rawMeta["planType"]
        )
    }

    func settingsProviderPlanType(provider: ProviderDescriptor, snapshot: UsageSnapshot?) -> String? {
        if provider.family == .official {
            return officialMonitorPlanType(providerType: provider.type, snapshot: snapshot)
        }
        return PlanTypeDisplayFormatter.normalizedPlanType(
            snapshot?.extras["planType"],
            providerType: provider.type
        ) ?? PlanTypeDisplayFormatter.normalizedPlanType(
            snapshot?.rawMeta["planType"],
            providerType: provider.type
        )
    }

    func codexQuotaMetrics(provider: ProviderDescriptor, snapshot: UsageSnapshot?) -> [CodexQuotaMetricDisplay] {
        if provider.type == .claude {
            if let snapshot, !snapshot.quotaWindows.isEmpty {
                return claudeCodexQuotaMetrics(provider: provider, snapshot: snapshot)
            }
            return claudeCodexQuotaPlaceholderMetrics(provider: provider)
        }

        let windows: [UsageQuotaWindow]
        if let snapshot, !snapshot.quotaWindows.isEmpty {
            windows = snapshot.quotaWindows
                .sorted { codexQuotaRank($0.kind) < codexQuotaRank($1.kind) }
        } else {
            switch provider.type {
            case .trae:
                windows = [
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-dollar",
                        title: traeQuotaMetricTitle(baseTitle: "Dollar"),
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .custom
                    ),
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-autocomplete",
                        title: traeQuotaMetricTitle(baseTitle: "Autocomplete"),
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .custom
                    )
                ]
            case .copilot:
                windows = [
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-premium",
                        title: "Premium",
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .custom
                    ),
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-chat",
                        title: "Chat",
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .custom
                    )
                ]
            case .microsoftCopilot:
                windows = [
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-d7",
                        title: "D7",
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .custom
                    ),
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-d30",
                        title: "D30",
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .custom
                    )
                ]
            case .openrouterCredits:
                windows = [
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-credits",
                        title: "Credits",
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .credits
                    )
                ]
            case .openrouterAPI:
                windows = [
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-limit",
                        title: "Limit",
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .credits
                    )
                ]
            case .ollamaCloud:
                windows = [
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-session",
                        title: viewModel.localizedText("会话", "Session"),
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .session
                    ),
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-weekly",
                        title: viewModel.text(.quotaWeekly),
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .weekly
                    )
                ]
            default:
                windows = [
                    UsageQuotaWindow(
                        id: "codex-placeholder-session",
                        title: viewModel.text(.quotaFiveHour),
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .session
                    ),
                    UsageQuotaWindow(
                        id: "codex-placeholder-weekly",
                        title: viewModel.text(.quotaWeekly),
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .weekly
                    )
                ]
            }
        }

        return windows.prefix(2).map { window in
            let percents = Self.quotaMetricPercents(
                for: window,
                displaysUsedQuota: provider.displaysUsedQuota
            )
            return CodexQuotaMetricDisplay(
                id: window.id,
                title: codexQuotaDisplayTitle(window, provider: provider),
                valueText: codexQuotaValueText(
                    window: window,
                    provider: provider,
                    snapshot: snapshot,
                    displayPercent: percents.displayPercent
                ),
                resetText: codexResetCountdownText(for: window, snapshot: snapshot),
                percent: percents.displayPercent,
                barColor: codexQuotaBarColor(remainingPercent: percents.healthPercent),
                healthPercent: percents.healthPercent,
                isBlockedByDepletedQuota: QuotaBlockagePresenter.isBlockedByDepletedWeeklyQuota(
                    window: window,
                    in: windows,
                    provider: provider
                )
            )
        }
    }

    func claudeCodexQuotaPlaceholderMetrics(provider: ProviderDescriptor) -> [CodexQuotaMetricDisplay] {
        [
            CodexQuotaMetricDisplay(
                id: "\(provider.id)-placeholder-session",
                title: usagePreferredQuotaTitle(viewModel.text(.quotaFiveHour), provider: provider),
                valueText: "0%",
                resetText: codexResetCountdownText(to: nil),
                percent: 0,
                barColor: codexQuotaBarColor(remainingPercent: 0),
                healthPercent: 0
            ),
            CodexQuotaMetricDisplay(
                id: "\(provider.id)-placeholder-weekly-all",
                title: usagePreferredQuotaTitle(
                    viewModel.localizedText("全部模型", "All models"),
                    provider: provider
                ),
                valueText: "0%",
                resetText: codexResetCountdownText(to: nil),
                percent: 0,
                barColor: codexQuotaBarColor(remainingPercent: 0),
                healthPercent: 0
            ),
            CodexQuotaMetricDisplay(
                id: "\(provider.id)-placeholder-weekly-sonnet",
                title: usagePreferredQuotaTitle(
                    viewModel.localizedText("Sonnet 专用", "Sonnet only"),
                    provider: provider
                ),
                valueText: "N/A",
                resetText: codexResetCountdownText(to: nil),
                percent: nil,
                barColor: .clear,
                isAvailable: false
            ),
            CodexQuotaMetricDisplay(
                id: "\(provider.id)-placeholder-weekly-design",
                title: usagePreferredQuotaTitle(
                    viewModel.localizedText("Claude Design", "Claude Design"),
                    provider: provider
                ),
                valueText: "N/A",
                resetText: codexResetCountdownText(to: nil),
                percent: nil,
                barColor: .clear,
                isAvailable: false
            )
        ]
    }

    func claudeCodexQuotaMetrics(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot
    ) -> [CodexQuotaMetricDisplay] {
        let windows = snapshot.quotaWindows
        let sessionWindow = windows.first(where: { $0.kind == .session })
        return [
            claudeCodexQuotaMetric(
                provider: provider,
                id: "\(provider.id)-session",
                title: viewModel.text(.quotaFiveHour),
                window: sessionWindow,
                snapshot: snapshot,
                isBlockedByDepletedQuota: sessionWindow.map {
                    QuotaBlockagePresenter.isBlockedByDepletedWeeklyQuota(window: $0, in: windows, provider: provider)
                } ?? false
            ),
            claudeCodexQuotaMetric(
                provider: provider,
                id: "\(provider.id)-weekly-all",
                title: viewModel.localizedText("全部模型", "All models"),
                window: windows.first(where: { $0.kind == .weekly }),
                snapshot: snapshot
            ),
            claudeCodexQuotaMetric(
                provider: provider,
                id: "\(provider.id)-weekly-sonnet",
                title: viewModel.localizedText("Sonnet 专用", "Sonnet only"),
                window: windows.first(where: isClaudeSonnetWindow(_:)),
                snapshot: snapshot
            ),
            claudeCodexQuotaMetric(
                provider: provider,
                id: "\(provider.id)-weekly-design",
                title: viewModel.localizedText("Claude Design", "Claude Design"),
                window: windows.first(where: isClaudeDesignWindow(_:)),
                snapshot: snapshot
            )
        ]
    }

    func claudeCodexQuotaMetric(
        provider: ProviderDescriptor,
        id: String,
        title: String,
        window: UsageQuotaWindow?,
        snapshot: UsageSnapshot,
        isBlockedByDepletedQuota: Bool = false
    ) -> CodexQuotaMetricDisplay {
        guard let window else {
            return CodexQuotaMetricDisplay(
                id: id,
                title: usagePreferredQuotaTitle(title, provider: provider),
                valueText: "N/A",
                resetText: codexResetCountdownText(to: nil),
                percent: nil,
                barColor: .clear,
                isAvailable: false
            )
        }

        let percents = Self.quotaMetricPercents(
            for: window,
            displaysUsedQuota: provider.displaysUsedQuota
        )
        return CodexQuotaMetricDisplay(
            id: id,
            title: usagePreferredQuotaTitle(title, provider: provider),
            valueText: codexQuotaValueText(
                window: window,
                provider: provider,
                snapshot: snapshot,
                displayPercent: percents.displayPercent
            ),
            resetText: codexResetCountdownText(for: window, snapshot: snapshot),
            percent: percents.displayPercent,
            barColor: codexQuotaBarColor(remainingPercent: percents.healthPercent),
            isAvailable: true,
            healthPercent: percents.healthPercent,
            isBlockedByDepletedQuota: isBlockedByDepletedQuota
        )
    }

    func codexQuotaBarColor(remainingPercent: Double?) -> Color {
        guard let remainingPercent else {
            return .clear
        }
        if remainingPercent > 30 {
            return Color(hex: 0x69BD64)
        }
        if remainingPercent > 10 {
            return Color(hex: 0xE88B2D)
        }
        return Color(hex: 0xD05757)
    }

    func isClaudeSonnetWindow(_ window: UsageQuotaWindow) -> Bool {
        let normalizedID = window.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedID.contains("sonnet")
            || normalizedTitle.contains("sonnet")
    }

    func isClaudeDesignWindow(_ window: UsageQuotaWindow) -> Bool {
        let normalizedID = window.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedID.contains("design")
            || normalizedTitle.contains("design")
    }

    func codexQuotaDisplayTitle(_ window: UsageQuotaWindow, provider: ProviderDescriptor) -> String {
        let baseTitle: String
        if provider.type == .trae {
            baseTitle = traeQuotaMetricTitle(baseTitle: window.title)
            return usagePreferredQuotaTitle(baseTitle, provider: provider)
        }
        switch window.kind {
        case .session:
            if provider.type == .ollamaCloud {
                baseTitle = viewModel.localizedText("会话", "Session")
            } else {
                baseTitle = viewModel.text(.quotaFiveHour)
            }
        case .weekly, .modelWeekly:
            baseTitle = viewModel.text(.quotaWeekly)
        default:
            baseTitle = relayTokenPlanMetricTitle(window.title, provider: provider)
        }
        return usagePreferredQuotaTitle(baseTitle, provider: provider)
    }

    func relayTokenPlanMetricTitle(_ rawTitle: String, provider: ProviderDescriptor) -> String {
        let normalizedAdapterID = provider.relayConfig?.adapterID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let normalizedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedAdapterID == "xiaomimimo-token-plan" else { return rawTitle }
        if normalizedTitle == "current plan" {
            return viewModel.localizedText("当前套餐", "Current Plan")
        }
        return rawTitle
    }

    func usagePreferredQuotaTitle(_ baseTitle: String, provider: ProviderDescriptor) -> String {
        guard provider.displaysUsedQuota else { return baseTitle }
        switch viewModel.language {
        case .zhHans:
            return "\(baseTitle)已用"
        case .en:
            return "\(baseTitle) used"
        }
    }

    func codexQuotaValueText(
        window: UsageQuotaWindow,
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        displayPercent: Double
    ) -> String {
        if provider.type == .trae, provider.traeDisplaysAmount {
            if let amount = traeAmountValue(
                window: window,
                snapshot: snapshot,
                displaysUsedQuota: provider.displaysUsedQuota
            ),
               let kind = TraeMetricKind.detect(id: window.id, title: window.title) {
                return TraeValueDisplayFormatter.format(
                    amount,
                    kind: kind,
                    maxWidth: MetricValueLayoutFormatter.metricValueColumnWidth
                )
            }
            return "-"
        }
        return "\(Int(displayPercent.rounded()))%"
    }

    func traeAmountValue(
        window: UsageQuotaWindow,
        snapshot: UsageSnapshot?,
        displaysUsedQuota: Bool
    ) -> Double? {
        guard let snapshot else { return nil }
        let primaryKey: String?
        let fallbackKey: String?
        let normalizedTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if window.id.lowercased().contains("autocomplete") || normalizedTitle.contains("autocomplete") || normalizedTitle.contains("自动补全") {
            primaryKey = displaysUsedQuota ? "autocompleteUsed" : "autocompleteRemaining"
            fallbackKey = displaysUsedQuota ? "autocompleteRemaining" : nil
        } else if window.id.lowercased().contains("dollar") || normalizedTitle.contains("dollar") || normalizedTitle.contains("美元") {
            primaryKey = displaysUsedQuota ? "dollarUsed" : "dollarRemaining"
            fallbackKey = displaysUsedQuota ? "dollarRemaining" : nil
        } else {
            primaryKey = nil
            fallbackKey = nil
        }
        guard let key = primaryKey else { return nil }
        let resolvedRaw = snapshot.extras[key] ?? fallbackKey.flatMap { snapshot.extras[$0] }
        guard let raw = resolvedRaw else { return nil }
        return Double(raw)
    }

    func traeQuotaMetricTitle(baseTitle: String) -> String {
        let normalized = baseTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("autocomplete") || normalized.contains("自动补全") {
            return viewModel.localizedText("自动补全", "Autocomplete")
        }
        if normalized.contains("dollar") || normalized.contains("美元") {
            return viewModel.localizedText("美元余额", "Dollar Balance")
        }
        return baseTitle
    }

    func codexQuotaRank(_ kind: UsageQuotaKind) -> Int {
        switch kind {
        case .session: return 0
        case .weekly: return 1
        case .reviews: return 2
        case .modelWeekly: return 3
        case .credits: return 4
        case .extraUsage: return 5
        case .custom: return 6
        }
    }

    func codexResetCountdownText(to target: Date?) -> String {
        Self.codexCountdownText(to: target, now: runtimeState.settingsNow, language: viewModel.language)
    }

    func codexResetCountdownText(for window: UsageQuotaWindow, snapshot: UsageSnapshot?) -> String {
        codexResetCountdownText(to: window.resetAt)
    }

    static func codexCountdownText(to target: Date?, now: Date, language: AppLanguage) -> String {
        SettingsCountdownPresenter.codexCountdownText(to: target, now: now, language: language)
    }

    var codexEditButtonTitle: String {
        viewModel.language == .zhHans ? "编辑" : "Edit"
    }

    var codexDeleteButtonTitle: String {
        viewModel.language == .zhHans ? "删除账号" : "Delete"
    }

    var codexAddButtonTitle: String {
        viewModel.language == .zhHans ? "添加" : "Add"
    }

    func sourceModeLabel(_ mode: OfficialSourceMode) -> String {
        switch mode {
        case .auto: return "Auto"
        case .api: return "API"
        case .cli: return "CLI"
        case .web: return "Web"
        }
    }

    func officialSourceHintText(for provider: ProviderDescriptor) -> String {
        if provider.type == .kiro {
            return viewModel.localizedText(
                "默认会自动发现本地 CLI 或 Kiro IDE 登录态；当 CLI 不可用时会回退读取 IDE 缓存。",
                "Local Kiro CLI sessions are auto-discovered by default. When CLI is unavailable, the app falls back to Kiro IDE cache."
            )
        }
        if provider.type == .copilot {
            return viewModel.localizedText(
                "默认按顺序自动读取 COPILOT_GITHUB_TOKEN、GH_TOKEN、GITHUB_TOKEN、Copilot CLI 钥匙串与 GitHub CLI 登录态；当前仅支持 API 检测。",
                "Automatically checks COPILOT_GITHUB_TOKEN, GH_TOKEN, GITHUB_TOKEN, Copilot CLI keychain, and GitHub CLI login in order. API detection only."
            )
        }
        if provider.type == .openrouterCredits {
            return viewModel.localizedText(
                "OpenRouter Credits 需要管理密钥（Management Key），用于读取 /credits 的总额度数据。",
                "OpenRouter Credits requires a Management Key to read total credit usage from /credits."
            )
        }
        if provider.type == .opencodeGo {
            return viewModel.localizedText(
                "Workspace ID 请从 opencode.ai 的 workspace URL 中复制 wrk_...；Cookie 可开启浏览器自动导入 auth，或手动粘贴。若远端接口 hash 变更，可用环境变量 OPENCODE_USAGE_ENDPOINT_ID 覆盖。",
                "Copy Workspace ID (wrk_...) from the opencode.ai workspace URL. Cookie can be auto-imported from browser auth or pasted manually. If endpoint hash changes, override with OPENCODE_USAGE_ENDPOINT_ID."
            )
        }
        if provider.type == .openrouterAPI {
            return viewModel.localizedText(
                "OpenRouter API 使用普通 API Key，读取 /key 的 limit 与 remaining。",
                "OpenRouter API uses a regular API key to read limit and remaining from /key."
            )
        }
        if provider.type == .ollamaCloud {
            return viewModel.localizedText(
                "默认从浏览器自动导入 ollama.com 的 __Secure-session Cookie，也可切到手动模式粘贴。",
                "By default, __Secure-session is auto-imported from ollama.com browser cookies. You can switch to manual mode and paste it."
            )
        }
        return viewModel.text(.officialAutoDiscoveryHint)
    }

    func webModeLabel(_ mode: OfficialWebMode) -> String {
        switch mode {
        case .disabled: return viewModel.text(.webDisabled)
        case .autoImport: return viewModel.text(.webAutoImport)
        case .manual: return viewModel.text(.webManual)
        }
    }

    func firstExistingRelayIconName(_ candidates: [String]) -> String? {
        candidates.first { bundledImage(named: $0) != nil }
    }
}
