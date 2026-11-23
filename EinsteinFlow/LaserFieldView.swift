import Foundation
import SwiftUI

// Oversample layout coordinates so even 16× user zoom keeps pixel rounding
// below a screen point. Only the clipped viewport is rasterized.
private let drawingUnit = 1024.0

/// Cache visible hats in color groups, sealing batches of 64. A stable camera
/// window updates only its current batch; the construction keeps every hat.
private final class FieldPaths {
    var guides = Path()
    var sealed = Array(repeating: Path(), count: 5)
    var current = Array(repeating: Path(), count: 5)
    private var batchCount = 0
    private var paintedCount = 0
    private var firstID: Int?
    private var geometryRevision = -1
    private var bounds: TraceBounds?
    private var cycle = -1
    private var window: TraceBounds?

    func update(_ frame: ConstructionFrame, visibleIn viewport: TraceBounds) {
        // Quantize a padded window so rotation does not rebuild cached paths
        // for every subpixel change. Keep every hat in the construction model.
        let useWindow = viewport.width * viewport.height < frame.bounds.width * frame.bounds.height * 0.8
        let step = 0.5
        let nextWindow: TraceBounds? = useWindow ? TraceBounds(
            minX: floor(viewport.minX / step) * step, minY: floor(viewport.minY / step) * step,
            maxX: ceil(viewport.maxX / step) * step, maxY: ceil(viewport.maxY / step) * step) : nil
        let geometryChanged = geometryRevision != frame.geometryRevision || bounds != frame.bounds || window != nextWindow
        let completed = nextWindow.map { area in frame.completed.filter { $0.tile.bounds.intersects(area) } } ?? frame.completed
        if geometryChanged {
            guides = Path()
            for tile in frame.guides where nextWindow == nil || tile.bounds.intersects(nextWindow!) {
                guides.addPath(path(tile, in: frame.bounds))
            }
            geometryRevision = frame.geometryRevision
            bounds = frame.bounds
            window = nextWindow
        }
        if geometryChanged || cycle != frame.cycle || firstID != completed.first?.id || paintedCount > completed.count {
            sealed = Array(repeating: Path(), count: 5)
            current = Array(repeating: Path(), count: 5)
            paintedCount = 0
            batchCount = 0
            cycle = frame.cycle
            firstID = completed.first?.id
        }
        for hat in completed.dropFirst(paintedCount) {
            current[Self.group(hat.tile.kind)].addPath(path(hat.tile, in: frame.bounds))
            batchCount += 1
            if batchCount == 64 {
                for group in 0..<5 { sealed[group].addPath(current[group]) }
                current = Array(repeating: Path(), count: 5)
                batchCount = 0
            }
        }
        paintedCount = completed.count
    }

    private func path(_ tile: TraceTile, in bounds: TraceBounds) -> Path {
        var result = Path()
        result.addLines(tile.vertices.map {
            CGPoint(x: ($0.x - bounds.minX) * drawingUnit, y: ($0.y - bounds.minY) * drawingUnit)
        })
        result.closeSubpath()
        return result
    }

    private static func group(_ kind: HatKind) -> Int {
        switch kind {
        case .reflected: return 0
        case .h: return 1
        case .t: return 2
        case .p: return 3
        case .f: return 4
        }
    }
}

private struct FieldCamera {
    let size: CGSize
    let center: HatPoint
    let span: Double
    let angle: Double
    var scale: CGFloat { max(1, min(size.width, size.height)) / span }

    func rotate(_ point: HatPoint) -> CGSize {
        CGSize(width: cos(angle) * point.x - sin(angle) * point.y,
               height: sin(angle) * point.x + cos(angle) * point.y)
    }

    func project(_ point: HatPoint) -> CGSize {
        let rotated = rotate(point - center)
        return CGSize(width: size.width / 2 + rotated.width * scale,
                      height: size.height / 2 + rotated.height * scale)
    }

    func visibleBounds(padding: Double = 4) -> TraceBounds {
        let halfWidth = Double(size.width) / 2 + padding
        let halfHeight = Double(size.height) / 2 + padding
        let cosine = abs(cos(angle)), sine = abs(sin(angle))
        let x = (cosine * halfWidth + sine * halfHeight) / scale
        let y = (sine * halfWidth + cosine * halfHeight) / scale
        return TraceBounds(minX: center.x - x, minY: center.y - y,
                           maxX: center.x + x, maxY: center.y + y)
    }
}

private struct RenderFrame {
    let construction: ConstructionFrame
    let guides: Path
    let sealed: [Path]
    let current: [Path]
    let camera: FieldCamera
    let visibleCutters: [ActiveCut]
    let torchCutters: [ActiveCut]
}

struct CameraInputContext {
    let viewport: CGSize
    let automaticSpan: Double
    let angle: Double
}

/// TimelineView requests a value snapshot; construction and drawing caches stay
/// in this model without publishing state during a SwiftUI update.
final class LaserFieldModel {
    private let construction = LaserConstruction()
    private let paths = FieldPaths()
    private var center = HatPoint(x: 0, y: 0)
    private var span = 11.0
    private var initialCenter = HatPoint(x: 0, y: 0)
    private var lastTime: Double?
    private var lastCycle = -1
    private var lastSize: FlowFieldSize?
    private var previewOffset = 0.0
    private var previousAutomaticCenter: HatPoint?
    private var previousAutomaticSpan = 11.0
    private var manualBase: (center: HatPoint, span: Double)?
    private(set) var cameraInputContext: CameraInputContext?

    fileprivate func frame(size: CGSize, time: Double, cutters: Int, fieldSize: FlowFieldSize, rotation: Double,
                           navigation: CameraNavigation,
                           reducedMotion: Bool) -> RenderFrame {
        if lastTime == nil, reducedMotion {
            // Show a composed still on an initial Reduce Motion launch, then
            // preserve it if the user later enables animation.
            for second in 0...36 {
                _ = construction.frame(at: Double(second), cutterCount: cutters, fieldSize: fieldSize)
            }
            previewOffset = 36
        }
        let constructionTime = time + previewOffset
        let scene = construction.frame(at: constructionTime, cutterCount: cutters, fieldSize: fieldSize)
        let delta = min(1, max(0, constructionTime - (lastTime ?? constructionTime)))
        if lastSize != fieldSize || lastCycle != scene.cycle {
            initialCenter = scene.cutters.first?.tile.center ?? scene.guides.first?.center ?? scene.framing.center
            let stillPreview = lastTime == nil && reducedMotion
            center = stillPreview ? scene.framing.center : initialCenter
            span = stillPreview ? max(11, hypot(scene.framing.width, scene.framing.height) * 1.16) : 11
            lastCycle = scene.cycle
            lastSize = fieldSize
        }
        let reset = sqrt(max(0, 1 - scene.fade))
        let ease = reset * reset * (3 - 2 * reset)
        let target = HatPoint(x: scene.framing.center.x + (initialCenter.x - scene.framing.center.x) * ease,
                              y: scene.framing.center.y + (initialCenter.y - scene.framing.center.y) * ease)
        let targetSpan = max(11, hypot(scene.framing.width, scene.framing.height) * 1.16)
        let blend = 1 - exp(-delta * 5)
        center = HatPoint(x: center.x + (target.x - center.x) * blend,
                          y: center.y + (target.y - center.y) * blend)
        span += (targetSpan + (11 - targetSpan) * ease - span) * blend
        // Keep heads visible while smooth framing catches up to a new frontier.
        for cut in scene.cutters {
            span = max(span, hypot(cut.position.x - center.x, cut.position.y - center.y) * 2.18)
        }
        lastTime = constructionTime
        let angle = reducedMotion ? 0.25 : rotation
        if navigation.isManual {
            if manualBase == nil {
                manualBase = (previousAutomaticCenter ?? center, previousAutomaticSpan)
            }
        } else {
            manualBase = nil
        }
        let baseCenter = manualBase?.center ?? center
        let baseSpan = manualBase?.span ?? span
        previousAutomaticCenter = center
        previousAutomaticSpan = span
        cameraInputContext = CameraInputContext(viewport: size, automaticSpan: baseSpan, angle: angle)
        let camera = FieldCamera(size: size, center: navigation.center(relativeTo: baseCenter),
                                 span: navigation.span(relativeTo: baseSpan), angle: angle)
        let visible = camera.visibleBounds()
        paths.update(scene, visibleIn: visible)
        let visibleCutters = scene.cutters.filter { $0.tile.bounds.intersects(visible) }
        let torchCutters = scene.cutters.filter {
            let point = camera.project($0.position)
            return point.width >= -110 && point.height >= -110
                && point.width <= size.width + 110 && point.height <= size.height + 110
        }
        return RenderFrame(construction: scene, guides: paths.guides, sealed: paths.sealed,
                           current: paths.current, camera: camera,
                           visibleCutters: visibleCutters, torchCutters: torchCutters)
    }
}

struct LaserFieldView: View {
    let size: CGSize
    let time: TimeInterval
    let palette: Int
    let reducedMotion: Bool
    let cutterCount: Int
    let fieldSize: FlowFieldSize
    let rotation: Double
    let navigation: CameraNavigation
    let model: LaserFieldModel

    var body: some View {
        let frame = model.frame(size: size, time: time, cutters: cutterCount,
                                fieldSize: fieldSize, rotation: rotation, navigation: navigation,
                                reducedMotion: reducedMotion)
        return Group {
            if !reducedMotion && !frame.torchCutters.isEmpty {
                surface(frame)
                    .compositingGroup()
                    .layerEffect(torch(frame), maxSampleOffset: CGSize(width: 3, height: 3))
                    .clipped()
            } else {
                surface(frame)
            }
        }
    }

    private func surface(_ frame: RenderFrame) -> some View {
        let bounds = frame.construction.bounds
        let fieldCenter = frame.camera.project(bounds.center)
        return ZStack {
            Color(red: 0.008, green: 0.022, blue: 0.04)
            world(frame)
                .frame(width: bounds.width * drawingUnit, height: bounds.height * drawingUnit)
                .scaleEffect(frame.camera.scale / drawingUnit)
                .rotationEffect(.radians(frame.camera.angle))
                .position(x: fieldCenter.width, y: fieldCenter.height)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func torch(_ frame: RenderFrame) -> Shader {
        // Preserve each head's shader slot/particle seed while panning. A
        // culled head costs only the shader's zero-power early return.
        var heads = frame.construction.cutters.map { cut -> (CGSize, CGSize, Float) in
            let visible = frame.torchCutters.contains { $0.id == cut.id }
            return (frame.camera.project(cut.position), frame.camera.rotate(cut.direction),
             reducedMotion || !visible ? 0 : Float(cut.power * frame.construction.fade))
        }
        let count = heads.count
        while heads.count < 8 { heads.append((.zero, .zero, 0)) }
        func vector(_ index: Int) -> Shader.Argument {
            .float4(Float(heads[index].0.width), Float(heads[index].0.height),
                    Float(heads[index].1.width), Float(heads[index].1.height))
        }
        return ShaderLibrary.default.einsteinFlow(
            .float2(size), .float4(Float(time), Float(palette), Float(count), 0),
            vector(0), vector(1), vector(2), vector(3), vector(4), vector(5), vector(6), vector(7),
            .float4(heads[0].2, heads[1].2, heads[2].2, heads[3].2),
            .float4(heads[4].2, heads[5].2, heads[6].2, heads[7].2))
    }

    private func world(_ frame: RenderFrame) -> some View {
        let scene = frame.construction
        let width = scene.bounds.width * drawingUnit, height = scene.bounds.height * drawingUnit
        let scale = frame.camera.scale / drawingUnit
        return ZStack(alignment: .topLeading) {
            frame.guides.stroke(Color(red: 0.25, green: 0.56, blue: 0.63).opacity(0.15 * scene.fade), lineWidth: 0.65 / scale)
                .frame(width: width, height: height, alignment: .topLeading)
            ForEach(0..<5) { group in
                if !frame.sealed[group].isEmpty {
                    frame.sealed[group].fill(faceColors[group].opacity(scene.fade * 0.9))
                        .frame(width: width, height: height, alignment: .topLeading)
                        .overlay(frame.sealed[group].stroke(Color.black.opacity(scene.fade * 0.7), lineWidth: 0.85 / scale))
                }
                if !frame.current[group].isEmpty {
                    frame.current[group].fill(faceColors[group].opacity(scene.fade * 0.9))
                        .frame(width: width, height: height, alignment: .topLeading)
                        .overlay(frame.current[group].stroke(Color.black.opacity(scene.fade * 0.7), lineWidth: 0.85 / scale))
                }
            }
            ForEach(frame.visibleCutters, id: \.id) { cut in
                let active = partial(cut.tile, from: 0, to: cut.cut, in: scene.bounds)
                let trail = partial(cut.tile, from: max(0, cut.cut - 0.22), to: cut.cut, in: scene.bounds)
                active.stroke(Color(red: 1, green: 0.36, blue: 0.11).opacity(scene.fade * 0.4),
                              style: StrokeStyle(lineWidth: 6 / scale, lineCap: .round, lineJoin: .round))
                    .frame(width: width, height: height, alignment: .topLeading)
                active.stroke(Color(red: 1, green: 0.67, blue: 0.28).opacity(scene.fade * 0.9),
                              style: StrokeStyle(lineWidth: 1.7 / scale, lineCap: .round, lineJoin: .round))
                    .frame(width: width, height: height, alignment: .topLeading)
                trail.stroke(Color.white.opacity(scene.fade),
                             style: StrokeStyle(lineWidth: 1.3 / scale, lineCap: .round, lineJoin: .round))
                    .frame(width: width, height: height, alignment: .topLeading)
            }
        }
    }

    private var faceColors: [Color] {
        if palette == 1 {
            return [Color(red: 1, green: 0.54, blue: 0.22), Color(red: 0.40, green: 0.30, blue: 0.88),
                    Color(red: 0.89, green: 0.25, blue: 0.57), Color(red: 0.10, green: 0.67, blue: 0.86),
                    Color(red: 0.22, green: 0.82, blue: 0.60)]
        }
        if palette == 2 {
            return [Color(red: 0.91, green: 0.72, blue: 0.41), Color(red: 0.87, green: 0.91, blue: 0.87),
                    Color(red: 0.54, green: 0.72, blue: 0.79), Color(red: 0.28, green: 0.53, blue: 0.65),
                    Color(red: 0.68, green: 0.82, blue: 0.81)]
        }
        return [Color(red: 1, green: 0.66, blue: 0.28), Color(red: 0.08, green: 0.57, blue: 0.58),
                Color(red: 0.43, green: 0.33, blue: 0.77), Color(red: 0.14, green: 0.73, blue: 0.70),
                Color(red: 0.08, green: 0.35, blue: 0.48)]
    }

    private func partial(_ tile: TraceTile, from start: Double, to end: Double, in bounds: TraceBounds) -> Path {
        var result = Path()
        guard end > start else { return result }
        let lower = start * tile.perimeter, upper = end * tile.perimeter
        var distance = 0.0
        var begun = false
        for index in tile.vertices.indices {
            let a = tile.vertices[index], b = tile.vertices[(index + 1) % tile.vertices.count]
            let length = tile.edgeLengths[index]
            let lo = max(lower, distance), hi = min(upper, distance + length)
            if hi > lo {
                func point(_ fraction: Double) -> CGPoint {
                    CGPoint(x: (a.x + (b.x - a.x) * fraction - bounds.minX) * drawingUnit,
                            y: (a.y + (b.y - a.y) * fraction - bounds.minY) * drawingUnit)
                }
                if !begun { result.move(to: point((lo - distance) / length)); begun = true }
                result.addLine(to: point((hi - distance) / length))
            }
            distance += length
        }
        return result
    }
}
