import Foundation

@main struct HatFieldChecks {
    static func main() {
        var checks = 0
        func require(_ name: String, _ value: @autoclosure () -> Bool) {
            guard value() else {
                FileHandle.standardError.write(Data(("FAIL: " + name + "\n").utf8)); exit(1)
            }
            checks += 1
        }
        func key(_ tile: HatTile) -> String {
            let x = tile.vertices.map(\.x).reduce(0, +) / 13
            let y = tile.vertices.map(\.y).reduce(0, +) / 13
            return "\(Int64((x * 100_000).rounded())),\(Int64((y * 100_000).rounded()))"
        }
        func window(x: Double, y: Double = 0) -> TraceBounds {
            TraceBounds(minX: x - 30, minY: y - 30, maxX: x + 30, maxY: y + 30)
        }
        func sampledCoverage(_ tiles: [HatTile], _ bounds: TraceBounds) -> Bool {
            // Offset the independent sample lattice to avoid polygon edges.
            for row in 0..<21 {
                for column in 0..<21 {
                    let point = HatPoint(x: bounds.minX + (Double(column) + 0.371) * bounds.width / 21,
                                         y: bounds.minY + (Double(row) + 0.619) * bounds.height / 21)
                    if tiles.filter({ $0.contains(point) }).count != 1 { return false }
                }
            }
            return true
        }
        let field = HatTiling.Field()
        let initialWindow = window(x: 0)
        let initial = field.tiles(in: initialWindow)
        require("A 60-unit window materializes about 1100 hats", (1050...1200).contains(initial.count))
        require("Initial query uses a small hierarchy", field.substitutions <= 6 && field.storedNodeCount <= 33)
        require("The initial rectangle has no sampled gaps or overlaps", sampledCoverage(initial, initialWindow))
        require("No query duplicates a hat", Set(initial.map(key)).count == initial.count)
        require("Queried hats retain 13 vertices and genuine area", initial.allSatisfy {
            $0.vertices.count == 13 && abs(abs($0.signedArea) - 2 * sqrt(3.0)) < 1e-7
        })
        require("Queries include both chiralities", initial.contains(where: \.reflected) && initial.contains { !$0.reflected })
        let anchors = Dictionary(uniqueKeysWithValues: initial.filter {
            $0.vertices.allSatisfy { abs($0.x) < 28 && abs($0.y) < 28 }
        }.map { (key($0), $0) })
        for (x, y) in [(24.0, 0.0), (192, 0), (-192, 96), (1024, -1024), (10_000, 0), (-100_000, 100_000)] {
            let bounds = window(x: x, y: y)
            let tiles = field.tiles(in: bounds)
            require("Window \(x),\(y) remains bounded", (1050...1200).contains(tiles.count))
            require("Window \(x),\(y) has complete non-overlapping coverage", sampledCoverage(tiles, bounds))
            require("Window \(x),\(y) has unique tiles", Set(tiles.map(key)).count == tiles.count)
        }
        let grown = Dictionary(uniqueKeysWithValues: field.tiles(in: initialWindow).map { (key($0), $0) })
        require("Expansion preserves all original interior hats", anchors.keys.allSatisfy { grown[$0] != nil })
        require("Expansion preserves exact source categories and chirality", anchors.allSatisfy { id, tile in
            grown[id]?.kind == tile.kind && grown[id]?.reflected == tile.reflected
        })
        require("Expansion preserves old world vertices within numeric tolerance", anchors.allSatisfy { id, tile in
            guard let other = grown[id] else { return false }
            return zip(tile.vertices, other.vertices).allSatisfy { hypot($0.x - $1.x, $0.y - $1.y) < 1e-6 }
        })
        require("Hierarchy memory grows with depth, not visited hats", field.storedNodeCount <= 9 + 4 * field.substitutions)
        require("Distant queries remain shallow", field.substitutions <= 14)
        for count in [168, 512, 2048] {
            let scene = TraceScene.make(tileCount: count)
            require("Finite preset \(count) returns every requested hat", scene.tiles.count == count)
            require("Finite preset \(count) contains genuine hats", scene.tiles.allSatisfy {
                abs($0.perimeter - 9.196152422706632) < 1e-7
            })
        }
        // Real endless queries filter out previously seen hats. The remaining
        // islands can be disconnected; travel must bridge them without a trap.
        let islands = initial.filter { tile in
            let x = tile.vertices.map(\.x).reduce(0, +) / 13
            return x < -20 || x > 20
        }
        let previous = HatPoint(x: -35, y: 4)
        let route = TraceScene.make(tiles: islands, tileCount: islands.count,
                                    startNear: previous, previousEnd: previous)
        require("Filtered disconnected frontier orders all remaining hats", route.tiles.count == islands.count)
        require("Filtered frontier starts near the previous endpoint", route.tiles[0].center.x < -20)
        print("Expandable field: \(checks) checks passed; \(initial.count) hats/window; \(field.substitutions) levels, \(field.storedNodeCount) stored nodes; 168/512/2048 presets verified.")
    }
}
