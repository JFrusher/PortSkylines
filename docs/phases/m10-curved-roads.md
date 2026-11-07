# M10 — Roads like Cities: Skylines

Roads today are straight segments on the 4 m grid at 0°, 45° or 90°. In the
sim, a road is the set of grid cells its lanes cover, one vehicle to a cell.
This phase makes roads, rail and ship lanes curves at any angle, drawn and
snapped the way Cities: Skylines does it. Areas are laid along those curves,
and vehicles drive them continuously.

Placed after M9 and before events (now M11), as the developer chose on
1 Nov 2026.

## The developer's answers (1 Nov 2026)

| Question | Answer |
|---|---|
| How far toward CS | **Full CS.** Roads are curves at any angle in the sim, not only on screen. Lanes are curves, vehicles follow them, and cells stay only for areas and blocking. |
| Drawing tools | **Straight, curved (three clicks), freeform, and upgrade in place.** |
| Snapping | **Angle snap with guides, length snap, guide lines, and a grid-snap toggle** for tidy yards. |
| Areas | **CS-style.** An area is laid in cells along the road's side and bends with it, as CS zoning does. |
| Junctions | **Minimum angle, auto corner shapes from the roads' widths, node merging, and lane-arrow editing.** |
| Elevation | **Later.** Ground level only in this phase. Bridges, flyovers and tunnels follow. |
| Rail and water | **Rail curves too** (with a larger minimum radius). **Ship lanes curve too.** **Berths stay straight**, but can be placed at the angle that adds the least land, or turned to any reasonable angle with a button. |
| Old saves | **Migrate them.** Each grid segment becomes a straight curve on the same line, and areas are rebuilt along it. |
| Traffic | **CS-like.** Vehicles keep a gap behind the one ahead along their lane, slow on tight curves and at junctions, and change lane where marked. They no longer take one cell each. |
| Performance | **No worse than today** on the mega port bench (about 19.5 ms a tick). |
| Speed limits | **Per road type, in the data:** two-lane terminal road 30 km/h, four-lane 40, one-way 40, tractor lane 25, highway 80. A vehicle drives at the lower of the road's limit and its own top speed. Routing uses travel time. |
| Lane changes | **Anywhere but junctions** and their approaches, as today. |
| Areas on bends | **A minimum radius per area type, in the data** (e.g. 30 m for yard blocks). Straight areas are always fine. |
| Following distance | **A standstill gap (2 m) plus about one second of travel** at the current speed, in the data. |
| Vehicle lengths | **Real lengths, in the data:** lorries 16.5 m, tractors with a chassis 15 m. Queues grow about four times longer than today's one-cell vehicles, so road, buffer and gate capacity matter more; a balance pass follows. |
| Highway | **A highway road type** (2+2, 80 km/h) for the road to the site's edge. |
| Grid snap default | **Off**, CS-style. The grid is a toggle. |
| Code | **GDScript first;** only hot spots that are measured move to native code. |
| Extras | **Length, cost and angle tooltip** while drawing; **parallel snapping**; **roundabouts**; **Move It-style editing** of built roads' nodes and control points. |

## Steps, in order

Each step is one commit with its test, as in every phase. The order keeps the
game playable throughout: geometry first, then the sim on top of it, then the
tools.

### Geometry
1. **Curve segments.** A segment is a quadratic Bézier: two end nodes and one control point (a straight road has its control point at the middle). Its length, a point and direction at a distance along it, and the nearest point to a position, all from a sampled length table. Test: a straight curve matches today's line; curve lengths are within 0.5% of a fine numeric sum.
2. **Lanes as offset curves.** Each lane is the segment's curve offset sideways by the lane's position, sampled to a polyline. Test: the lanes are parallel, at the type's lane width, all along.
3. **Junction shapes.** A node's shape comes from the widths and angles of its roads: each road is trimmed back far enough that neighbours don't overlap, with a corner radius from the larger width. Junctions sharper than the data's minimum angle are refused. Test: a T of two 2+2 roads trims each by the data's amount; a 20° junction is refused.
4. **Connections at a junction.** Lane-to-lane connections are short curves inside the junction shape, built from each lane's turn arrows (today's turn rules as defaults). Test: today's turn-rule tests pass on curved geometry.
5. **Save v38 and migration.** Old grid segments become straight curves on the same lines, so every older save still loads and plays. Test: each fixture from v26 on loads with the same roads.

### Areas along curves
6. **Area cells along a curve**, CS-style local cells (the developer's choice, 1 Nov 2026), in four parts:
   - **6a. Area shapes.** An area's cells are its own rows of 4 m cells along a stretch of road, turned with it; each a quad with a centre. Test: on straight grid roads they are today's cells; a bend's outer rows stretch and inner cells too small to use are dropped.
   - **6b. Overlap by shape.** Areas and roads block each other by overlapping shapes, not shared grid cells. Test: the same refusals as today on grid layouts, and overlaps on curves.
   - **6c. Areas store their shape (save v39).** Old saves migrate; bays, slots and stacks are laid out on the local cells. Test: every fixture loads and yards work as before.
   - **6d. Water and terminal paint** are read at each cell's centre. Test: today's coast and terminal tests pass.
7. **Stacks, slots and machines on curved areas.** Bays follow the area's rows; machines travel along them. Test: a yard block on a bend works a ship as one on a straight road does.

### Order after 6c-1 (1 Nov 2026)

Area layouts can't leave the global grid while vehicles drive cell to cell on it, so continuous traffic (step 8) comes next, before 6c-2, 6b, 6d and 7. Today's lane graph is grid geometry throughout (junctions crossed cell by cell, area flow and slots by grid steps), so the new network is built beside it from steps 1-4's curves and switched to in one tested step:

- **8a. Lane network.** Pieces: each lane's curve, trimmed at junctions, and each connection curve across them; routing over pieces. Standalone, with its own tests.
- **8b. Continuous traffic.** Vehicles hold a piece, a distance along it and a speed; they keep the standstill gap plus about a second of travel behind the one ahead, book a junction's box whole before entering, and drive at the lower of the road's speed limit (in the data) and their own. Standalone, with its own tests.
- **8c. Area driveways and slots as pieces.**
- **8d. The switch.** The sim's vehicles, trains, signals and areas move onto the network and traffic; LaneGraph and LaneTraffic go. Save v40. Test: every behaviour test passes.

### 6c-2: areas on their own cells (the developer's answers, 2 Nov 2026)

| Question | Answer |
|---|---|
| How the sim names a spot in an area | **Area + local cell:** (area id, column k, row r) on the area's own cells; its place in the world comes from the area's shape. |
| Handover slot length | **Two bays (24 m)** per slot, so a 16.5 m lorry fits once real lengths return; a block has half today's slots. A last odd bay is served from the slot beside it. |
| Driving inside an area | **Lanes along the rows:** the buffer strip and through lanes are one curved lane each along their row, with short connections into and out of each slot, as Cities: Skylines' parking lots are. |
| Order | **6c-2 before 6b**, as the revised order says. |

In four tested parts, new beside old and then the switch, as step 8 was:
- **6c-2a. Layouts on local cells.** AreaLayout lays buffer, slots (two bays), stacks, rails, lanes and kerbs out as (k, r) local cells from an area's shape. Standalone, with its own tests.
- **6c-2b. Driveways as lanes.** The lane network builds each area's row lanes and slot connections from its layout and shape, not from the lane graph. Standalone, with its own tests.
- **6c-2c. The switch.** Area flow, handovers, machines, stacks, trains, the view and Inspect name spots as (area, k, r); vehicles head for spots; save v41. Every behaviour test passes.
- **6c-2d. LaneGraph goes.** What still reads it (level crossings, which way traffic runs beside an area, old routing tests) moves to the network.

### Interim traffic data (2 Nov 2026)

The switch (8d) cut the showcase port's deliveries to a quarter (27 in 3,000 ticks against 117 on grid traffic). Measured causes: real vehicle lengths, because areas' handover slots are spaced for one-cell vehicles (27 to 63), and acceleration at 1.5 m/s² (61 to 102); area speed barely mattered. The developer chose interim data until step 7 lays areas and slots for real lengths: lorries and tractors 4 m, `area_kmh` 25, `accel` 20. Step 7's balance pass puts back 16.5 m, 15 m, 20 km/h and 1.5 m/s².

**Step 7's balance pass (2 Nov 2026):** the real values are back. With two-bay slots and "don't block the box", real acceleration and area speed cost almost nothing (124 to 122 showcase deliveries in 3,000 ticks); real lengths cost about 30%, through gridlock: queues on both lanes of the spine joined by U-turns into closed loops. Signals now count green in the traffic's real seconds (they counted sim seconds, a calendar minute each, so a phase lasted 20 game minutes), buffer room counts real lengths, and, the developer's choice, any vehicle stuck `stuck_minutes` (15) is moved on to where it was heading with its box, as Cities: Skylines despawns stuck vehicles (149 deliveries in 3,000 ticks, 52 moved on, no lorry gave up; save v42 counts them).

Step 9 also ports M7's "both lanes carry" test (lorries change lane before a turn so both lanes of a 2+2 road carry traffic), dropped with LaneTraffic in 8d-3, and "a lane change costs no extra cells" on a one-way road, dropped with LaneGraph in 6c-2d.

**Step 9 (2 Nov 2026):** a lane beside one running the same way is cut either side of a stretch of `lane_change_cells` (4) at its road's middle, on a road with `lane_change_clear_cells` (5, the longest vehicle and its gap) clear each side, and a lane change crosses the stretch each way: a connection booked as a junction's are, so two changes crossing take turns and a lorry changes only with room past. Routes pick lanes by length as before, so a lorry bound for a turn changes over before the junction rather than going round. The showcase port first fell from 162 deliveries in 3,000 ticks to 40. Two causes, each traced to its root: a gate whose way out met a lane change's end got no exit, because `nearest` took the change over the lane ending there (a road lane now wins a tie); and on roads shorter than a lorry each side of the stretch, a lorry that had changed lane stood at the next stop line with its rear still on the change, holding it, so the crossing change and its lane queued behind (such roads now have no change). After both: 157 deliveries, 41 vehicles moved on (47 before). Shortcut: one change stretch per road, at its middle, and a changing vehicle doesn't look behind in the lane it joins.

**Step 10 (2 Nov 2026):** signals, priority signs and level crossings already run on the new junctions and continuous traffic (8d-1; test_traffic_junctions and test_signals pass). Junction arms are still keyed by their way rounded to a grid step, exact while roads are built straight or at 45°; step 12's any-angle tool must key them by their exact way, since arms 30° apart can round to the same step.

**Step 11 (2 Nov 2026):** the endgame bench runs 15.65 ms a tick against the 19.5 ms gate (28.2 ms before), with the sim's behaviour unchanged; `docs/perf.md` has the record.

### Step 12: the developer's answers (3 Nov 2026)

| Question | Answer |
|---|---|
| Where a road's ends and junctions sit | **Anywhere**, as in Cities: Skylines: two roads crossing split at their exact crossing point; step 14's grid snap keeps today's layouts. |
| Level crossings at an angle | **Down to 30°** (`min_angle`); a shallower crossing is longer, so a train books more of it. |

In four tested parts, today's grid layouts behaving as they do now after each:
- **12a. Positions off the grid (save v43).** Road and track nodes are points anywhere; junctions, signals and signs are kept by their node's point, and arms by the segment they run along. Every older save migrates.
- **12b. Road shapes at any angle.** A road's lanes are quads along its curve, as an area's cells are; its ground (water, land, cost, upkeep) is the grid cells under their middles, and roads, track and areas block each other where quads overlap.
- **12c. Meeting at any angle.** A road crossing another splits both at the crossing point; one ending on or near another joins its node or splits it there; junctions below `min_angle` are refused; road and track cross down to 30°. Commands only.
**12b-1 (7 Nov 2026):** a road's lanes are quads along its curve (`RoadNet.shape`), its ground the grid cells under their middles (`ground`, and `footprint` for one not yet built); picking, water, land, breakwaters, area fill and the port map read the ground, and an area is blocked where its quads overlap a road's lane quads. Straight grid roads stand on exactly today's cells. A 45° road stands on its true diagonal rather than today's staircase rows: a few more cells, and a square-cut end that reaches over the line it starts on, so one started on the corner of owned land now needs the land past it. Track keeps its grid cells until step 19; road and track crossings are 12c's. 12b-2 lays areas along roads at any angle.
**12b-2 (7 Nov 2026):** areas lie along a road at any angle: column k is k cells along its curve, so a road offers a column per whole cell of its length (straight roads as today; a new area on a 45° road has cells a cell apart rather than a diagonal step). Whether a road runs beside an area, where a drag attaches, the far end of a drag and an RMG block's siding are read from the area's own points; its grid `start`, `end` and `out` are worked out from them, for quay aprons and berths, which stay on grid roads until step 21.
**12c (7 Nov 2026):** roads meet at any angle (`RoadNet._plan`). An end within a road's half width of its end or line joins it there; a road crossing another splits both at the crossing point, off the grid as it falls; lanes may overlap only near where roads meet, as far out as two roads that wide overlap at the angle they meet; arms parting by under `min_angle` are refused ("Roads meet at 20°; a junction needs at least 30°"), and a road along another, at under a degree, as before. Road and track may share ground only where they cross, at `min_angle` or more. A road's price and upkeep count the cells of its length (`RoadNet.cells_long`), so a 45° road now costs its true length, √2 times its run. Track keeps the grid rules until step 19.

The soak's random roads, drawn at any angle, were all refused before; now they build, and its run went from 186 s to 326 s. Measured: the time was the lane network's rebuilds (101, 1.2 s each), almost all in finding conflicting connections at one 4-way junction whose two stub roads were shorter than the junction cut them back (2.5 and 3.5 cells against 3.3 at each end): their lanes ran backwards and its connections were curves thousands of cells long. Grid layouts could make such stubs too, silently. Now a road is refused if any road at the junctions it touches would be shorter than its ends are cut back ("Too close to a junction"), worked out with the lane network's own junction shapes on a trial copy; the lane network asserts it; conflicts are measured only between connection segments in neighbouring cells; and a one-way road coming into a junction takes no connection out (it has no lane out). `RoadNet` now takes the data's junction rules.
- **12d. The straight tool** draws at any angle, snapping onto a road anywhere along it, with its cost by length.

**12d (7 Nov 2026):** the road tool draws at any angle. A drag's ends snap onto the roads (`RoadNet.snap_point`): a road's end, a junction or the highway's anchor within `SNAP_CELLS` first, else the nearest point of a road's line that close, never back onto the road the drag starts on; with Shift held, the grid point under the mouse. Commands carry points. The view draws each road between its nodes with its lanes square across its line, and its junction markings where the lane network's junction shapes cut it back. Shortcut: guides, angle snap and length snap are step 14's, so until then roads have no straight-or-45° snap; track keeps its grid tool until step 19.

### Traffic
8. **Continuous movement.** A vehicle has a lane, a distance along it and a speed. It keeps the data's gap behind the vehicle ahead, slows for a curve by its radius, and slows into junctions. This replaces one vehicle per cell. Test: a queue holds its gap; a vehicle on a tight bend is slower than on a straight.
9. **Lane changes where marked.** A vehicle changes lane along a stretch before its turn, as CS vehicles do, using today's lane choice by cost. Test: today's routing and lane-choice tests pass.
10. **Signals, priority and crossings** on the new junctions. Test: today's junction tests pass.
11. **Performance gate.** The mega port bench is no slower than before step 1. Spatial index per lane; cached lane lengths. The bench recorded in `docs/perf.md`.

### Drawing tools
12. **Straight tool** at any angle, with node merging and segment splitting where a road ends on or near another. Test: commands only; drawing is the view's work.
13. **Curved tool** (start, control point, end) and **freeform** (each piece continues tangent to the last).
14. **Snapping:** angle snap with guides (90°, 45° and 15° against nearby roads), length snap (whole cells), guide lines from road ends and perpendicular and parallel to nearby roads, parallel snapping at a set gap, and a grid-snap toggle that keeps today's grid layouts.
15. **Tooltip** with length, cost and angle beside the cursor.
16. **Lane-arrow editing** at a junction.
17. **Roundabouts:** a circle tool that builds a one-way ring with yield entries.
18. **Move It-style editing:** drag a built road's node or control point to reshape it, moving its areas with it, or refuse with the reason.

### Rail, water and berths
19. **Rail curves**, with a larger minimum radius from the data. Trains follow the track's curve.
20. **Ship lanes curve**, with a minimum radius from the data. Ships follow lanes; river channels follow rivers.
21. **Berths at an angle:** a berth is still one straight quay, placed at the angle that adds the least fill, or turned by a button to any angle the coast allows.

### Close
22. Showcase port rebuilt with curves (a curving spine, a roundabout, yards on a bend, a curved river channel), fixture, soak, playtest notes in `docs/playtests/m10.md`, tag.

## Risks

- **This touches the core of the sim.** The lane graph, traffic, areas, stacking layout and saves all change. Steps 1–5 change nothing the player sees, so a bad turn can be caught before traffic moves onto the new model.
- **Determinism.** Continuous movement uses floats. Each tick's order must stay fixed, and the soak test's same-seed checks must still pass.
- **Performance.** Cell occupancy was cheap. Gap-keeping needs each lane's vehicles in order, so it needs a sorted list per lane, not a scan.
- **Areas on curves** lose cells on the inside of a bend, as CS zoning does. Yard blocks on tight bends will be short, which is realistic.
