# Performance log

Each entry records what was measured, where, and how. Compare entries only
when they were made on the same machine and renderer.

## M1 baseline (2026-10-18)

**Machine:** cloud container, 4-core Intel Xeon at 2.80 GHz, no GPU. Software
rendering through Mesa llvmpipe (`--rendering-method gl_compatibility` under
`xvfb-run`). The frame times show CPU-side cost on this box only; they say
nothing about the GTX 1660-class target.

**Command:** `xvfb-run -a godot --rendering-method gl_compatibility --resolution 1280x720 --script res://bench/bench.gd -- <size>`
(seeded map, about 30% of land tiles built, 600 frames after a 60-frame warm-up).

| Map | Built tiles | MultiMesh parts (chunk × kind) | Draw calls | Avg frame | p95 frame |
|---|---:|---:|---:|---:|---:|
| 64×64 | 1,012 | 12 | 15 | 24.57 ms | 29.76 ms |
| 256×256 | 18,791 | 192 | 195 | 104.84 ms | 138.37 ms |

**Reading.** Draw calls equal the MultiMesh parts plus 3 (water, land, hover
box). They grow with chunks (16×) rather than tiles (19×), which is the M1
exit criterion. The frame time growth on llvmpipe is CPU rasterisation of
more triangles, not draw calls. It needs re-measuring on real GPUs before any
conclusion about rendering cost.
