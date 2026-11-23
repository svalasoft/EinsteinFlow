import Foundation

/// Persistent user navigation relative to the automatically framed camera.
/// Offset stays in world coordinates as the field rotates or keeps growing.
struct CameraNavigation: Equatable, Sendable {
    static let zoomRange = 0.25...16.0
    private(set) var offset = HatPoint(x: 0, y: 0)
    private(set) var zoom = 1.0
    private(set) var isManual = false

    func center(relativeTo automatic: HatPoint) -> HatPoint { automatic + offset }
    func span(relativeTo automatic: Double) -> Double { automatic / zoom }

    /// Use a copy captured at gesture start for cumulative drag translations,
    /// or call with incremental deltas. The field follows the screen-space drag.
    mutating func pan(screenDelta: CGSize, viewport: CGSize, automaticSpan: Double, angle: Double) {
        let width = Double(viewport.width), height = Double(viewport.height)
        let dx = Double(screenDelta.width), dy = Double(screenDelta.height)
        guard width > 0, height > 0, automaticSpan > 0,
              width.isFinite, height.isFinite, automaticSpan.isFinite,
              dx.isFinite, dy.isFinite, angle.isFinite else { return }
        let scale = min(width, height) / span(relativeTo: automaticSpan)
        guard scale > 0, scale.isFinite else { return }
        // Invert the camera's rotation and scale. Moving the camera opposite
        // this vector moves the visible field in the finger's drag direction.
        let cosine = cos(angle), sine = sin(angle)
        let worldX = (cosine * dx + sine * dy) / scale
        let worldY = (-sine * dx + cosine * dy) / scale
        let next = HatPoint(x: offset.x - worldX, y: offset.y - worldY)
        guard next.x.isFinite, next.y.isFinite else { return }
        if next != offset { isManual = true }
        offset = next
    }

    /// Factor is relative to the receiver's current zoom. A gesture-start copy
    /// lets the standard magnification gesture supply its cumulative factor.
    mutating func magnify(by factor: Double) {
        guard factor > 0, factor.isFinite else { return }
        let next = min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, zoom * factor))
        if next != zoom { isManual = true }
        zoom = next
    }

    mutating func reset() {
        offset = HatPoint(x: 0, y: 0)
        zoom = 1
        isManual = false
    }
}
