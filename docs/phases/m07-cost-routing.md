# M7 — CS2-style cost routing

**Goal.** Route vehicles by a cost made of time, comfort and money over a lane graph, as Cities: Skylines II does. Cell reservation from M2 stays underneath to stop vehicles colliding. Ship vanilla traffic tools (truck-only lanes, one-way gate lanes, simple signals), because CS1 players needed TM:PE for these.

**Depends on.** M6 (flow fields, path thread, packed vehicles).

**Exit criteria:**
- Route choice responds to cost: in a scripted scenario, adding a toll or signal delay shifts at least a set share of lorries to the alternative route.
- Vehicles use every lane of a multi-lane road (no lane hogging) within a set tolerance in the soak test.
- The endgame bench still meets the M6 budget.
- Determinism holds: the replay hash with threads matches the hash without.

## Steps

### Lane graph
1. **Lane model.** M5 builds the lanes from road segments and road types. This step adds the lane count per direction (1–3) to the cost model. Test: a 2+2 road gives 4 lanes, and a T junction gives the expected turn edges.
2. **Turn connections.** Each junction connects lanes to lanes by turn rules: left lanes turn left, right lanes turn right, middle lanes go straight. Test: the generated turn table matches the hand-written one for each junction shape.
3. **Reservation per lane.** M2 cell reservation moves to lane-cell slots, so overtaking on a multi-lane road becomes possible. Test: two lorries side by side in two lanes don't conflict.

### Cost
4. **Cost function.**
   - `cost = w_time × time + w_comfort × (turns + lane changes) + w_money × (fuel + tolls)`.
   - Weights are per vehicle type in the data.

   Test: unit tests on hand-made edges.
5. **Live travel times.** Each edge keeps a smoothed travel time from completed traversals, refreshed every N ticks, never mid-tick. Test: a jammed edge's time rises, then recovers.
6. **Routing uses cost.** The path thread runs A* on the lane graph with the cost, and flow fields to fixed targets are rebuilt on cost epochs. Test: the toll/signal shift scenario.
7. **Lane choice.** Vehicles change lanes ahead of turns, and spread across lanes by occupancy. Test: the lane-use exit criterion.

### Traffic tools
8. **Truck-only lanes.** Lane flags restrict vehicle types (e.g. port-only, no private cars, ready for the city later). Test: a restricted lane is never used by a disallowed type.
9. **One-way roads and gate lanes.** One-way tiles and gate-entry lanes. Test: no vehicle travels against a one-way.
10. **Signals.** Junction signals with phase timings set by the player. Defaults come from the data. Test: no conflicting movements during a phase.
11. **Priority signs** *(cuttable)*: yield and stop. Test: a yielding vehicle waits for a gap.
12. **Traffic overlay.** A view mode colours lanes by speed relative to free flow. Check: screenshot.

### From the M5 follow-up (24 Oct 2026)
Done already, on the M5 lane graph: turns join where the two lanes cross (no turn drives back over a cell), traffic turns back at junctions as well as dead ends, every cell where roads meeting at a junction overlap is a junction cell, and the road tool snaps onto nearby roads (`tests/test_junctions.gd`, `test_roads`). Step 2's turn rules (which lane may turn which way) are still to do.
- **Gates across both directions** (M5 playtest, open 3). Done 24 Oct 2026: lorries use the terminal's gate nearest them in and out; a two-way gate builds one on each side of the road; gates come in 2, 4 and 6 lanes, at manual, OCR and automated levels, with throughput shown in Inspect.

### Order and scope, with the developer (31 Oct 2026)
Where things stand: lanes per direction, lane changes, one-way roads and gate lanes are done (steps 1, 9, most of 3); tractor lanes already bar lorries (part of 8). Routes are the shortest distance, kept until a road changes; M6's path thread was never needed. The Traffic panel colours each road by the share of its vehicles stopped this moment.

Decisions: money is dropped from the cost (lorries are outside hauliers, so no tolls): cost is time plus turns and lane changes. All four of congestion routing, lane rules, signals and the overlay are in. M6 closes later (laptop bench, fixture, tag) alongside this phase. Order, so each step is measured by the one before:
- **A. Live travel times (step 5 first).** Each lane cell keeps a smoothed time vehicles spend in it, updated on a fixed tick so replays match. Test: a jammed cell's time rises, then falls back once the jam clears.
- **B. Traffic overlay from them (step 12).** The Traffic view colours each lane by its smoothed time against free flow, instead of who is stopped this moment. Check: screenshot of a jam.
- **C. Routing by cost (steps 4, 6).** Routes weigh each cell by its smoothed time, with turns and lane changes costing extra; kept routes are dropped on a cost epoch. Measure the route cost on the endgame bench before keeping it. Test: the second-road shift scenario.
- **D. Turn rules and lane choice (steps 2, 7).** Test: the turn table and the lane-use exit criterion.
- **D. Turn rules and lane choice (steps 2, 7).** Strict: on a road with more than one lane each way, the left lane turns left, the right lane turns right, and lanes between go straight (the outer lanes go straight too where no road turns their way). Vehicles change into the lane their next turn needs before the junction, and never inside a junction. Done 31 Oct 2026, except that a vehicle that can't get across waits for a gap rather than going on and being routed again (shortcut: re-route when lane changes are seen to stall). Test: the turn table for a crossroads and a T, and a 2+2 road carrying both lanes in the soak.
- **E. Signals and priority (steps 10, 11).** A tool to put signals on a junction or take them off, and to give each approach a give-way or stop sign. Inspect on a junction shows its phases and green times, set by the player, defaults from the data. Test: no conflicting movements in a phase; a vehicle at a give-way waits for a gap.
- **F. Terminals painted on a map** (brought forward from M8's notes, 31 Oct 2026). The Land tab opens a full-screen 2D map of the port in two modes, buying land and painting terminals. Painting uses a round brush in three sizes, an eraser and a fill that floods a road-bounded block. An area belongs to the terminal holding most of its cells; one in no terminal is idle ("paint it into a terminal"), and repainting moves areas at once. Inspect's terminal buttons go. Each terminal has an editable name and a colour used on the map, the berth board and Inspect; the map shows each terminal's berths, yard fill, gate turn time and moves and money a day, and marks one missing a gate, apron or yard. Saves from before are refused (FIRST moves up), as with the grid-lines change. Test: painting moves areas, an unpainted area is idle, the fill stops at roads.

### Close
13. **Bench and replay.** Endgame bench within budget, and the replay hash test with threads.
14. **Fixture and soak.** New save fixture, and lane invariants in the soak test.
15. **Public playtest build.** Notes go in `docs/playtests/m7.md`.
16. **Close the phase.** Tag `m7`.
