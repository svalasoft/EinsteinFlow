# Shader verification

Run on a Mac with the rebuilt Svala native shared SDK:

```sh
python3 Tests/run-shader-checks.py \
  --image EinsteinFlow/Assets.xcassets/HatField.imageset/HatField.png \
  --output /tmp/einstein-shader-checks
```

The runner checks that the Metal and SkSL calculations match after removing
their API-specific entry-point signatures, uniform declarations and layer-sample
spellings. It then compiles the actual bundled SkSL through the actual Skia
runtime and executes it in an accelerated offscreen OpenGL context. It opens no
app window and never uses the unavailable CPU runtime-shader interpreter.

There are 214 GPU/ABI cases: the child and twelve uniform storage contracts; all
three styles at landscape and portrait dimensions; opaque output; visible flame
and particle evolution; deterministic fixed uniforms; white-hot core position;
unchanged distant layer content; moving the torch away from its old position;
finite default direction; and frame-edge safety. Zero power must preserve the
entire source exactly, independent of time or style. The fixture additionally
tests every cutter count from one through eight, each active head's core, unused
head suppression, eight unpowered heads, zero selected heads, and eight fully
overlapping heads. Source-parity checking is separate from those cases.

Omitting `--image` uses a synthetic dark layer, one filled rectangle and a short
cutting stroke to isolate shader execution. Those shapes are never app artwork.
The optional actual HatField PNG provides a detailed source-preservation fixture;
the app itself renders the individual hats with shared SwiftUI `Path` views.

The SwiftUI layer owns all geometry, path progress, fill completion, zoom and rotation.
The shader never wraps, repeats or transforms the input. Its twelve arguments
are `float2(size)`, `float4(time, style, count, reserved)`, eight
`float4(tipX, tipY, directionX, directionY)` heads, and two four-power vectors.
They use standard SwiftUI `.float2` and `.float4` values on both platforms;
shader-array support is not required. All heads share one layer capture/pass.
The shader preserves completed content outside the active heads' 110-point
neighbourhoods exactly. Those fragments need one source sample; the local
cutting region uses at most three, with a bounded five-chip loop for each
nearby active head. The two neighbour samples stay
within 1.4 horizontal and 1.4 vertical points, so a three-point sample-offset
budget is sufficient. Every child sample stays in the entry point, as required
by the current Svala SkSL dialect.

Apple also compiles `Einstein.metal` into its normal `default.metallib`. A passing
offscreen SkSL run establishes GPU execution and output checks, not browser
performance, SwiftUI layer capture or exact Metal/SkSL colour-space equivalence.
Those platform app paths need their own build/runtime checks.
