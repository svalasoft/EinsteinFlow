import Foundation

@main struct HatGeometryChecks {
    static func main() throws {
        var checks = 0
        func require(_ name: String, _ value: @autoclosure () -> Bool) {
            precondition(value(), name)
            checks += 1
        }
        let expected = [4, 25, 169, 1156, 7921]
        let unitEdges = HatTiling.outline.indices.map { index -> Double in
            let a = HatTiling.outline[index], b = HatTiling.outline[(index + 1) % 13]
            return hypot(a.x - b.x, a.y - b.y) / 2
        }
        var final: [HatTile] = []
        for depth in 0...4 {
            let tiles = HatTiling.patch(substitutions: depth)
            require("Substitution count at level \(depth)", tiles.count == expected[depth])
            require("Every tile retains thirteen vertices", tiles.allSatisfy { $0.vertices.count == 13 })
            require("Coordinates are finite", tiles.allSatisfy { $0.vertices.allSatisfy { $0.x.isFinite && $0.y.isFinite } })
            let area = abs(tiles[0].signedArea)
            require("The hats are congruent", tiles.allSatisfy { abs(abs($0.signedArea) - area) < 1e-7 })
            require("The hierarchy includes both chiralities", tiles.contains(where: \.reflected) && tiles.contains { !$0.reflected })
            require("Only H1 tiles are reflected", tiles.allSatisfy { $0.reflected == ($0.kind == .reflected) })
            require("Every edge retains the original hat length", tiles.allSatisfy { tile in
                tile.vertices.indices.allSatisfy { index in
                    let a = tile.vertices[index], b = tile.vertices[(index + 1) % 13]
                    return abs(hypot(a.x - b.x, a.y - b.y) - unitEdges[index]) < 1e-7
                }
            })
            final = tiles
        }
        let centroids = final.map { tile in
            let x = tile.vertices.map(\.x).reduce(0, +) / 13
            let y = tile.vertices.map(\.y).reduce(0, +) / 13
            return "\(Int((x * 1e7).rounded())),\(Int((y * 1e7).rounded()))"
        }
        require("No duplicate hat placements", Set(centroids).count == final.count)
        require("Each of the five construction categories is represented", Set(final.map(\.kind)) == Set(HatKind.allCases))
        let coverage = HatCoverage(final).validateSquare(samples: 240)
        require("The baked square has no holes", coverage.holes == 0)
        require("The baked square has no overlapping interiors", coverage.overlaps == 0)
        let x = final.flatMap(\.vertices).map(\.x), y = final.flatMap(\.vertices).map(\.y)
        print("Checks: \(checks); tiles: \(final.count); area: \(abs(final[0].signedArea)); bounds: \(x.min()!)...\(x.max()!), \(y.min()!)...\(y.max()!)")
        if CommandLine.arguments.contains("--json") {
            let data = try JSONEncoder().encode(final)
            try data.write(to: URL(fileURLWithPath: "/tmp/einstein-hats.json"))
        }
    }
}
