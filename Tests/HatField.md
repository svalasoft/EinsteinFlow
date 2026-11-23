# Expandable genuine hat geometry

```sh
python3 Tests/run-field-checks.py
```

`HatTiling.Field` retains a shared hierarchy of the original H/T/P/F
substitution. Every expansion embeds the previous H root unchanged as the
third H child of its new parent. That child rotates by 120 degrees, so repeated
expansion surrounds the existing patch. Using the first child repeatedly would
leave an unfilled wedge even though the abstract supertile outline surrounds
the origin; the coverage regression protects against that mistake.

`tiles(in: TraceBounds)` prunes descendants by cached geometric bounds and
returns only the requested finite window. It sums polygon/rectangle clipped
areas before accepting the query; if the window is not completely covered, it
grows another parent and retries. The nested patch already prevents overlap.
The method does not tile a texture or repeat a rectangular seed.

Window queries do not accumulate previously visited tile arrays. A 60×60 world
window materializes about 1130 hats. Queries reaching ±100000 world units use
12 hierarchy levels containing 57 shared nodes, rather than flattening the
billions of hats represented by that hierarchy. Callers retain one Field and
evict offscreen paths or IDs to keep endless rendering bounded.

`TraceScene.make(tileCount:)` supports 168, 512, and 2048 hat presets (bounded at
8192 per visible scene). `make(tiles:tileCount:startNear:previousEnd:)` orders
queried or filtered tiles, including disconnected islands left after excluding
previously rendered hats. Its first outline vertex is selected near
`previousEnd`; a renderer carrying a beam across windows owns that connecting
travel segment.

The 37 checks verify sampled complete non-overlapping coverage, distinct
placements, genuine areas and chiralities, stable vertices/categories after
expansion, bounded hierarchy size, finite presets, and disconnected filtered
frontiers. These checks use only Foundation geometry.
