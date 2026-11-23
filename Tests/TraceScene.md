# Laser construction geometry

```sh
python3 Tests/run-trace-checks.py
```

This compiles the actual Foundation-only `HatTiling.swift` and `TraceScene.swift`.
The finite scene selects the requested number of genuine hats by growing one
connected central cluster from an expandable substitution field. It orders the
hats for nearby construction, choosing each outline's starting vertex near the
preceding closed outline. Transitions between nonadjacent hats use continuous
travel interpolation rather than teleporting the beam.

Each `TraceTile` provides thirteen vertices, its center/bounds/perimeter, an arc-length
parameterized laser point with a unit tangent, and a partial outline ending at
that exact point. `TraceScene.travel(to:at:)` bridges to the next outline during
the fast travel part of an animation step. The renderer can fill a hat only
after its complete closed outline has been drawn.

The checks cover genuine hat areas, distinct placements, a connected cluster,
deterministic order, bounds, reflected tiles, endpoint continuity, constant-speed
edge traversal, partial-outline/laser agreement, normalized tangents, clamping,
and continuous travel into the next hat. No rendering framework or GPU is used.
