import Foundation
import SwiftUI
import UIKit
#if canImport(UXKit)
import UXKit
#endif

/// SwiftUI has no wheel event modifier. Keep that single native input hook
/// isolated here; the field's touch pinch and drag remain SwiftUI gestures.
struct WheelZoomInput: UIViewRepresentable {
    let onZoom: (Double) -> Void

    func makeUIView(context: Context) -> WheelZoomView {
        let view = WheelZoomView(frame: .zero)
        view.onZoom = onZoom
        return view
    }

    func updateUIView(_ view: WheelZoomView, context: Context) {
        view.onZoom = onZoom
    }
}

final class WheelZoomView: UIView {
    var onZoom: (Double) -> Void = { _ in }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = true
        #if !canImport(UXKit)
        let wheel = UIPanGestureRecognizer(target: self, action: #selector(scrolled(_:)))
        wheel.allowedScrollTypesMask = [.continuous, .discrete]
        // Direct touch stays available to the surrounding SwiftUI gestures.
        wheel.allowedTouchTypes = []
        wheel.cancelsTouchesInView = false
        addGestureRecognizer(wheel)
        #endif
    }

    required init?(coder: NSCoder) { nil }

    #if canImport(UXKit)
    override var handlesScrollWheelEvents: Bool { true }

    override func scrollWheel(with event: UXEvent) {
        // UXKit normalizes SDL and browser wheels to upward-positive units;
        // browser input has already converted 100 CSS pixels to one unit.
        zoom(logarithmicDelta: Double(event.velocity.y) * 0.12)
    }
    #else
    @objc private func scrolled(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .began || recognizer.state == .changed else { return }
        let delta = recognizer.translation(in: self).y
        recognizer.setTranslation(.zero, in: self)
        zoom(logarithmicDelta: Double(delta) * 0.003)
    }
    #endif

    private func zoom(logarithmicDelta: Double) {
        guard logarithmicDelta.isFinite, logarithmicDelta != 0 else { return }
        onZoom(exp(min(0.5, max(-0.5, logarithmicDelta))))
    }
}
