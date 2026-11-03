import SwiftUI
import UIKit

/// A quick horizontal swipe pages; holding first inspects. Vertical scrolling stays native.
struct WeightChartGesture: UIViewRepresentable {
    var select: (CGPoint) -> Void
    var page: (Int) -> Void
    func makeUIView(context: Context) -> Surface { Surface() }
    func updateUIView(_ view: Surface, context: Context) { view.select = select; view.page = page }

    final class Surface: UIView, UIGestureRecognizerDelegate {
        var select: (CGPoint) -> Void = { _ in }
        var page: (Int) -> Void = { _ in }
        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear; isAccessibilityElement = false
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(inspect(_:)))
            hold.minimumPressDuration = 0.2; hold.allowableMovement = 12; hold.delegate = self
            let swipe = UIPanGestureRecognizer(target: self, action: #selector(swipe(_:)))
            swipe.maximumNumberOfTouches = 1; swipe.delegate = self; swipe.require(toFail: hold)
            let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
            tap.require(toFail: hold)
            addGestureRecognizer(hold); addGestureRecognizer(swipe); addGestureRecognizer(tap)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        @objc private func inspect(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began || gesture.state == .changed { select(gesture.location(in: self)) }
        }
        @objc private func tap(_ gesture: UITapGestureRecognizer) { select(gesture.location(in: self)) }
        @objc private func swipe(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .ended else { return }
            let distance = gesture.translation(in: self).x, velocity = gesture.velocity(in: self).x
            guard abs(distance) > 40 || abs(velocity) > 300 else { return }
            page(distance > 0 ? -1 : 1)
        }
        override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: self)
            return abs(velocity.x) > abs(velocity.y)
        }
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            gesture is UIPanGestureRecognizer && other.view is UIScrollView
        }
    }
}
