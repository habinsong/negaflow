import SwiftUI
import AppKit

/// 드래그 중 AppKit이 thumb를 소유합니다. SwiftUI 재표시는 추적 중인 값을 덮지 않습니다.
struct CommitSlider: NSViewRepresentable {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let resetValue: Double
    let ownerID: UUID
    let label: String
    var snapsToStep = false
    var onDraft: (Double?) -> Void
    var onCommit: (Double) -> Void
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> CommitSliderControl { CommitSliderControl() }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CommitSliderControl, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil }
            ?? max(0, nsView.intrinsicContentSize.width)
        return CGSize(width: width, height: 20)
    }

    func updateNSView(_ slider: CommitSliderControl, context: Context) {
        if slider.minValue != range.lowerBound { slider.minValue = range.lowerBound }
        if slider.maxValue != range.upperBound { slider.maxValue = range.upperBound }
        slider.step = step
        slider.snapsToStep = snapsToStep
        slider.resetValue = resetValue
        if slider.isEnabled != isEnabled { slider.isEnabled = isEnabled }
        slider.setAccessibilityLabel(label)
        slider.synchronize(value, ownerID: ownerID)
        slider.onDraft = onDraft
        slider.onCommit = onCommit
    }
}

final class CommitSliderControl: NSSlider {
    var step = 0.01
    var snapsToStep = false
    var resetValue = 1.0
    var onDraft: (Double?) -> Void = { _ in }
    var onCommit: (Double) -> Void = { _ in }
    private(set) var editing = false
    private var cancelled = false
    private var initialValue = 0.0
    private var ownerID: UUID?

    init() {
        super.init(frame: .zero)
        isContinuous = true
        controlSize = .small
        target = self
        action = #selector(valueChanged)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override var isEnabled: Bool {
        didSet { if !isEnabled && editing { cancelOperation(nil) } }
    }

    func synchronize(_ value: Double, ownerID: UUID) {
        let value = snapped(value)
        if self.ownerID != ownerID {
            cancelled = editing
            self.ownerID = ownerID
            initialValue = value
            doubleValue = value
        } else if !editing {
            initialValue = value
            doubleValue = value
        }
    }

    func beginEditing() {
        guard isEnabled else { return }
        initialValue = doubleValue
        editing = true
        cancelled = false
        traceTracking("controlBegin")
    }

    func finishEditing() {
        guard editing else { return }
        editing = false
        traceTracking(cancelled ? "controlCancelledEnd" : "controlEnd")
        if cancelled || !isEnabled { doubleValue = initialValue }
        else { doubleValue = snapped(doubleValue); onCommit(doubleValue) }
        onDraft(nil)
        cancelled = false
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            doubleValue = resetValue
            onCommit(resetValue)
            return
        }
        beginEditing()
        super.mouseDown(with: event)
        finishEditing()
    }

    @objc func valueChanged() {
        guard !cancelled, isEnabled else { doubleValue = initialValue; return }
        // 감마만 지정 간격으로 맞춥니다. 추적 중 외부 모델 값은 여전히 받지 않습니다.
        doubleValue = snapped(doubleValue)
        if editing { onDraft(doubleValue) }
        else { onCommit(doubleValue) }
    }

    private func snapped(_ value: Double) -> Double {
        guard snapsToStep else { return value }
        let increments = 1 / step
        return min(max((value * increments).rounded() / increments, minValue), maxValue)
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        if [123, 124, 125, 126].contains(event.keyCode) {
            if !editing { beginEditing() }
            let direction = [124, 126].contains(event.keyCode) ? 1.0 : -1.0
            let increment = step * (event.modifierFlags.contains(.shift) ? 10 : 1)
            doubleValue = min(max(doubleValue + direction * increment, minValue), maxValue)
            valueChanged()
        } else if event.keyCode == 53 { cancelOperation(nil) }
        else if event.keyCode == 36 { finishEditing() }
        else { super.keyDown(with: event) }
    }

    override func keyUp(with event: NSEvent) {
        if [123, 124, 125, 126].contains(event.keyCode) { finishEditing() }
        else { super.keyUp(with: event) }
    }

    override func cancelOperation(_ sender: Any?) {
        guard editing else { return }
        traceTracking("controlCancel")
        cancelled = true
        doubleValue = initialValue
        onDraft(nil)
    }

    override func resignFirstResponder() -> Bool {
        if editing { traceTracking("controlBlur") }
        if editing { cancelOperation(nil); finishEditing() }
        return super.resignFirstResponder()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            traceTracking("controlDetach")
            cancelled = true; editing = false
        }
    }

    private func traceTracking(_ phase: String) {
        guard snapsToStep, let ownerID else { return }
        InputGammaPreviewTrace.emit(phase, frameID: ownerID, session: 0, value: doubleValue)
    }
}
