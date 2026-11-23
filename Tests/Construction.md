Run `python3 Tests/run-construction-checks.py` on macOS. The runner compiles the
same Foundation geometry and scheduler sources used by Apple and Svala; it does
not load SwiftUI, a GPU, or an SDK application runtime.

The 60 checks cover distinct, widely separated starting assignments for eight
cutters, travel before the outline, completion fills, and each worker growing a
nearby patch. The closest initial pair must be more than 12 percent of the field
diagonal apart for every preset; a single cutter begins in the central
neighborhood.

A representative run measures minimum initial separation at 20.5, 19.5, 24.8,
and 26.3 percent of the field diagonal for the 168, 512, 1,024, and 2,048 hat
presets.

Live worker changes must preserve existing cuts and completed fills, return
unfinished jobs to the queue, and eventually complete each retired job exactly
once. Every intermediate frame in the 168, 512, 1,024, and 2,048 hat presets must
retain all previous completed IDs in order, without duplicate jobs or world geometry.
All fills remain visible until the four second end-of-field fade, followed by a
fresh cycle. Invalid timestamps, worker counts, and large clock jumps are also
exercised.
