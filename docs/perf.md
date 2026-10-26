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

## M5 budget on roads and areas (2026-10-19)

The tile model is gone, so `bench/sim_bench.gd` now runs the soak test's
port on roads and areas: AreaPort's chain built by commands, with a lorry
every quarter minute. Its lorries drive the 2 km from the highway to the
coast at the data's 125 m a game minute, so about 280 vehicles are on the
roads at once, where the tile bench port held 8.5. The whole-tick budget
rises with that, and the per-vehicle one tightens.

| Entity | Measured (this box) | Budget |
|---|---:|---:|
| Whole tick, bench port | 2.5–2.8 ms | 12 ms |
| Per vehicle per tick | 8.8–9.8 µs | 50 µs |

**Machine:** the same cloud container (4 vCPU Xeon at 2.8 GHz). **Command:**
`godot --headless --script res://bench/sim_bench.gd`. At 10 µs a vehicle,
the endgame's 2,000 lorries would cost about 20 ms a tick, still over the
M6 target. The render bench, the endgame port and the sim profiler built
tile ports, so they went with the tile model; M6 steps 1 and 2 rebuild them
on roads and areas, and the M4 and M6 render figures below were measured on tiles.

## Vehicles at their data speed, then realistic speeds (2026-10-25)

Until 25 Oct every vehicle moved one cell a tick at most, 80 m a game
minute, so the bench port's lorries never drove at the 125 m above.
`LaneTraffic.advance` now enters cells up to a vehicle's speed, and the
data speeds became 25 km/h for lorries and 30 km/h for tractors (417 and
500 m a game minute). Faster trips leave fewer vehicles on the roads at
once, each crossing more cells a tick, so the cost per vehicle-tick rises
while the whole tick holds.

| Bench run | ms a tick | Vehicles on average | µs per vehicle-tick |
|---|---:|---:|---:|
| One cell a tick (before) | 0.73 | 100 | 7.3 |
| Data speed, 125 and 150 m | 0.66 | 80 | 8.3 |
| 417 and 500 m | 0.67 | 59 | 11.5 |

Budgets are unchanged (12 ms, 50 µs). For the endgame, cost now scales with
cells crossed a tick, not vehicles alone: M6's packed data and path
threading should be measured in cells a tick too.

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

Scale and rail was M5 when these steps were done; it is now M6. Step numbers here are that phase's.

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

### Routing hot spots removed (M5 step 7, distance fields)

Same command. The sim's state hash after 30,000 ticks of the soak ports and
300 ticks of the endgame port is identical before and after: every choice
is the same, only found faster.

| Change | Hot spot removed | ms a tick |
|---|---|---:|
| Baseline | | 78.6 |
| Gate queues counted in one pass per route, not one per gate; gates tried from the shortest road distance (cached BFS fields from each gate, rebuilt only when roads change) and searched only while one could win | `_queue_at`, `_route_via_gate` | 37.6 |
| Nearest block with room found by road distance, scanning blocks for room only from the nearest; gate reachability for dispatch read from the fields; each path's gate steps found once | `_yard_tile_for`, `_dispatch_import_lorry`, `_gate_queues` | 3.0 |

The soak port's sim bench dropped from 0.20 to 0.12 ms a tick.

### Vehicles drawn as MultiMeshes (M5 step 4)

`bench/endgame_bench.gd -- 1` on `bench/endgame.bin` (about 2,000
vehicles), software GL under xvfb at 1920x1080, so only the draw calls and
the ratio of render CPU time carry over to a real GPU.

| | Draw calls | Render CPU ms | Frame ms |
|---|---:|---:|---:|
| A node per vehicle (cab, chassis, box) | 4,981 | 276 | 668 |
| Cabs, chassis, 20 ft and 40 ft boxes as one MultiMesh each | 329 | 184 | 541 |

Vehicle draw calls are now four, whatever the vehicle count. The frame is
still sim-bound at this load (about 9 ticks a frame at 27 ms each), which
the later M5 steps take on.

### What render time is spent on (M5 steps 5 and 6)

Endgame save, sim paused, render CPU with one group hidden at a time
(software GL, so ratios only):

| Hidden | Instances | Render CPU saved |
|---|---:|---:|
| Ground tiles | 23,882 | 69 ms of 168 |
| Stacked boxes | 19,767 | 48 ms |
| Yard machines | 2,016 | 44 ms |
| Ships and cranes (162 draw calls) | | 5 ms |

Cost follows instances drawn: swapping every container for a 12-triangle
box saved nothing, and a quarter of the resolution saved nothing. So step 5
(ships and cranes in a MultiMesh) is not justified by the counts and is
skipped. Step 6 draws chunks with less detail as the camera pulls back, the
way Cities: Skylines does: past 60 units from a chunk's centre each yard
tile's stack is one slab in its top box's livery, and past 80 the yard
machines are not drawn. Chunks out of view are culled whole, as before.

`bench/endgame_bench.gd -- 0 90` (paused, the game's farthest zoom):

| | Render CPU ms | Draw calls | Primitives |
|---|---:|---:|---:|
| Every box and machine at every distance | 264 | 313 | 578,321 |
| Fidelity by distance | 164 | 282 | 430,013 |

Ground tiles are now the largest cost and are drawn as before.

## M6 baseline on roads and areas (2026-10-26)

M6 steps 1 and 2, redone on roads and areas. `bench/make_endgame.gd` builds
`bench/endgame_port.gd` by commands (6 Panamax aprons of 3 STS cranes, 18
cranes, 72 tractors, 7 rows of RTG blocks with 20,000 imports, 12 two-way
gates) and runs it for six game hours with a lorry sent every tick.
`bench/profile_sim.gd` times each step of a tick and checks the state hash
against a plain run. Same container as earlier entries.
**Commands:** `godot --headless --script res://bench/make_endgame.gd`, then
`godot --headless --script res://bench/profile_sim.gd -- 200`.

**Counts reached.** 694 lorries, 20,019 boxes and 6 ships after six hours,
short of the 2,000 lorries M6 names. Lorries arrive faster than the yard
hands boxes over (398 delivered in six hours), so the count still grows; at
one lorry a tick through one site entry, 2,000 at once needs either that
backlog or a second entry (M8's whole port).

Building it found a dispatch bug: lorries took the first due box in block
order, so every lorry went to 5 of 80 blocks and the port jammed (35 boxes
delivered in six hours). They now take the box due longest.

**288 ms a tick** with 694 vehicles, against the 1 ms budget:

| Step of the tick | Share | Per tick |
|---|---:|---:|
| Ships (`PortSim._work`) | 95.8% | 276 ms |
| Vehicles (`AreaFlow._drive`) | 1.7% | 4.9 ms |
| Routes (`LaneGraph.route`, inside the others) | 1.7% | 4.8 ms (4 a tick, 1.1 ms each) |
| Machines | 1.2% | 3.4 ms |
| `dispatch_import_lorry` | 1.1% | 3.1 ms |
| Vehicle moves (`LaneTraffic.advance`, inside vehicles) | 0.8% | 3.7 µs each |

Inside ship work, timed one call at a time on the saved port, where all six
ships wait to load about 50 exports each and no export is in the yard:

| Hot spot | Per call | Why |
|---|---:|---|
| `AreaFlow._export_box` | 18.4 ms | walks every box of every block in the terminal (20,000 imports) for an export, once per crane each tick, and finds none |
| `AreaFlow._exports_coming` | 4.3 ms | calls `export_demand` and scans every vehicle |
| `AreaFlow.export_demand` | 2.7 ms | counts exports across all 20,000 boxes |
| `LaneGraph.route` | 1.1 ms | A* over the whole lane graph |
| `dispatch_import_lorry` | 3.1 ms a tick | walks every box for the one due longest |

The top five are box scans, not vehicles: kinematics is under 1%. The next
M6 steps name the scan they remove; keeping export and due-box indexes as
boxes come and go would take the first three and the fifth off the tick.

**Render.** `bench/endgame_bench.gd -- 1 90` (software GL under xvfb at
1920x1080, the farthest zoom, so ratios only): 705 vehicles, frame 2,748 ms
(p95 2,956), sim 693 ms of it (routes 10 ms), render CPU 1,977 ms, 658 draw
calls, 161,622 primitives. The tile model's endgame drew in 164 to 264 ms
of render CPU on this box with more primitives (430,013 to 578,321), so the
roads-and-areas view costs far more per primitive. Why is not known yet:
profile it per group, as for steps 5 and 6 on tiles, before M6's render
steps change anything.

### Box scans off the tick (2026-10-26)

Same save (`bench/endgame.bin` from `make_endgame.gd`, 694 lorries) and
command, `profile_sim.gd -- 200`, run once per commit one after another.
The container ran slower than for the baseline above (509 ms against 288 ms
for the same code), so compare within this table only. `bench/hash_ticks.gd`
gives the same state hash after 300 ticks before and after (1889779304).

| Change | Hot spot removed | ms a tick |
|---|---|---:|
| Baseline | | 508.8 |
| A block's exports listed by kind, soonest due first, sorted again only when its stacks change | `AreaFlow._export_box` (18.4 ms a call) | 86.0 |
| A count of exports kept as boxes come and go | `AreaFlow.export_demand` (2.7 ms) | 46.6 |
| Lorries take each block's first unclaimed import from the same sorted list | `dispatch_import_lorry` (4.6 to 2.7 ms a tick) | 43.8 |

| Each area's idle reason kept until roads or areas change, not rebuilt from its cells per call | `Areas.idle_reason` (10.5 µs a call, 80 a crane lookup) | 29.8 |

Ship work was still 29 ms of the 43.8. Timed one call at a time on the
saved port (six ships loading, no export in the yard), `AreaFlow.work` cost
4.3 ms a ship: `_export_box` 662 µs with nothing to find, because it asked
each of 80 blocks `idle_reason`, which built the block's line of cells
every call; `_export_room` 972 µs and `_has_gate` 141 µs did the same over
every area. With the reason kept, `AreaFlow.work` is 2.1 ms a ship.

`AreaFlow._block_of` still lists every block's boxes to find one (298 µs a
call; 25.5 µs asking each block's index instead), but a tick calls it about
0.15 times: the change measured 30.7 ms a tick against 29.8, within noise,
so it was not kept. The box scans left run once a day (storage) or for the
view, not every tick.

### The endgame save at 2,000 lorries (2026-10-26)

Why the save stopped near 700 lorries, probed on it (`make_endgame.gd`'s
rules put back after loading): of 630 lorries driving in, 519 were bound
for one gate, the one nearest the site entry, since `_gate_of` ranked gates
by route length alone. Its queue reached back to the entry, which was busy
510 ticks in 600, and a lorry comes in only through a free entry cell.

Lorries now take the gate they get through soonest: minutes of driving plus
the lorries already bound there times the booth minutes over its lanes
(`test_roads` checks a 20-lorry queue sends the next lorry on to the other
gate). `make_endgame.gd` then reaches its 2,000 lorries at 2.8 game hours,
in under 3 minutes of building where it took 29; the 12 gates hold 42 to 58
lorries each. Deliveries stay low (144 by then), since a lorry every tick
outruns the yard's RTGs, which is the point of the bench.

Note on the benches: rules are data and are not saved, so a loaded
`endgame.bin` plays on the base rules (a lorry a minute, an RTG per 10
bays), not the bench's. `profile_sim.gd`'s figures above, and the 288 ms
baseline, were taken that way.

### At 2,000 lorries (2026-10-26)

`profile_sim.gd -- 200` on the 2,000-lorry save with the bench's rules, so
a lorry is sent every tick (2,150 vehicles at the end). Same state hash after
300 ticks before and after each change.

| Change | Hot spot removed | ms a tick |
|---|---|---:|
| Baseline at 2,000 lorries | | 86.8 |
| Route lengths for gate choice kept until the lane graph changes | `_gate_of` routing to all 12 gates per lorry (20 of 20 route calls a tick, 1.66 ms each) | 75.3 |
| Each terminal's working gates kept until roads or areas change | `_has_gate` scanning every area (125 µs) for each of 80 blocks per dispatch | 61.2 |
| Routes kept until the lane graph changes (replaces the length memo above) | `LaneGraph.route`: one A* over 23,480 points, 1.2 ms, plus 0.3 ms building cells | 56.6 |

Probed before the last change: every route runs one A* search (start and
goal cells each hold one lane point), so the search itself is the cost.
Over six endgame minutes 43% of routes asked a (from, to) asked before,
rising to 69% in the last 200 ticks, with none empty: vehicles drive
between the same slots, buffers and gates. A 200-tick profile starts with
the memo empty, so it undersells the gain.

What is left, from the same profile: vehicles 22.6 ms, machines 18.1 ms and
ships 16.6 ms, inclusive of 11.6 route searches a tick at 1.65 ms each
(31% of the tick) and of loops over every vehicle (`_machine_done`,
`_promote`, `_vehicle`, `_tractors_out`, `_fetchers`, `_export_room`). Those
are M6 steps 3 (vehicles as packed arrays, found by index) and 7 to 9 (paths).

### What the roads-and-areas render spends its time on (2026-10-26)

`bench/endgame_bench.gd` on the 2,000-lorry save, software GL under xvfb at
1920x1080, farthest zoom (90), 20 frames after 5 of warm-up: ratios only.

The sim running was not the cause: render CPU was 3,037 ms a frame paused
and 3,124 ms at 1×. One group hidden at a time, paused:

| Hidden | Render CPU ms | Primitives reported |
|---|---:|---:|
| Nothing | 3,037 | 197,630 |
| Ground | 3,030 | 197,606 |
| Roads | 2,920 | 195,114 |
| Areas | 2,910 | 107,006 |
| **Stacked boxes** | **200** | 196,058 |
| Yard machines | 2,966 | 150,974 |
| Vehicles | 2,866 | 146,354 |
| Ships | 3,122 | 194,408 |
| STS cranes | 2,906 | 195,902 |

The stacks were 94% of it, yet hiding them took only 1,572 primitives off
the count: the counter reports a MultiMesh's mesh once, not once per
instance. The container models have 552 (20 ft) and 1,020 (40 ft)
triangles, and all 20,000 boxes drew them in one MultiMesh, about 15
million triangles a frame, with no culling or detail by distance since one
box covered the whole port. Drawn as plain 12-triangle boxes they cost
371 ms. So this is why the tile model, with fewer real triangles, drew
faster than its larger primitive count suggested.

Each yard block now draws its boxes in its own MultiMeshes, the container
model up to 30 units from the camera and a plain box in its livery beyond
(visibility ranges, M6 step 6), and redraws only when its stacks change,
where all 20,000 were rebuilt every tick:

| | Render CPU ms | Frame ms | Draw calls |
|---|---:|---:|---:|
| Before, paused | 3,037 | 3,208 | 700 |
| After, paused | 226 | 263 | 860 |
| Before, 1× | 3,124 | 3,521 | 713 |
| After, 1× | 226 | 391 | 873 |
| After, paused, zoomed in to 20 | 469 | 509 | 386 |

Checked by eye at 10, 28 and 60 units: near rows show the container model,
far rows plain boxes in the same liveries, with no visible jump.
