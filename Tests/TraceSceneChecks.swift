import Foundation

@main struct TraceSceneChecks {
    static func main() throws {
        var checks = 0
        func require(_ name: String, _ value: @autoclosure () -> Bool) {
            if !value() {
                FileHandle.standardError.write(Data(("FAIL: " + name + "\n").utf8))
                exit(1)
            }
            checks += 1
        }
        func distance(_ a: HatPoint, _ b: HatPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }
        let scene = TraceScene.make()
        require("The scene has168 hats", scene.tiles.count == 168)
        require("World bounds are finite and positive", scene.worldBounds.width.isFinite && scene.worldBounds.height.isFinite
            && scene.worldBounds.width > 0 && scene.worldBounds.height > 0)
        require("Every hat stays in world bounds", scene.tiles.allSatisfy { tile in tile.vertices.allSatisfy { scene.worldBounds.contains($0) } })
        require("The scene includes reflected hats", scene.tiles.contains(where: \.reflected))
        require("The scene includes ordinary hats", scene.tiles.contains { !$0.reflected })
        require("The first hat is near the construction origin", hypot(scene.tiles[0].center.x, scene.tiles[0].center.y) < 3)
        require("The initial laser point is on the first hat", scene.startPoint == scene.tiles[0].vertices[0])
        require("Each outline retains13 hat vertices", scene.tiles.allSatisfy { $0.vertices.count == 13 })
        require("Each outline retains the genuine hat area", scene.tiles.allSatisfy {
            abs(abs(HatTile(kind: $0.kind, vertices: $0.vertices, reflected: $0.reflected).signedArea) - 2 * sqrt(3.0)) < 1e-7
        })
        let centerKeys = scene.tiles.map { "\(Int(($0.center.x * 1e7).rounded())),\(Int(($0.center.y * 1e7).rounded()))" }
        require("Each hat is traced exactly once", Set(centerKeys).count == scene.tiles.count)
        let firstPerimeter = scene.tiles[0].perimeter
        require("Hats have congruent perimeter lengths", scene.tiles.allSatisfy { abs($0.perimeter - firstPerimeter) < 1e-7 })
        require("Trace begins at the first vertex", scene.tiles.allSatisfy { distance($0.point(at: 0).position, $0.vertices[0]) < 1e-9 })
        require("Trace returns to the starting vertex", scene.tiles.allSatisfy { distance($0.point(at: 1).position, $0.vertices[0]) < 1e-9 })
        require("Negative progress clamps to the start", scene.tiles.allSatisfy { distance($0.point(at: -1).position, $0.vertices[0]) < 1e-9 })
        require("Excess progress clamps to the end", scene.tiles.allSatisfy { distance($0.point(at: 2).position, $0.vertices[0]) < 1e-9 })
        require("NaN progress has a safe start", scene.tiles.allSatisfy { distance($0.point(at: .nan).position, $0.vertices[0]) < 1e-9 })
        require("Zero progress does not draw an edge", scene.tiles.allSatisfy { $0.outline(upTo: 0) == [$0.vertices[0]] })
        require("Completed paths have one closure point", scene.tiles.allSatisfy { $0.outline(upTo: 1).count == 14 })
        for progress in [0.0, 0.0001, 0.1, 0.3, 0.5, 0.9, 0.9999, 1.0] {
            require("Laser direction remains normalized at \(progress)", scene.tiles.allSatisfy {
                abs(hypot($0.point(at: progress).direction.x, $0.point(at: progress).direction.y) - 1) < 1e-9
            })
            require("Partial outline ends at the laser at \(progress)", scene.tiles.allSatisfy {
                distance($0.outline(upTo: progress).last!, $0.point(at: progress).position) < 1e-8
            })
        }
        var visited: Set<Int> = [0]
        func shareVertex(_ a: TraceTile, _ b: TraceTile) -> Bool {
            a.vertices.contains { p in b.vertices.contains { distance(p, $0) < 1e-7 } }
        }
        while true {
            let neighbors = scene.tiles.indices.filter { index in
                !visited.contains(index) && visited.contains { shareVertex(scene.tiles[$0], scene.tiles[index]) }
            }
            if neighbors.isEmpty { break }
            visited.formUnion(neighbors)
        }
        require("All selected hats form one connected cluster", visited.count == scene.tiles.count)
        let sharedSteps = zip(scene.tiles, scene.tiles.dropFirst()).filter { distance($0.vertices[0], $1.vertices[0]) < 1e-7 }.count
        let travel = zip(scene.tiles, scene.tiles.dropFirst()).map { distance($0.vertices[0], $1.vertices[0]) }
        let neighboringSteps = zip(scene.tiles, scene.tiles.dropFirst()).filter { shareVertex($0, $1) }.count
        print("Route: shared laser vertices \(sharedSteps); neighboring hats \(neighboringSteps); longest travel \(travel.max()!)")
        require("The route includes seamless shared-vertex transitions", sharedSteps > 0)
        require("Neighboring hats dominate the construction route", neighboringSteps > scene.tiles.count * 3 / 4)
        require("Fast travel starts at the previous closed outline", scene.tiles.indices.dropFirst().allSatisfy {
            distance(scene.travel(to: $0, at: 0).position, scene.tiles[$0 - 1].point(at: 1).position) < 1e-8
        })
        require("Fast travel finishes at the next outline", scene.tiles.indices.allSatisfy {
            distance(scene.travel(to: $0, at: 1).position, scene.tiles[$0].point(at: 0).position) < 1e-8
        })
        require("Travel stays in the construction viewport", scene.tiles.indices.allSatisfy {
            scene.worldBounds.contains(scene.travel(to: $0, at: 0.5).position)
        })
        require("Travel distances are finite", travel.allSatisfy(\.isFinite))
        let again = TraceScene.make()
        require("Scene construction is deterministic", zip(scene.tiles, again.tiles).allSatisfy { $0.vertices == $1.vertices })
        require("The one-hat scene is valid", TraceScene.make(tileCount: 1).tiles.count == 1)
        print("Trace checks: \(checks); hats: \(scene.tiles.count); bounds: \(scene.worldBounds.width)×\(scene.worldBounds.height); perimeter: \(firstPerimeter); shared transitions: \(sharedSteps)/\(scene.tiles.count-1); longest travel: \(travel.max()!)")
    }
}
