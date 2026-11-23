// Hat substitution geometry adapted from Craig S. Kaplan's hatviz (2023).
// See ThirdParty/hatviz-LICENSE.txt for the BSD 3-Clause license.
import Foundation

struct HatPoint: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    static func + (a: Self, b: Self) -> Self { Self(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: Self, b: Self) -> Self { Self(x: a.x - b.x, y: a.y - b.y) }
}

/// Axis-aligned world window shared by geometry queries and tracing cameras.
struct TraceBounds: Equatable, Sendable {
    let minX: Double
    let minY: Double
    let maxX: Double
    let maxY: Double
    var width: Double { maxX - minX }
    var height: Double { maxY - minY }
    var center: HatPoint { HatPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2) }

    init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX; self.minY = minY; self.maxX = maxX; self.maxY = maxY
    }
    init(points: [HatPoint]) {
        precondition(!points.isEmpty)
        minX = points.map(\.x).min()!
        minY = points.map(\.y).min()!
        maxX = points.map(\.x).max()!
        maxY = points.map(\.y).max()!
    }
    func contains(_ point: HatPoint, tolerance: Double = 1e-8) -> Bool {
        point.x >= minX - tolerance && point.x <= maxX + tolerance
            && point.y >= minY - tolerance && point.y <= maxY + tolerance
    }
    func intersects(_ other: Self) -> Bool {
        minX <= other.maxX && maxX >= other.minX && minY <= other.maxY && maxY >= other.minY
    }
    fileprivate var corners: [HatPoint] {
        [HatPoint(x: minX, y: minY), HatPoint(x: maxX, y: minY),
         HatPoint(x: maxX, y: maxY), HatPoint(x: minX, y: maxY)]
    }
}

enum HatKind: String, CaseIterable, Codable, Sendable {
    case reflected = "H1", h = "H", t = "T", p = "P", f = "F"
}

struct HatTile: Codable, Sendable {
    let kind: HatKind
    let vertices: [HatPoint]
    let reflected: Bool

    var signedArea: Double {
        zip(vertices, vertices.dropFirst() + vertices.prefix(1)).reduce(0) {
            $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y
        } * 0.5
    }

    func contains(_ p: HatPoint) -> Bool {
        var inside = false
        var j = vertices.count - 1
        for i in vertices.indices {
            let a = vertices[i], b = vertices[j]
            if (a.y > p.y) != (b.y > p.y),
               p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }
}

/// Genuine H/T/P/F substitution geometry, never a repeated texture cell.
/// Small finite fixtures can flatten a patch; Field expands a shared hierarchy
/// and materializes only finite windows for continuous exploration.
enum HatTiling {
    private static let h = sqrt(3.0) / 2
    static let outline: [HatPoint] = [(0, 0), (-1, -1), (0, -2), (2, -2),
        (2, -1), (4, -2), (5, -1), (4, 0), (3, 0), (2, 2), (0, 3),
        (0, 2), (-1, 2)].map { HatPoint(x: Double($0.0) + Double($0.1) / 2, y: Double($0.1) * h) }

    static func patch(substitutions: Int = 4) -> [HatTile] {
        precondition((0...5).contains(substitutions), "Use a bounded substitution depth.")
        var nodes = initialMetatiles()
        for _ in 0..<substitutions { nodes = metatiles(from: assemble(nodes)) }
        var result: [HatTile] = []
        nodes[.h]!.flatten(.identity, into: &result)
        return result
    }

    /// An expandable, genuine substitution tiling. Queries retain only a small
    /// hierarchy and the requested window; no enormous flat patch is allocated.
    /// Expand this instance on one executor, outside the animation frame loop.
    final class Field {
        private var metatiles: [HatKind: Node]
        private var root: Node
        private var transform: Affine
        private(set) var substitutions = 0

        init() {
            let initial = initialMetatiles()
            metatiles = initial
            root = initial[.h]!
            // Anchor the initial H metatile once. Later parents keep this exact
            // child in place, preserving tile positions across window changes.
            let shape = root.shape
            transform = .translation(HatPoint(x: -shape.map(\.x).reduce(0, +) / Double(shape.count),
                                              y: -shape.map(\.y).reduce(0, +) / Double(shape.count)))
        }

        /// Each level adds four shared metatiles. This count is independent of
        /// how many windows have been visited or hats have been materialized.
        var storedNodeCount: Int {
            var seen: Set<ObjectIdentifier> = []
            func visit(_ node: Node) {
                guard seen.insert(ObjectIdentifier(node)).inserted else { return }
                for child in node.children { visit(child.node) }
            }
            for node in metatiles.values { visit(node) }
            return seen.count
        }

        /// Returns all hats intersecting this finite window in stable world
        /// coordinates. Reusing a Field makes successive windows one tiling,
        /// including after the hierarchy grows. Tile order is not a draw route.
        func tiles(in bounds: TraceBounds) -> [HatTile] {
            precondition(bounds.width > 0 && bounds.height > 0
                && [bounds.minX, bounds.minY, bounds.maxX, bounds.maxY].allSatisfy(\.isFinite),
                "A tiling window must be finite and have positive dimensions.")
            let requiredArea = bounds.width * bounds.height
            while true {
                var result: [HatTile] = []
                root.collect(transform, intersecting: bounds, into: &result)
                // Supertile outlines are abstract polygonal guides; their true
                // hat boundary is irregular. Exact clipped area verifies the
                // complete requested rectangle before accepting a query.
                let coveredArea = result.reduce(0) { $0 + Self.clippedArea($1.vertices, to: bounds) }
                if abs(coveredArea - requiredArea) <= max(1e-7, requiredArea * 1e-9) {
                    return result
                }
                grow()
            }
        }

        private func grow() {
            let next = HatTiling.metatiles(from: assemble(metatiles))
            let parent = next[.h]!
            // The third H child rotates its parent ancestry by 120 degrees.
            // Repeating this ancestry surrounds the existing patch instead of
            // leaving a persistent one-sided boundary. Align the actual child
            // with the old root, preserving every previously generated hat.
            transform = transform * parent.children[2].transform.inverse
            metatiles = next
            root = parent
            substitutions += 1
        }

        private static func clippedArea(_ polygon: [HatPoint], to bounds: TraceBounds) -> Double {
            var polygon = polygon
            for edge in 0..<4 {
                guard !polygon.isEmpty else { return 0 }
                func coordinate(_ p: HatPoint) -> Double { edge < 2 ? p.x : p.y }
                let boundary = [bounds.minX, bounds.maxX, bounds.minY, bounds.maxY][edge]
                func inside(_ p: HatPoint) -> Bool {
                    edge % 2 == 0 ? coordinate(p) >= boundary : coordinate(p) <= boundary
                }
                func crossing(_ a: HatPoint, _ b: HatPoint) -> HatPoint {
                    let t = (boundary - coordinate(a)) / (coordinate(b) - coordinate(a))
                    return HatPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                }
                var clipped: [HatPoint] = [], previous = polygon.last!
                for point in polygon {
                    if inside(point) {
                        if !inside(previous) { clipped.append(crossing(previous, point)) }
                        clipped.append(point)
                    } else if inside(previous) { clipped.append(crossing(previous, point)) }
                    previous = point
                }
                polygon = clipped
            }
            guard polygon.count >= 3 else { return 0 }
            // Shift before the shoelace sum to retain precision in distant
            // moving windows; only local differences affect area.
            let origin = polygon[0]
            var twiceArea: Double = 0
            for index in polygon.indices {
                let a: HatPoint = polygon[index]
                let b: HatPoint = polygon[(index + 1) % polygon.count]
                let ax: Double = a.x - origin.x
                let ay: Double = a.y - origin.y
                let bx: Double = b.x - origin.x
                let by: Double = b.y - origin.y
                twiceArea = twiceArea + ax * by - bx * ay
            }
            return abs(twiceArea) * 0.5
        }
    }

    private struct Affine {
        let a, b, c, d, e, f: Double
        static let identity = Self(a: 1, b: 0, c: 0, d: 0, e: 1, f: 0)
        var determinant: Double { a * e - b * d }
        func point(_ p: HatPoint) -> HatPoint { HatPoint(x: a * p.x + b * p.y + c, y: d * p.x + e * p.y + f) }
        static func * (l: Self, r: Self) -> Self {
            Self(a: l.a * r.a + l.b * r.d, b: l.a * r.b + l.b * r.e,
                 c: l.a * r.c + l.b * r.f + l.c, d: l.d * r.a + l.e * r.d,
                 e: l.d * r.b + l.e * r.e, f: l.d * r.c + l.e * r.f + l.f)
        }
        var inverse: Self {
            let det = determinant
            return Self(a: e / det, b: -b / det, c: (b * f - c * e) / det,
                        d: -d / det, e: a / det, f: (c * d - a * f) / det)
        }
        static func translation(_ p: HatPoint) -> Self { Self(a: 1, b: 0, c: p.x, d: 0, e: 1, f: p.y) }
        static func rotation(_ angle: Double) -> Self {
            Self(a: cos(angle), b: -sin(angle), c: 0, d: sin(angle), e: cos(angle), f: 0)
        }
        static func rotation(around p: HatPoint, angle: Double) -> Self {
            translation(p) * rotation(angle) * translation(HatPoint(x: -p.x, y: -p.y))
        }
        static func segment(_ p: HatPoint, _ q: HatPoint) -> Self {
            Self(a: q.x - p.x, b: p.y - q.y, c: p.x, d: q.y - p.y, e: q.x - p.x, f: p.y)
        }
        static func match(_ p: HatPoint, _ q: HatPoint, to u: HatPoint, _ v: HatPoint) -> Self {
            segment(u, v) * segment(p, q).inverse
        }
    }

    private final class Node {
        var shape: [HatPoint]
        let kind: HatKind?
        var children: [(transform: Affine, node: Node)] = []
        private var cachedBounds: TraceBounds?
        init(_ shape: [HatPoint], kind: HatKind? = nil) { self.shape = shape; self.kind = kind }
        func add(_ transform: Affine, _ node: Node) {
            cachedBounds = nil
            children.append((transform, node))
        }
        var descendantBounds: TraceBounds {
            if let cachedBounds { return cachedBounds }
            let points = kind != nil ? shape : children.flatMap { child in
                child.node.descendantBounds.corners.map(child.transform.point)
            }
            let bounds = TraceBounds(points: points)
            cachedBounds = bounds
            return bounds
        }
        func collect(_ transform: Affine, intersecting query: TraceBounds, into result: inout [HatTile]) {
            let bounds = TraceBounds(points: descendantBounds.corners.map(transform.point))
            guard bounds.intersects(query) else { return }
            if let kind {
                let vertices = shape.map(transform.point)
                guard TraceBounds(points: vertices).intersects(query) else { return }
                result.append(HatTile(kind: kind, vertices: vertices, reflected: transform.determinant < 0))
            } else {
                for child in children {
                    child.node.collect(transform * child.transform, intersecting: query, into: &result)
                }
            }
        }
        func vertex(_ child: Int, _ vertex: Int) -> HatPoint {
            children[child].transform.point(children[child].node.shape[vertex])
        }
        func recenter() {
            cachedBounds = nil
            let center = HatPoint(x: -shape.map(\.x).reduce(0, +) / Double(shape.count),
                                  y: -shape.map(\.y).reduce(0, +) / Double(shape.count))
            shape = shape.map { $0 + center }
            children = children.map { (Affine.translation(center) * $0.transform, $0.node) }
        }
        func flatten(_ transform: Affine, into result: inout [HatTile]) {
            if let kind {
                result.append(HatTile(kind: kind, vertices: shape.map(transform.point), reflected: transform.determinant < 0))
            } else {
                for child in children { child.node.flatten(transform * child.transform, into: &result) }
            }
        }
    }

    private static func initialMetatiles() -> [HatKind: Node] {
        func p(_ x: Double, _ y: Double) -> HatPoint { HatPoint(x: x, y: y) }
        let hs = [p(0, 0), p(4, 0), p(4.5, h), p(2.5, 5*h), p(1.5, 5*h), p(-0.5, h)]
        let hn = Node(hs), tn = Node([p(0, 0), p(3, 0), p(1.5, 3*h)])
        let pn = Node([p(0, 0), p(4, 0), p(3, 2*h), p(-1, 2*h)])
        let fn = Node([p(0, 0), p(3, 0), p(3.5, h), p(3, 2*h), p(-1, 2*h)])
        let ordinary = Node(outline, kind: .h)
        hn.add(.match(outline[5], outline[7], to: hs[5], hs[0]), ordinary)
        hn.add(.match(outline[9], outline[11], to: hs[1], hs[2]), ordinary)
        hn.add(.match(outline[5], outline[7], to: hs[3], hs[4]), ordinary)
        hn.add(.translation(p(2.5, h)) * Affine(a: -0.5, b: -h, c: 0, d: h, e: -0.5, f: 0)
               * Affine(a: 0.5, b: 0, c: 0, d: 0, e: -0.5, f: 0), Node(outline, kind: .reflected))
        tn.add(Affine(a: 0.5, b: 0, c: 0.5, d: 0, e: 0.5, f: h), Node(outline, kind: .t))
        for (node, kind) in [(pn, HatKind.p), (fn, HatKind.f)] {
            let tile = Node(outline, kind: kind)
            node.add(Affine(a: 0.5, b: 0, c: 1.5, d: 0, e: 0.5, f: h), tile)
            node.add(.translation(p(0, 2*h)) * Affine(a: 0.5, b: h, c: 0, d: -h, e: 0.5, f: 0)
                     * Affine(a: 0.5, b: 0, c: 0, d: 0, e: 0.5, f: 0), tile)
        }
        return [.h: hn, .t: tn, .p: pn, .f: fn]
    }

    private enum Rule {
        case initial(HatKind), edge(Int, Int, HatKind, Int), bridge(Int, Int, Int, Int, HatKind, Int)
    }
    private static func assemble(_ shapes: [HatKind: Node]) -> Node {
        let rules: [Rule] = [.initial(.h), .edge(0, 0, .p, 2), .edge(1, 0, .h, 2),
            .edge(2, 0, .p, 2), .edge(3, 0, .h, 2), .edge(4, 4, .p, 2),
            .edge(0, 4, .f, 3), .edge(2, 4, .f, 3), .bridge(4, 1, 3, 2, .f, 0),
            .edge(8, 3, .h, 0), .edge(9, 2, .p, 0), .edge(10, 2, .h, 0),
            .edge(11, 4, .p, 2), .edge(12, 0, .h, 2), .edge(13, 0, .f, 3),
            .edge(14, 2, .f, 1), .edge(15, 3, .h, 4), .edge(8, 2, .f, 1),
            .edge(17, 3, .h, 0), .edge(18, 2, .p, 0), .edge(19, 2, .h, 2),
            .edge(20, 4, .f, 3), .edge(20, 0, .p, 2), .edge(22, 0, .h, 2),
            .edge(23, 4, .f, 3), .edge(23, 0, .f, 3), .edge(16, 0, .p, 2),
            .bridge(9, 4, 0, 2, .t, 2), .edge(4, 0, .f, 3)]
        let patch = Node([])
        for rule in rules {
            switch rule {
            case .initial(let kind): patch.add(.identity, shapes[kind]!)
            case .edge(let child, let edge, let kind, let newEdge):
                let old = patch.children[child]
                let p = old.transform.point(old.node.shape[(edge + 1) % old.node.shape.count])
                let q = old.transform.point(old.node.shape[edge])
                let shape = shapes[kind]!
                patch.add(.match(shape.shape[newEdge], shape.shape[(newEdge + 1) % shape.shape.count], to: p, q), shape)
            case .bridge(let childA, let vertexA, let childB, let vertexB, let kind, let edge):
                let shape = shapes[kind]!
                patch.add(.match(shape.shape[edge], shape.shape[(edge + 1) % shape.shape.count],
                                 to: patch.vertex(childB, vertexB), patch.vertex(childA, vertexA)), shape)
            }
        }
        return patch
    }

    private static func intersection(_ p: HatPoint, _ q: HatPoint, _ u: HatPoint, _ v: HatPoint) -> HatPoint {
        let divisor = (v.y-u.y)*(q.x-p.x) - (v.x-u.x)*(q.y-p.y)
        let a = ((v.x-u.x)*(p.y-u.y) - (v.y-u.y)*(p.x-u.x)) / divisor
        return HatPoint(x: p.x + a*(q.x-p.x), y: p.y + a*(q.y-p.y))
    }
    private static func metatiles(from patch: Node) -> [HatKind: Node] {
        let b1 = patch.vertex(8, 2), b2 = patch.vertex(21, 2)
        let rotated = Affine.rotation(around: b1, angle: -2 * .pi / 3).point(b2)
        let p7 = patch.vertex(7, 2), p25 = patch.vertex(25, 2)
        let corner = intersection(b1, rotated, patch.vertex(6, 2), p7)
        let rotate = Affine.rotation(-.pi / 3)
        let w1 = rotate.point(patch.vertex(6, 2) - corner), w2 = rotate.point(w1)
        let hs = [corner, b1, b1 + w1, patch.vertex(14, 2), patch.vertex(14, 2) - w2, patch.vertex(6, 2)]
        let hn = Node(hs), pn = Node([p7, p7 + (b1 - corner), b1, corner])
        let fn = Node([b2, patch.vertex(24, 2), patch.vertex(25, 0), p25, p25 + (corner - b1)])
        let a = hs[2], b = hs[1] + (hs[4] - hs[5])
        let tn = Node([b, Affine.rotation(around: b, angle: -.pi / 3).point(a), a])
        for (node, indices) in [(hn, [0, 9, 16, 27, 26, 6, 1, 8, 10, 15]),
                                (pn, [7, 2, 3, 4, 28]), (fn, [21, 20, 22, 23, 24, 25]), (tn, [11])] {
            for index in indices { let child = patch.children[index]; node.add(child.transform, child.node) }
            node.recenter()
        }
        return [.h: hn, .t: tn, .p: pn, .f: fn]
    }
}
