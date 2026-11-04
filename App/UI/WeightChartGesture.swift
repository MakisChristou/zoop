import SwiftUI
import UIKit

/// One recognizer resolves intent before claiming a touch. A vertical movement
/// fails immediately, leaving the containing scroll view in charge.
struct WeightChartGesture: UIViewRepresentable {
    var select: (CGPoint) -> Void
    var page: (Int) -> Void
    func makeUIView(context: Context) -> Surface { Surface() }
    func updateUIView(_ view: Surface, context: Context) { view.select = select; view.page = page }

    final class Surface: UIView {
        var select: (CGPoint) -> Void = { _ in }
        var page: (Int) -> Void = { _ in }
        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear; isAccessibilityElement = false
            addGestureRecognizer(IntentGesture(target: self, action: #selector(handle(_:))))
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        @objc private func handle(_ gesture: IntentGesture) {
            if gesture.inspect || gesture.tap {
                if gesture.state == .began || gesture.state == .changed || gesture.state == .ended { select(gesture.point) }
            } else if gesture.state == .ended, abs(gesture.point.x - gesture.origin.x) > 40 {
                page(gesture.point.x > gesture.origin.x ? -1 : 1)
            }
        }
    }

    private final class IntentGesture: UIGestureRecognizer {
        private(set) var origin = CGPoint.zero
        private(set) var point = CGPoint.zero
        private(set) var inspect = false
        private(set) var tap = false
        private var hold: Timer?
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            guard touches.count == 1, let touch = touches.first else { state = .failed; return }
            origin = touch.location(in: view); point = origin
            hold = Timer.scheduledTimer(timeInterval: 0.2, target: self, selector: #selector(beginInspection), userInfo: nil, repeats: false)
        }
        @objc private func beginInspection() {
            guard state == .possible else { return }
            inspect = true; state = .began
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let touch = touches.first else { return }
            point = touch.location(in: view)
            if state == .possible {
                let x = abs(point.x - origin.x), y = abs(point.y - origin.y)
                guard max(x, y) >= 6 else { return }
                hold?.invalidate(); hold = nil
                if y >= x { state = .failed; return }
                state = .began
            } else if state == .began || state == .changed { state = .changed }
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            if let touch = touches.first { point = touch.location(in: view) }
            hold?.invalidate(); hold = nil
            tap = state == .possible
            if state == .possible || state == .began || state == .changed { state = .ended }
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .cancelled }
        override func reset() {
            hold?.invalidate(); hold = nil; inspect = false; tap = false
            super.reset()
        }
    }
}
