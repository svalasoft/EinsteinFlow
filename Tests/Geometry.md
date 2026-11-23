# Hat geometry and field asset

Run on macOS with Xcode selected:

```sh
python3 Tests/run-geometry-checks.py
./Scripts/generate-hat-field.sh
```

The first command compiles and exercises the actual pure-Swift geometry, not a
duplicate implementation. It checks 39 invariants: the five substitution counts,
thirteen vertices, finite coordinates, congruent areas and edge lengths,
reflections, distinct placements, all five metatile coloring categories, and
57,600 crop samples with neither uncovered nor multiply covered interiors.
It also verifies that the shipped image is an opaque 3072 × 3072 RGB PNG and its
asset-catalog entry includes an explicit 1x scale for Svala.

`HatTiling.swift` ports the H/T/P/F metatile construction from Craig S. Kaplan's
BSD 3-Clause licensed [hatviz](https://github.com/isohedral/hatviz). The mathematics is
from Smith, Myers, Kaplan and Goodman-Strauss, [An aperiodic monotile](https://cs.uwaterloo.ca/~csk/hat/).
The preserved license is bundled as `ThirdParty/hatviz-LICENSE.txt`.

The field is one central square from a four-substitution patch containing 7921
hats. It is not a repeating texture cell. The generator paints the actual
polygon vertices with an antialiased navy outline and five category colors.
This baked field remains a reference asset. The live laser construction now
uses the actual vector hats from `TraceScene.swift`, prepared once at startup.
Run `python3 Tests/run-trace-checks.py` for the construction-route checks.
