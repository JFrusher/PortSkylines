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
6. **Area cells along a curve.** An area's cells are laid in rows following its road's side, as CS zoning is: one row of 4 m cells per depth step, spaced along the curve. Blocking and the coast use the same cells. Test: an area along a 90° bend has the same cell count as along a straight road of the same length, give or take the inner-corner loss.
7. **Stacks, slots and machines on curved areas.** Bays follow the area's rows; machines travel along them. Test: a yard block on a bend works a ship as one on a straight road does.

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
