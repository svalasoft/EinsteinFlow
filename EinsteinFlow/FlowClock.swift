import Foundation

/// One source of truth for playback. Explicit input values avoid stale view
/// captures in change callbacks. A visible view starts playing immediately;
/// subsequent lifecycle events freeze time while it is away.
struct FlowClock {
    private var accumulated: TimeInterval = 0
    private var anchor: Date
    private var rotationAccumulated = 0.0
    private var rotationAnchor: Date
    private var visible = true
    private var reducedMotion = false
    private(set) var paused = false
    private(set) var running = true
    private(set) var speed = 1.0
    private(set) var rotationStep = 1

    init(at date: Date = Date()) { anchor = date; rotationAnchor = date }

    func elapsed(at date: Date) -> TimeInterval {
        accumulated + (running ? max(0, date.timeIntervalSince(anchor)) * speed : 0)
    }

    mutating func setSpeed(_ value: Double, at date: Date) {
        accumulated = elapsed(at: date)
        anchor = date
        speed = min(8, max(0.25, value))
    }

    func rotationAngle(at date: Date) -> Double {
        rotationAccumulated + (running ? max(0, date.timeIntervalSince(rotationAnchor)) * 0.065 * Double(rotationStep) : 0)
    }

    mutating func stepRotation(by step: Int, at date: Date) {
        rotationAccumulated = rotationAngle(at: date)
        rotationAnchor = date
        rotationStep = min(4, max(-4, rotationStep + step))
    }

    mutating func togglePaused(at date: Date) {
        paused.toggle()
        reconcile(at: date)
    }

    mutating func setVisible(_ value: Bool, at date: Date) {
        visible = value
        reconcile(at: date)
    }

    mutating func setReducedMotion(_ value: Bool, at date: Date) {
        reducedMotion = value
        reconcile(at: date)
    }

    private mutating func reconcile(at date: Date) {
        let next = visible && !paused && !reducedMotion
        guard next != running else { return }
        accumulated = elapsed(at: date)
        rotationAccumulated = rotationAngle(at: date)
        anchor = date
        rotationAnchor = date
        running = next
    }
}
