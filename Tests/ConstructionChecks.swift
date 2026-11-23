import Foundation

@main struct ConstructionChecks {
    static func main() {
        var checks = 0
        func require(_ name: String, _ value: @autoclosure () -> Bool) {
            guard value() else {
                FileHandle.standardError.write(Data(("FAIL: " + name + "\n").utf8)); exit(1)
            }
            checks += 1
        }
        func key(_ tile: TraceTile) -> String {
            let count = Double(tile.vertices.count)
            let x = tile.vertices.reduce(0.0) { $0 + $1.x } / count
            let y = tile.vertices.reduce(0.0) { $0 + $1.y } / count
            return "\(Int64((x * 100_000).rounded())),\(Int64((y * 100_000).rounded()))"
        }
        func finite(_ value: HatPoint) -> Bool { value.x.isFinite && value.y.isFinite }
        func contains(_ outer: TraceBounds, _ inner: TraceBounds) -> Bool {
            outer.minX <= inner.minX + 1e-8 && outer.minY <= inner.minY + 1e-8
                && outer.maxX >= inner.maxX - 1e-8 && outer.maxY >= inner.maxY - 1e-8
        }
        func structurallyValid(_ frame: ConstructionFrame) -> Bool {
            let ids = frame.completed.map(\.id) + frame.cutters.map(\.id)
            let tiles = frame.completed.map(\.tile) + frame.cutters.map(\.tile)
            return Set(ids).count == ids.count && Set(tiles.map(key)).count == tiles.count
                && frame.cutters.allSatisfy {
                    (0...1).contains($0.cut) && (0...1).contains($0.power)
                        && finite($0.position) && finite($0.direction)
                        && abs(hypot($0.direction.x, $0.direction.y) - 1) < 1e-8
                }
                && tiles.allSatisfy { contains(frame.bounds, $0.bounds) && contains(frame.framing, $0.bounds) }
                && (0...1).contains(frame.fade)
        }

        require("The four finite presets expose stable titles",
            FlowFieldSize.allCases.map(\.title) == ["168 hats", "512 hats", "1,024 hats", "2,048 hats"]
                && FlowFieldSize.allCases.map(\.rawValue) == [168, 512, 1024, 2048])
        let workers = LaserConstruction()
        let initial = workers.frame(at: 0, cutterCount: 8, fieldSize: .small)
        require("Eight workers receive eight different hats", initial.cutters.count == 8 && structurallyValid(initial))
        require("The finite pool holds exactly 168 genuine hats", initial.guides.count == 168
            && Set(initial.guides.map(key)).count == 168
            && initial.guides.allSatisfy { abs($0.perimeter - 9.196152422706632) < 1e-7 })
        require("Initial framing includes the separated active construction sites", initial.cutters.allSatisfy {
            contains(initial.framing, $0.tile.bounds)
        })
        let travel = workers.frame(at: 0.02, cutterCount: 8, fieldSize: .small)
        require("The first 14 percent is travel before any outline", travel.completed.isEmpty
            && travel.cutters.allSatisfy { $0.cut == 0 && $0.power < 1 })
        let tracing = workers.frame(at: 0.20, cutterCount: 8, fieldSize: .small)
        require("After travel all cutters trace their outlines", tracing.cutters.allSatisfy { $0.cut > 0.3 && $0.power == 1 })
        require("Tracing does not rebuild geometry or completion revisions", initial.geometryRevision == tracing.geometryRevision
            && initial.revision == tracing.revision)
        let firstID = tracing.cutters[0].id
        let firstCut = tracing.cutters[0].cut
        let reduced = workers.frame(at: 0.20, cutterCount: 1, fieldSize: .small)
        require("Reducing workers preserves the ongoing worker and cycle", reduced.cutters.count == 1
            && reduced.cutters[0].id == firstID && reduced.cutters[0].cut == firstCut
            && reduced.cycle == initial.cycle && reduced.completed.isEmpty)
        let expanded = workers.frame(at: 0.20, cutterCount: 8, fieldSize: .small)
        require("Increasing workers preserves the ongoing cut without duplicate jobs", expanded.cutters.count == 8
            && expanded.cutters[0].id == firstID && expanded.cutters[0].cut == firstCut && structurallyValid(expanded))
        let firstCompleted = workers.frame(at: 0.42, cutterCount: 8, fieldSize: .small)
        require("A hat fills only when its 0.42 second job finishes", firstCompleted.completed.map(\.id) == [firstID])
        let reclaimedCompleted = workers.frame(at: 0.62, cutterCount: 8, fieldSize: .small)
        require("Re-expanded workers complete distinct hats", reclaimedCompleted.completed.count == 8
            && structurallyValid(reclaimedCompleted))
        let afterCompletedResize = workers.frame(at: 0.70, cutterCount: 2, fieldSize: .small)
        require("Live worker changes preserve all completed fills", afterCompletedResize.completed.map(\.id) == reclaimedCompleted.completed.map(\.id)
            && afterCompletedResize.cutters.count == 2 && afterCompletedResize.cycle == initial.cycle)
        var resizedFrame = afterCompletedResize
        var resizedTime = 0.70
        while resizedFrame.completed.count < 168 && resizedTime < 15 {
            resizedTime += 0.1
            resizedFrame = workers.frame(at: resizedTime, cutterCount: 8, fieldSize: .small)
        }
        require("Every retired worker's unfinished job remains available and eventually fills", resizedFrame.completed.count == 168
            && Set(initial.cutters.map(\.id)).isSubset(of: Set(resizedFrame.completed.map(\.id)))
            && structurallyValid(resizedFrame))

        let single = LaserConstruction()
        let singleStart = single.frame(at: 0, cutterCount: 1, fieldSize: .small)
        let singleNext = single.frame(at: 0.42, cutterCount: 1, fieldSize: .small)
        require("A single cutter begins in the central neighborhood", hypot(singleStart.cutters[0].tile.center.x,
            singleStart.cutters[0].tile.center.y) < 2)
        require("A single cutter advances to a nearby hat", hypot(singleNext.cutters[0].tile.center.x - singleStart.cutters[0].tile.center.x,
            singleNext.cutters[0].tile.center.y - singleStart.cutters[0].tile.center.y) < 3)

        var minimumSeedFractions: [Double] = []
        // Run every finite size to its last fill, checking that previous fills
        // are a prefix of every later snapshot, then inspect its four second
        // fade and make sure a new cycle gets fresh IDs without new geometry.
        for size in [FlowFieldSize.small, .medium, .expanded, .large] {
            let model = LaserConstruction()
            var time = 0.0
            var frame = model.frame(at: time, cutterCount: 8, fieldSize: size)
            let geometryRevision = frame.geometryRevision
            let initialCycle = frame.cycle
            let diagonal = hypot(frame.bounds.width, frame.bounds.height)
            var minimumDistance = Double.infinity
            for i in frame.cutters.indices {
                for j in frame.cutters.indices where j > i {
                    let a = frame.cutters[i].tile.center, b = frame.cutters[j].tile.center
                    minimumDistance = min(minimumDistance, hypot(a.x - b.x, a.y - b.y))
                }
            }
            minimumSeedFractions.append(minimumDistance / diagonal)
            require("\(size.title) distributes eight initial cutters across the field", minimumDistance > diagonal * 0.12)
            let nextBatch = model.frame(at: 0.42, cutterCount: 8, fieldSize: size)
            require("\(size.title) each worker grows its own nearby patch", zip(frame.cutters, nextBatch.cutters).allSatisfy {
                hypot($0.tile.center.x - $1.tile.center.x, $0.tile.center.y - $1.tile.center.y) < 3
            })
            frame = nextBatch; time = 0.42
            var previousIDs = frame.completed.map(\.id)
            var fillsPreserved = true
            var validSnapshots = true
            var maxRetained = frame.completed.count
            while frame.completed.count < size.rawValue && time < 120 {
                time += 0.1
                frame = model.frame(at: time, cutterCount: 8, fieldSize: size)
                fillsPreserved = fillsPreserved && Array(frame.completed.prefix(previousIDs.count).map(\.id)) == previousIDs
                validSnapshots = validSnapshots && structurallyValid(frame)
                maxRetained = max(maxRetained, frame.completed.count)
                previousIDs = frame.completed.map(\.id)
            }
            require("\(size.title) never discards an earlier completed hat before the fade", fillsPreserved
                && maxRetained == size.rawValue)
            require("\(size.title) all intermediate construction snapshots stay distinct and valid", validSnapshots)
            require("\(size.title) completes every hat before fading", frame.completed.count == size.rawValue
                && frame.cutters.isEmpty && structurallyValid(frame))
            require("\(size.title) fills do not regenerate the geometry", frame.geometryRevision == geometryRevision
                && frame.cycle == initialCycle && frame.fade > 0.99)
            let completedIDs = Set(frame.completed.map(\.id))
            let finish = ceil(Double(size.rawValue) / 8) * 0.42
            time = finish + 1
            frame = model.frame(at: time, cutterCount: 3, fieldSize: size)
            require("\(size.title) worker changes during fade preserve the completed field", frame.completed.count == size.rawValue
                && frame.cutters.isEmpty && frame.cycle == initialCycle && abs(frame.fade - 0.9375) < 1e-7)
            time = finish + 2.5
            frame = model.frame(at: time, cutterCount: 3, fieldSize: size)
            require("\(size.title) remains visible partway through the four second fade", frame.completed.count == size.rawValue
                && abs(frame.fade - 0.609375) < 1e-7)
            time = finish + 3.99
            frame = model.frame(at: time, cutterCount: 3, fieldSize: size)
            require("\(size.title) does not restart before four seconds", frame.cycle == initialCycle && frame.fade < 0.01)
            time = finish + 4.01
            frame = model.frame(at: time, cutterCount: 3, fieldSize: size)
            require("\(size.title) resets once with fresh jobs after the fade", frame.cycle == initialCycle + 1
                && frame.completed.isEmpty && frame.cutters.count == 3 && frame.fade == 1
                && frame.geometryRevision == geometryRevision
                && completedIDs.isDisjoint(with: Set(frame.cutters.map(\.id))))
        }

        let defensive = LaserConstruction()
        let zero = defensive.frame(at: 0, cutterCount: 0, fieldSize: .small)
        require("Worker count clamps to at least one", zero.cutters.count == 1)
        let tooMany = defensive.frame(at: 0, cutterCount: 99, fieldSize: .small)
        require("Worker count clamps to eight", tooMany.cutters.count == 8)
        let jump = defensive.frame(at: 1e9, cutterCount: 8, fieldSize: .small)
        require("A huge clock jump processes at most two seconds", jump.completed.count == 32 && jump.cycle == zero.cycle)
        let invalid = defensive.frame(at: .nan, cutterCount: 8, fieldSize: .small)
        let infinite = defensive.frame(at: .infinity, cutterCount: 8, fieldSize: .small)
        let negative = defensive.frame(at: -1, cutterCount: 8, fieldSize: .small)
        require("Invalid and reversed time do not replay or reset jobs", invalid.revision == jump.revision
            && infinite.revision == jump.revision && negative.revision == jump.revision && structurallyValid(negative))
        let changed = defensive.frame(at: 0, cutterCount: 4, fieldSize: .medium)
        require("Changing field size resets geometry and construction", changed.cycle == zero.cycle + 1
            && changed.completed.isEmpty && changed.cutters.count == 4 && changed.guides.count == 512
            && changed.geometryRevision > zero.geometryRevision && structurallyValid(changed))

        let separation = minimumSeedFractions.map { String(format: "%.3f", $0) }.joined(separator: "/")
        print("Laser construction: \(checks) checks passed; all 168/512/1024/2048 fills retained until fade; minimum seed separation/field diagonal \(separation).")
    }
}
