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

### Close
13. **Bench and replay.** Endgame bench within budget, and the replay hash test with threads.
14. **Fixture and soak.** New save fixture, and lane invariants in the soak test.
15. **Public playtest build.** Notes go in `docs/playtests/m7.md`.
16. **Close the phase.** Tag `m7`.
