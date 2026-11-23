import Foundation

enum HatFieldLayout {
    static let substitutions = 4
    static let halfExtent = 25.0
    static let pixels = 3072
}

/// Spatial buckets keep full-crop coverage validation linear in sample count.
struct HatCoverage {
    private struct Cell: Hashable { let x: Int; let y: Int }
    private var buckets: [Cell: [Int]] = [:]
    private let tiles: [HatTile]
    private let cellSize = 4.0
    init(_ tiles: [HatTile]) {
        self.tiles = tiles
        for (index, tile) in tiles.enumerated() {
            let xs = tile.vertices.map(\.x), ys = tile.vertices.map(\.y)
            for x in Int(floor(xs.min()! / cellSize))...Int(floor(xs.max()! / cellSize)) {
                for y in Int(floor(ys.min()! / cellSize))...Int(floor(ys.max()! / cellSize)) {
                    buckets[Cell(x: x, y: y), default: []].append(index)
                }
            }
        }
    }
    func count(at point: HatPoint) -> Int {
        let key = Cell(x: Int(floor(point.x / cellSize)), y: Int(floor(point.y / cellSize)))
        return buckets[key, default: []].filter { tiles[$0].contains(point) }.count
    }
    func validateSquare(samples: Int = 160) -> (holes: Int, overlaps: Int) {
        var holes = 0, overlaps = 0
        let side = HatFieldLayout.halfExtent * 2
        // Irrational offsets avoid sampling exactly on shared polygon edges.
        for y in 0..<samples {
            for x in 0..<samples {
                let point = HatPoint(x: -side / 2 + (Double(x) + 0.38196601125) * side / Double(samples),
                                     y: -side / 2 + (Double(y) + 0.61803398875) * side / Double(samples))
                let count = count(at: point)
                holes += count == 0 ? 1 : 0
                overlaps += count > 1 ? 1 : 0
            }
        }
        return (holes, overlaps)
    }
}
