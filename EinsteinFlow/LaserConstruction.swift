import Foundation

enum FlowFieldSize: Int, CaseIterable, Identifiable {
    case small = 168, medium = 512, expanded = 1024, large = 2048
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .small: return "168 hats"
        case .medium: return "512 hats"
        case .expanded: return "1,024 hats"
        case .large: return "2,048 hats"
        }
    }
}

struct CompletedHat {
    let id: Int
    let tile: TraceTile
}
struct ActiveCut {
    let id: Int
    let tile: TraceTile
    let cut: Double
    let position: HatPoint
    let direction: HatPoint
    let power: Double
}
struct ConstructionFrame {
    let guides: [TraceTile]
    let completed: [CompletedHat]
    let cutters: [ActiveCut]
    let bounds: TraceBounds
    let framing: TraceBounds
    let fade: Double
    let geometryRevision: Int
    let revision: Int
    let cycle: Int
}

/// A serial, UI-independent construction scheduler. Worker count changes keep
/// completed hats and return retired workers' unfinished jobs to the queue.
/// Every completed hat remains visible until the whole field finishes.
final class LaserConstruction {
    private struct Job { let id: Int; let tile: TraceTile }
    private struct Worker { let job: Job; let began: Double; let origin: HatPoint }
    private let secondsPerHat = 0.42
    private let travelFraction = 0.14
    private var selection: FlowFieldSize?
    private var desiredWorkers = 1
    private var workers = Array<Worker?>(repeating: nil, count: 8)
    private var positions = Array<HatPoint?>(repeating: nil, count: 8)
    private var queue: [Job] = []
    private var nextPending = 0
    private var finished: [CompletedHat] = []
    private var finiteTiles: [TraceTile] = []
    private var lastInput = 0.0
    private var simulated = 0.0
    private var finishTime: Double?
    private var nextID = 0
    private var geometryRevision = 0
    private var revision = 0
    private var cycle = -1
    private var guides: [TraceTile] = []
    private var bounds = TraceBounds(minX: -1, minY: -1, maxX: 1, maxY: 1)
    private var framing = TraceBounds(minX: -1, minY: -1, maxX: 1, maxY: 1)
    private var framingDirty = true

    func frame(at time: Double, cutterCount: Int, fieldSize: FlowFieldSize) -> ConstructionFrame {
        let input = time.isFinite ? max(0, time) : lastInput
        let count = min(8, max(1, cutterCount))
        if selection != fieldSize {
            let first = selection == nil
            desiredWorkers = count
            resetField(fieldSize, at: simulated)
            lastInput = first ? 0 : input
        }
        // A resumed/hidden view or accidental wall-clock jump must not replay
        // hours of jobs in one frame. Normal 30/60Hz deltas pass unchanged.
        let delta = min(2.0, max(0, input - lastInput))
        lastInput = input
        advance(to: simulated + delta)
        resizeWorkers(to: count)
        if framingDirty { updateFraming() }
        let cuts = workers.compactMap { $0 }.map { cut($0, at: simulated) }
        let fade = finishTime.map { 1 - pow(min(1, max(0, (simulated - $0) / 4)), 2) } ?? 1
        return ConstructionFrame(guides: guides, completed: finished, cutters: cuts,
            bounds: bounds, framing: framing, fade: fade,
            geometryRevision: geometryRevision, revision: revision, cycle: cycle)
    }

    private func resetField(_ size: FlowFieldSize, at time: Double) {
        selection = size
        workers = Array(repeating: nil, count: 8)
        positions = Array(repeating: nil, count: 8)
        queue.removeAll(); finished.removeAll()
        nextPending = 0; finishTime = nil
        cycle += 1; revision += 1
        finiteTiles = TraceScene.make(tileCount: size.rawValue).tiles
        queue = finiteTiles.map(makeJob)
        updateGeometry()
        assignIdle(at: time)
        framingDirty = true
    }

    private func makeJob(_ tile: TraceTile) -> Job {
        let job = Job(id: nextID, tile: tile)
        nextID += 1
        return job
    }

    private func resizeWorkers(to count: Int) {
        guard count != desiredWorkers else { return }
        if count < desiredWorkers {
            var returned: [Job] = []
            for slot in count..<8 {
                if let worker = workers[slot] {
                    positions[slot] = cut(worker, at: simulated).position
                    returned.append(worker.job)
                    workers[slot] = nil
                }
            }
            queue = returned + Array(queue.dropFirst(nextPending))
            nextPending = 0
        }
        desiredWorkers = count
        assignIdle(at: simulated)
        framingDirty = true
    }

    private func assignIdle(at time: Double) {
        for slot in 0..<desiredWorkers where workers[slot] == nil {
            guard nextPending < queue.count else { break }
            let candidates = nextPending..<queue.count
            let chosen: Int
            if let origin = positions[slot] {
                // Continue locally, so each beam grows its own patch.
                chosen = candidates.min {
                    squaredDistance(queue[$0].tile.center, origin) < squaredDistance(queue[$1].tile.center, origin)
                }!
            } else {
                let occupied = workers.compactMap { $0?.job.tile.center }
                // New cutters start far from the cutters already working.
                chosen = occupied.isEmpty ? nextPending : candidates.max { a, b in
                    let distanceA = occupied.map { squaredDistance(queue[a].tile.center, $0) }.min()!
                    let distanceB = occupied.map { squaredDistance(queue[b].tile.center, $0) }.min()!
                    return distanceA < distanceB
                }!
            }
            queue.swapAt(nextPending, chosen)
            let job = queue[nextPending]
            nextPending += 1
            let origin = positions[slot] ?? job.tile.vertices[0]
            workers[slot] = Worker(job: job, began: time, origin: origin)
        }
    }

    private func squaredDistance(_ a: HatPoint, _ b: HatPoint) -> Double {
        let x = a.x - b.x, y = a.y - b.y
        return x * x + y * y
    }

    private func advance(to target: Double) {
        while true {
            if let finishTime, target >= finishTime + 4 {
                let restart = finishTime + 4
                finished.removeAll()
                positions = Array(repeating: nil, count: 8)
                queue = finiteTiles.map(makeJob); nextPending = 0
                self.finishTime = nil
                cycle += 1; revision += 1; framingDirty = true
                assignIdle(at: restart)
                continue
            }
            guard let end = workers.compactMap({ $0.map { $0.began + secondsPerHat } }).min(),
                  end <= target + 1e-9 else { break }
            for slot in workers.indices {
                guard let worker = workers[slot], worker.began + secondsPerHat <= end + 1e-9 else { continue }
                finished.append(CompletedHat(id: worker.job.id, tile: worker.job.tile))
                positions[slot] = worker.job.tile.vertices[0]
                workers[slot] = nil
                revision += 1
            }
            framingDirty = true
            assignIdle(at: end)
            if nextPending == queue.count, workers.allSatisfy({ $0 == nil }) {
                finishTime = end
            }
        }
        simulated = target
    }

    private func cut(_ worker: Worker, at time: Double) -> ActiveCut {
        let fraction = min(1, max(0, (time - worker.began) / secondsPerHat))
        if fraction < travelFraction {
            let travel = fraction / travelFraction
            let destination = worker.job.tile.vertices[0]
            let vector = destination - worker.origin
            let length = hypot(vector.x, vector.y)
            let direction = length > 1e-10 ? HatPoint(x: vector.x / length, y: vector.y / length)
                : worker.job.tile.point(at: 0).direction
            return ActiveCut(id: worker.job.id, tile: worker.job.tile, cut: 0,
                position: HatPoint(x: worker.origin.x + vector.x * travel, y: worker.origin.y + vector.y * travel),
                direction: direction, power: 0.35)
        }
        let progress = (fraction - travelFraction) / (1 - travelFraction)
        let point = worker.job.tile.point(at: progress)
        return ActiveCut(id: worker.job.id, tile: worker.job.tile, cut: progress,
            position: point.position, direction: point.direction, power: 1)
    }

    private func updateGeometry() {
        guides = finiteTiles
        if let first = guides.first {
            bounds = guides.dropFirst().reduce(first.bounds) { union($0, $1.bounds) }
        }
        geometryRevision += 1
    }

    private func updateFraming() {
        var result: TraceBounds?
        for hat in finished { result = result.map { union($0, hat.tile.bounds) } ?? hat.tile.bounds }
        for worker in workers.compactMap({ $0 }) {
            result = result.map { union($0, worker.job.tile.bounds) } ?? worker.job.tile.bounds
        }
        framing = result ?? bounds
        framingDirty = false
    }

    private func union(_ a: TraceBounds, _ b: TraceBounds) -> TraceBounds {
        TraceBounds(minX: min(a.minX, b.minX), minY: min(a.minY, b.minY),
            maxX: max(a.maxX, b.maxX), maxY: max(a.maxY, b.maxY))
    }
}
