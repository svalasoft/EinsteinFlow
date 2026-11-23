import Foundation

struct TracePoint: Sendable {
    let position: HatPoint
    /// Unit tangent in world coordinates, suitable for an oriented laser head.
    let direction: HatPoint
}

struct TraceTile: Sendable {
    let vertices: [HatPoint]
    let center: HatPoint
    let bounds: TraceBounds
    let perimeter: Double
    let kind: HatKind
    let reflected: Bool
    let edgeLengths: [Double]

    fileprivate init(_ tile: HatTile, nearest start: HatPoint) {
        // Use one trace direction for both chiralities. Reflection remains a
        // geometric property of the tile, independent of traversal direction.
        let polygon = tile.signedArea < 0 ? Array(tile.vertices.reversed()) : tile.vertices
        let first = polygon.indices.min { lhs, rhs in
            let a = squaredDistance(polygon[lhs], start), b = squaredDistance(polygon[rhs], start)
            return abs(a - b) < 1e-10 ? lhs < rhs : a < b
        }!
        let ordered = Array(polygon[first...]) + Array(polygon[..<first])
        vertices = ordered
        center = polygonCentroid(tile.vertices)
        bounds = TraceBounds(points: vertices)
        kind = tile.kind
        reflected = tile.reflected
        let lengths = ordered.indices.map { i in
            let a = ordered[i], b = ordered[(i + 1) % ordered.count]
            return hypot(b.x - a.x, b.y - a.y)
        }
        edgeLengths = lengths
        perimeter = lengths.reduce(0, +)
    }

    /// Arc-length parameterization keeps the beam speed constant on short and
    /// long sides. Progress 1 lands exactly back at the first vertex.
    func point(at fraction: Double) -> TracePoint {
        let fraction = normalizedTraceFraction(fraction)
        var remaining = fraction * perimeter
        for i in vertices.indices {
            let a = vertices[i], b = vertices[(i + 1) % vertices.count]
            let length = edgeLengths[i]
            if remaining < length || i == vertices.count - 1 {
                let t = min(1, max(0, remaining / length))
                return TracePoint(position: HatPoint(x: a.x + (b.x - a.x) * t,
                                                     y: a.y + (b.y - a.y) * t),
                    direction: HatPoint(x: (b.x - a.x) / length, y: (b.y - a.y) / length))
            }
            remaining -= length
        }
        preconditionFailure("A hat must have a nonempty outline.")
    }

    /// Vertex list for the currently drawn portion, ending at point(at:).
    /// Completed hats can use the thirteen vertices with a closed path.
    func outline(upTo fraction: Double) -> [HatPoint] {
        let fraction = normalizedTraceFraction(fraction)
        if fraction == 0 { return [vertices[0]] }
        var result = [vertices[0]], remaining = fraction * perimeter
        for i in vertices.indices {
            let a = vertices[i], b = vertices[(i + 1) % vertices.count], length = edgeLengths[i]
            if remaining < length {
                result.append(HatPoint(x: a.x + (b.x - a.x) * remaining / length,
                                       y: a.y + (b.y - a.y) * remaining / length))
                return result
            }
            result.append(b)
            remaining -= length
        }
        return result
    }
}

/// The construction route is prepared once. Rendering only looks up one hat
/// and its perimeter progress; it never searches or regenerates the tiling.
struct TraceScene: Sendable {
    let tiles: [TraceTile]
    let center: HatPoint
    let worldBounds: TraceBounds
    var startPoint: HatPoint { tiles[0].vertices[0] }

    /// A short travel phase connects closed outlines without teleporting the
    /// beam. A shared endpoint simply keeps the head in place for that phase.
    func travel(to index: Int, at fraction: Double) -> TracePoint {
        precondition(tiles.indices.contains(index))
        let destination = tiles[index].vertices[0]
        let source = index == 0 ? destination : tiles[index - 1].vertices[0]
        let t = normalizedTraceFraction(fraction)
        let length = hypot(destination.x - source.x, destination.y - source.y)
        return TracePoint(position: HatPoint(x: source.x + (destination.x - source.x) * t,
                                             y: source.y + (destination.y - source.y) * t),
            direction: length > 1e-10
                ? HatPoint(x: (destination.x - source.x) / length, y: (destination.y - source.y) / length)
                : tiles[index].point(at: 0).direction)
    }

    static func make(tileCount: Int = 168) -> Self {
        precondition((1...8192).contains(tileCount), "Keep each visible construction window bounded.")
        let field = HatTiling.Field()
        let radius = sqrt(Double(tileCount) * 3.4641016151377544 / .pi) * 1.5 + 6
        let patch = field.tiles(in: TraceBounds(minX: -radius, minY: -radius, maxX: radius, maxY: radius))
        return make(tiles: patch, tileCount: tileCount, startNear: HatPoint(x: 0, y: 0))
    }

    /// Orders a connected cluster from queried geometry, starting near the
    /// requested point and joining disconnected input islands when necessary.
    static func make(tiles patch: [HatTile], tileCount: Int, startNear origin: HatPoint,
                     previousEnd: HatPoint? = nil) -> Self {
        precondition(tileCount > 0 && tileCount <= patch.count)
        let centers = patch.map { polygonCentroid($0.vertices) }
        let first = patch.indices.min { a, b in
            let x = squaredDistance(centers[a], origin), y = squaredDistance(centers[b], origin)
            return abs(x - y) < 1e-10 ? a < b : x < y
        }!
        let adjacent = adjacency(patch)
        var selected: Set<Int> = [first], frontier = adjacent[first]
        // Grow one connected cluster, choosing the most central available hat.
        while selected.count < tileCount {
            // A moving window can omit hats rendered in an earlier window,
            // leaving disconnected islands. Travel bridges those islands.
            let candidates = frontier.isEmpty ? Set(patch.indices).subtracting(selected) : frontier
            let next = candidates.min { a, b in
                let x = squaredDistance(centers[a], origin), y = squaredDistance(centers[b], origin)
                return abs(x - y) < 1e-10 ? a < b : x < y
            }!
            frontier.remove(next)
            selected.insert(next)
            frontier.formUnion(adjacent[next].subtracting(selected))
        }
        let bounds = TraceBounds(points: selected.flatMap { patch[$0].vertices })
        var remaining = selected, current = first
        var previousEnd = previousEnd ?? HatPoint(x: centers[first].x, y: centers[first].y - 2)
        var ordered: [TraceTile] = []
        ordered.reserveCapacity(tileCount)
        while !remaining.isEmpty {
            let tile = TraceTile(patch[current], nearest: previousEnd)
            ordered.append(tile)
            remaining.remove(current)
            previousEnd = tile.vertices[0]
            guard !remaining.isEmpty else { break }
            let neighbors = adjacent[current].intersection(remaining)
            let candidates = neighbors.isEmpty ? remaining : neighbors
            current = candidates.min { a, b in
                let x = patch[a].vertices.map { squaredDistance($0, previousEnd) }.min()!
                let y = patch[b].vertices.map { squaredDistance($0, previousEnd) }.min()!
                if abs(x - y) >= 1e-9 { return x < y }
                let radialA = squaredDistance(centers[a], origin), radialB = squaredDistance(centers[b], origin)
                return abs(radialA - radialB) < 1e-10 ? a < b : radialA < radialB
            }!
        }
        return TraceScene(tiles: ordered, center: bounds.center, worldBounds: bounds)
    }

    private struct VertexKey: Hashable {
        let x: Int64
        let y: Int64
        init(_ p: HatPoint) { x = Int64((p.x * 1_000_000).rounded()); y = Int64((p.y * 1_000_000).rounded()) }
    }
    private static func adjacency(_ patch: [HatTile]) -> [Set<Int>] {
        var owners: [VertexKey: [Int]] = [:]
        for (index, tile) in patch.enumerated() {
            for vertex in tile.vertices { owners[VertexKey(vertex), default: []].append(index) }
        }
        var graph = Array(repeating: Set<Int>(), count: patch.count)
        for indices in owners.values {
            for index in indices { graph[index].formUnion(indices.filter { $0 != index }) }
        }
        return graph
    }
}

private func squaredDistance(_ a: HatPoint, _ b: HatPoint) -> Double {
    (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
}
private func normalizedTraceFraction(_ value: Double) -> Double {
    if value.isNaN { return 0 }
    return min(1, max(0, value))
}
private func polygonCentroid(_ points: [HatPoint]) -> HatPoint {
    let origin = points[0]
    var twiceArea = 0.0, x = 0.0, y = 0.0
    for index in points.indices {
        let a = points[index] - origin, b = points[(index + 1) % points.count] - origin
        let cross = a.x * b.y - b.x * a.y
        twiceArea += cross
        x += (a.x + b.x) * cross
        y += (a.y + b.y) * cross
    }
    return HatPoint(x: origin.x + x / (3 * twiceArea), y: origin.y + y / (3 * twiceArea))
}
