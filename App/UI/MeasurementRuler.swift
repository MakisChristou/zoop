import SwiftUI
import UIKit

/// A native scrolling ruler. Only the visible ticks are drawn, regardless of range.
struct MeasurementRuler: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let label: String
    var majorTickEvery = 10
    var onEditing: () -> Void = {}

    var body: some View {
        RulerSurface(value: $value, range: range, step: step, majorTickEvery: majorTickEvery, onEditing: onEditing)
            .frame(height: 92)
            .overlay(alignment: .top) {
                Capsule().fill(SnoopStyle.load).frame(width: 3, height: 38).allowsHitTesting(false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue("\(value.formatted(.number.precision(.fractionLength(step < 1 ? 1 : 0)))) \(unit)")
            .accessibilityAdjustableAction { direction in
                onEditing()
                let delta = direction == .increment ? step : -step
                value = min(max(((value + delta) / step).rounded() * step, range.lowerBound), range.upperBound)
            }
    }
}

private struct RulerSurface: UIViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let majorTickEvery: Int
    let onEditing: () -> Void

    func makeUIView(context: Context) -> Surface { Surface() }
    func updateUIView(_ view: Surface, context: Context) {
        view.changed = { value = $0 }
        view.editing = onEditing
        view.configure(value: value, range: range, step: step, majorTickEvery: majorTickEvery)
    }

    final class Surface: UIView, UIScrollViewDelegate {
        private let scroll = UIScrollView()
        private let ticks = Ticks()
        private let feedback = UISelectionFeedbackGenerator()
        private var range = 0.0...1.0
        private var step = 1.0
        private var value = 0.0
        private var configuring = false
        private var lastWidth = 0.0
        private let spacing = 12.0
        var changed: (Double) -> Void = { _ in }
        var editing: () -> Void = {}

        override init(frame: CGRect) {
            super.init(frame: frame)
            scroll.delegate = self
            scroll.showsHorizontalScrollIndicator = false
            scroll.alwaysBounceVertical = false
            scroll.isDirectionalLockEnabled = true
            scroll.decelerationRate = .fast
            scroll.contentInsetAdjustmentBehavior = .never
            addSubview(scroll)
            ticks.isUserInteractionEnabled = false
            ticks.isOpaque = false
            addSubview(ticks)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func configure(value: Double, range: ClosedRange<Double>, step: Double, majorTickEvery: Int) {
            ticks.majorTickEvery = max(1, majorTickEvery)
            let scaleChanged = self.range != range || self.step != step
            self.range = range; self.step = step
            let clamped = min(max(value, range.lowerBound), range.upperBound)
            let valueChanged = abs(self.value - clamped) > step / 100
            self.value = clamped
            if scaleChanged || valueChanged { position() }
            setNeedsLayout()
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            scroll.frame = bounds; ticks.frame = bounds
            scroll.contentSize = CGSize(width: (range.upperBound - range.lowerBound) / step * spacing + bounds.width, height: bounds.height)
            if lastWidth != bounds.width { lastWidth = bounds.width; position() }
            drawTicks()
        }
        private func position() {
            // A unit change or typed edit must not feed back as a new measurement.
            configuring = true
            scroll.setContentOffset(CGPoint(x: (value - range.lowerBound) / step * spacing, y: 0), animated: false)
            configuring = false
            drawTicks()
        }
        private func drawTicks() {
            ticks.start = range.lowerBound; ticks.end = range.upperBound; ticks.step = step
            ticks.offset = scroll.contentOffset.x; ticks.spacing = spacing
            ticks.setNeedsDisplay()
        }
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { editing(); feedback.prepare() }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            drawTicks()
            guard !configuring, scrollView.isDragging || scrollView.isDecelerating else { return }
            let raw = range.lowerBound + scrollView.contentOffset.x / spacing * step
            let selected = min(max((raw / step).rounded() * step, range.lowerBound), range.upperBound)
            guard abs(selected - value) > step / 100 else { return }
            value = selected
            feedback.selectionChanged()
            changed(selected)
        }
        func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
            let raw = range.lowerBound + targetContentOffset.pointee.x / spacing * step
            let selected = min(max((raw / step).rounded() * step, range.lowerBound), range.upperBound)
            targetContentOffset.pointee.x = (selected - range.lowerBound) / step * spacing
        }
    }

    private final class Ticks: UIView {
        var start = 0.0, end = 1.0, step = 1.0, offset = 0.0, spacing = 12.0
        var majorTickEvery = 10
        override func draw(_ rect: CGRect) {
            guard let context = UIGraphicsGetCurrentContext(), step > 0 else { return }
            let first = max(0, Int(floor((offset - bounds.midX) / spacing)))
            let last = min(Int(((end - start) / step).rounded()), Int(ceil((offset + bounds.midX) / spacing)))
            guard first <= last else { return }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: UIColor(SnoopStyle.secondary)
            ]
            for index in first...last {
                let value = start + Double(index) * step
                let tick = Int((value / step).rounded())
                let major = tick.isMultiple(of: majorTickEvery)
                let x = bounds.midX + Double(index) * spacing - offset
                context.setStrokeColor(UIColor(major ? SnoopStyle.secondary : SnoopStyle.track).cgColor)
                context.setLineWidth(1)
                context.move(to: CGPoint(x: x, y: 6))
                context.addLine(to: CGPoint(x: x, y: major ? 34 : tick.isMultiple(of: 5) ? 26 : 18))
                context.strokePath()
                if major {
                    let decimals = Double(majorTickEvery) * step < 1 ? 1 : 0
                    let text = value.formatted(.number.precision(.fractionLength(decimals))) as NSString
                    let width = text.size(withAttributes: attributes).width
                    // A clipped "80" must not look like a separate "0" reading.
                    // Keep edge ticks, but draw labels only when the whole number fits.
                    if x - width / 2 >= 0, x + width / 2 <= bounds.width {
                        text.draw(at: CGPoint(x: x - width / 2, y: 47), withAttributes: attributes)
                    }
                }
            }
        }
    }
}
