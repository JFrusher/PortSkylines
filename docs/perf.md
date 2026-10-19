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

## M3 default map (2026-10-19)

M3 grows the default map from 64×48 to 96×96, the 3×3 land tiles of 32
cells. Same machine, renderer and command as the M1 baseline, run with `96`.

| Map | Built tiles | MultiMesh parts (chunk × kind) | Draw calls | Avg frame | p95 frame |
|---|---:|---:|---:|---:|---:|
| 96×96 | 2,415 | 33 | 36 | 16.59 ms | 20.61 ms |

**Reading.** Draw calls stay chunk-bound (36), between the 64² and 256²
baselines. This run's frame times came out below the 64² baseline's, so this
box's timings drift by more than the gap between those two map sizes. Treat
the frame times as noise and keep the draw-call count as the result.

## M4 budget (2026-10-19)

`bench/sim_bench.gd` runs the soak test's port in headless timing mode for
half a game day and fails when the sim goes over budget. CI runs it on every
push. The render budget is checked by hand with `bench/bench.gd`.

| Entity | Measured (this box) | Budget |
|---|---:|---:|
| Whole tick, bench port | 0.18–0.20 ms | 1.0 ms |
| Per vehicle per tick | 21–23 µs | 100 µs |

**Machine:** the same cloud container as the M1 baseline. **Command:**
`godot --headless --script res://bench/sim_bench.gd`. The bench port holds
8.5 vehicles on average, 14 ships and 17 boxes, so the per-vehicle figure
still carries the tick's fixed cost; it is a regression guard, not a
measure of scale. The budgets leave about 5× headroom for slower CI
runners. At 21 µs per vehicle, 2,000 lorries would cost about 42 ms a tick,
far over the M5 target; packed vehicle state and threaded paths in M5 are
what close that gap.

## M4 render check (2026-10-19)

Same machine, renderer and command as the M1 baseline. The M4 view adds
road pieces, markings, quay edges, container models and yard machines.

| Map | Built tiles | Parts | Draw calls | Avg frame | p95 frame |
|---|---:|---:|---:|---:|---:|
| 96×96 | 2,415 | 90 | 80 | 33.18 ms | 42.26 ms |
| 256×256 | 18,791 | 640 | 559 | 129.78 ms | 184.59 ms |

**Reading.** The first cut of yard machines drew each one as its own node
of several meshes. The bench's random map has 636 one-tile yard blocks,
each with a machine, which took the 96² map to 1,325 draw calls (measured
commit by commit: 61 before the machines, 1,315 after). Drawing machines as
one MultiMesh per chunk and gear brought it back to 80. Draw calls stay
chunk-bound again. Frame time rose with the extra triangles, which on
llvmpipe is CPU rasterisation; the 60 fps exit criterion still needs a run
on a GTX 1660-class GPU.

## M5 baseline profile (2026-10-19)

`bench/profile_sim.gd` builds the endgame port (`bench/endgame_port.gd`: a
160² map, 6 berths of 3 cranes, a road grid with 25 gates, RTG yard bands
holding 20,000 imports) and times the sim's per-tick functions while
lorries flow in at one a tick. Same container as earlier entries.
**Command:** `godot --headless --script res://bench/profile_sim.gd -- 300`.

300 ticks: **78.6 ms a tick** with only 47 vehicles on the map at the end,
against a 1 ms budget. At this cost the endgame save's 2,000 lorries can't
even be generated, so the hot spots go first.

| Function | Share of the tick (inclusive) | Calls | Per call | Why |
|---|---:|---:|---:|---|
| `_route_via_gate` | 69% | 1,373 | 11.9 ms | A* to and from each of 25 gates for every lorry route |
| `_queue_at` | 66% | 34,325 | 0.45 ms | scans every vehicle's remaining path, once per gate per route |
| `_dispatch_import_lorry` | 56% | 300 | 43.9 ms | walks every stacked box, routing to each block |
| `_dispatch_export_lorry` | 43% | 300 | 34.0 ms | mostly `_yard_tile_for` |
| `_yard_tile_for` | 30% | 303 | 23.4 ms | routes to every yard block to find the nearest |

Vehicle movement (`_drive_lorry`, `_advance`) is under 1%: the cost is
routing and searching, not kinematics. Each M5 step below names the hot
spot it removes and is re-measured with the same command.
