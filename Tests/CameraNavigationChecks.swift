import Foundation

@main struct CameraNavigationChecks {
    static func main() {
        var checks = 0
        func close(_ value: Double, _ expected: Double) -> Bool { abs(value - expected) < 1e-10 }
        func close(_ point: HatPoint, _ expected: HatPoint) -> Bool {
            close(point.x, expected.x) && close(point.y, expected.y)
        }
        func require(_ name: String, _ value: @autoclosure () -> Bool) {
            guard value() else {
                FileHandle.standardError.write(Data(("FAIL: " + name + "\n").utf8)); exit(1)
            }
            checks += 1
        }
        func project(_ point: HatPoint, navigation: CameraNavigation, center: HatPoint,
                     span: Double, viewport: CGSize, angle: Double) -> HatPoint {
            let center = navigation.center(relativeTo: center)
            let x = point.x - center.x, y = point.y - center.y
            let scale = min(Double(viewport.width), Double(viewport.height)) / navigation.span(relativeTo: span)
            return HatPoint(x: Double(viewport.width) / 2 + (cos(angle) * x - sin(angle) * y) * scale,
                            y: Double(viewport.height) / 2 + (sin(angle) * x + cos(angle) * y) * scale)
        }
        let automatic = HatPoint(x: 11, y: -8)
        let viewport = CGSize(width: 1000, height: 800)
        var navigation = CameraNavigation()
        require("Default navigation preserves automatic framing", navigation.center(relativeTo: automatic) == automatic
            && navigation.span(relativeTo: 80) == 80 && navigation.zoom == 1)
        require("A new camera follows automatic framing", !navigation.isManual)
        navigation.pan(screenDelta: CGSize(width: 100, height: -50), viewport: viewport, automaticSpan: 80, angle: 0)
        require("Unrotated pan moves the camera opposite the drag", close(navigation.offset, HatPoint(x: -10, y: 5)))
        require("An actual pan enters manual mode", navigation.isManual)
        require("Pan remains relative to the automatic camera", close(navigation.center(relativeTo: automatic), HatPoint(x: 1, y: -3)))
        require("Pan does not change zoom", navigation.zoom == 1 && navigation.span(relativeTo: 80) == 80)

        var quarterTurn = CameraNavigation()
        quarterTurn.pan(screenDelta: CGSize(width: 100, height: 0), viewport: viewport, automaticSpan: 80, angle: .pi / 2)
        require("A quarter-turn uses inverse camera rotation", close(quarterTurn.offset, HatPoint(x: 0, y: 10)))

        let point = HatPoint(x: 3.5, y: 4.25)
        for size in [CGSize(width: 1200, height: 700), CGSize(width: 700, height: 1200)] {
            for angle in [-2.4, 0.0, 0.73, 2.9] {
                var camera = CameraNavigation()
                camera.magnify(by: 2.5)
                let before = project(point, navigation: camera, center: automatic, span: 68, viewport: size, angle: angle)
                camera.pan(screenDelta: CGSize(width: 97, height: -43), viewport: size, automaticSpan: 68, angle: angle)
                let after = project(point, navigation: camera, center: automatic, span: 68, viewport: size, angle: angle)
                require("The field follows the same screen drag at angle \(angle) in \(size)",
                        close(after - before, HatPoint(x: 97, y: -43)))
            }
        }
        var zoomed = CameraNavigation()
        zoomed.magnify(by: 2)
        require("An actual zoom enters manual mode", zoomed.isManual)
        zoomed.pan(screenDelta: CGSize(width: 100, height: 0), viewport: viewport, automaticSpan: 80, angle: 0)
        require("Pan sensitivity includes the user's zoom", close(zoomed.offset, HatPoint(x: -5, y: 0)))
        require("Zoom is relative to the automatic span", zoomed.span(relativeTo: 80) == 40 && zoomed.span(relativeTo: 160) == 80)
        let savedOffset = zoomed.offset
        zoomed.magnify(by: 1.5)
        require("Magnification preserves the world pan offset", zoomed.offset == savedOffset && zoomed.zoom == 3)
        require("Automatic reframing preserves the same user world offset",
                zoomed.center(relativeTo: HatPoint(x: 100, y: 200)) == HatPoint(x: 95, y: 200))

        let base = navigation
        var dragUpdate = base
        dragUpdate.pan(screenDelta: CGSize(width: 120, height: 30), viewport: viewport, automaticSpan: 80, angle: 0)
        var nextDragUpdate = base
        nextDragUpdate.pan(screenDelta: CGSize(width: 240, height: 60), viewport: viewport, automaticSpan: 80, angle: 0)
        require("Gesture-start copies do not compound cumulative translations",
                close(nextDragUpdate.offset - base.offset, HatPoint(x: -24, y: -6)))
        require("Gesture updates leave their captured base unchanged", base == navigation)
        let still = navigation.offset
        _ = project(point, navigation: navigation, center: automatic, span: 80, viewport: viewport, angle: 2.1)
        require("Continuing automatic rotation does not rewrite world navigation", navigation.offset == still)

        var limits = CameraNavigation()
        limits.magnify(by: 100)
        require("Maximum zoom clamps at sixteen", limits.zoom == 16)
        limits.magnify(by: 2)
        require("Further magnification stays at the upper endpoint", limits.zoom == 16)
        limits.magnify(by: 0.0001)
        require("Minimum zoom clamps at one quarter", limits.zoom == 0.25)
        limits.magnify(by: 0.5)
        require("Further reduction stays at the lower endpoint", limits.zoom == 0.25)
        for factor in [0.0, -1, .nan, .infinity] { limits.magnify(by: factor) }
        require("Invalid magnification leaves navigation unchanged", limits.zoom == 0.25)
        let beforeInvalid = navigation
        navigation.pan(screenDelta: CGSize(width: .infinity, height: 1), viewport: viewport, automaticSpan: 80, angle: 0)
        navigation.pan(screenDelta: CGSize(width: 1, height: 1), viewport: CGSize(width: 0, height: 0), automaticSpan: 80, angle: 0)
        navigation.pan(screenDelta: CGSize(width: 1, height: 1), viewport: viewport, automaticSpan: 0, angle: 0)
        navigation.pan(screenDelta: CGSize(width: 1, height: 1), viewport: viewport, automaticSpan: 80, angle: .nan)
        require("Invalid drag inputs preserve navigation", navigation == beforeInvalid)

        var undonePan = CameraNavigation()
        undonePan.pan(screenDelta: CGSize(width: 100, height: -50), viewport: viewport, automaticSpan: 80, angle: 0)
        undonePan.pan(screenDelta: CGSize(width: -100, height: 50), viewport: viewport, automaticSpan: 80, angle: 0)
        require("Undoing a pan restores the position while staying manual", undonePan.offset == HatPoint(x: 0, y: 0)
            && undonePan.zoom == 1 && undonePan.isManual)
        undonePan.pan(screenDelta: CGSize(width: 0, height: 0), viewport: viewport, automaticSpan: 80, angle: 0)
        undonePan.magnify(by: 1)
        require("No-op gestures cannot leave manual mode", undonePan.isManual)
        var undoneZoom = CameraNavigation()
        undoneZoom.magnify(by: 2)
        undoneZoom.magnify(by: 0.5)
        require("Undoing zoom restores its scale while staying manual", undoneZoom.zoom == 1 && undoneZoom.isManual
            && undoneZoom.offset == HatPoint(x: 0, y: 0))
        require("Identity-valued manual navigation differs from automatic mode", undonePan != CameraNavigation()
            && undoneZoom != CameraNavigation())
        undoneZoom.reset()
        require("Only Center leaves manual mode after an undone zoom", !undoneZoom.isManual && undoneZoom == CameraNavigation())

        var untouched = CameraNavigation()
        untouched.pan(screenDelta: CGSize(width: 0, height: 0), viewport: viewport, automaticSpan: 80, angle: 0)
        untouched.magnify(by: 1)
        require("No-op input does not capture automatic framing", !untouched.isManual && untouched == CameraNavigation())
        untouched.pan(screenDelta: CGSize(width: .infinity, height: 1), viewport: viewport, automaticSpan: 80, angle: 0)
        untouched.magnify(by: .nan)
        require("Rejected input does not capture automatic framing", !untouched.isManual && untouched == CameraNavigation())
        navigation.reset()
        require("Center restores automatic framing and zoom", navigation == CameraNavigation()
            && !navigation.isManual && navigation.center(relativeTo: automatic) == automatic && navigation.span(relativeTo: 80) == 80)
        print("Camera navigation: \(checks) checks passed")
    }
}
