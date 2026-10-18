# M2 — A real terminal loop

**Goal.** Replace "a ship drops 12 boxes" with the chain berth → quay crane → horizontal transport → yard → gate, for imports and exports, using the tuning table in the roadmap.

**Depends on.** M1 (ticks, commands, saves, data files, MultiMesh tiles).

**Exit criteria:**
- Two vehicles never occupy the same cell in the same tick. A test asserts this every tick of the soak.
- A Panamax call with 120 moves and 3 cranes at 25 moves per game-hour takes moves / (cranes × rate × 0.9) of game time, within ±5%.
- In a soak test, yard throughput tracks capacity / dwell within ±10%.
- In a blind manual playtest, a tester can explain why a gate queue formed.
- Save version 2 migrates the v1 fixture.

## Steps

### Ships and berths
1. **Add ship classes to the data.** `data/base/ships.json` defines Feeder and Panamax: length in tiles, draft in metres, moves per call, and import/export split. Values come from the tuning table. Test: the loader rejects a class with no draft.
2. **Add berths as player-made objects.**
   - A berth is a straight run of quay tiles along water. `PortMap.berths()` derives them: a contiguous run is one berth, and it has a length.
   - The map gets a water depth per tile, uniform for now and taken from the data.

   Test: an L-shaped quay gives two berths, and a run of 12 tiles has length 12.
3. **Match ships to berths.** A ship can only call at a berth with length ≥ the class length and depth ≥ the class draft. `_call_ship` picks the class from a weighted arrival table in the data. Test: a Panamax never calls at a berth of 8 tiles.
4. **Lay ships along the berth.** The ship occupies its full berth span, and the view scales the hull to the class length. Check: screenshot.

### Quay cranes
5. **Add an STS crane entity.**
   - Place `crane` on a quay tile with `{"op": "place_crane", "cell"}`. The cost is from the data, and cranes slide along their berth.
   - `PortSim.cranes` is a list with position and rate.

   Test: placing a crane on a road fails, and two cranes can't share a cell.
6. **Split work between cranes.** On arrival, the ship's moves are split across the cranes on its berth by bay ranges. Each crane works at the data rate in moves per game-hour × 0.9 interference. Test: the timing exit criterion.
7. **Crane outreach.** The data gives each crane an outreach in rows, and a ship class needs a minimum. A crane with too little outreach can't work that ship. Test: a Panamax with only feeder cranes waits and shows a status.
8. **Draw cranes.** Crane MultiMesh, with the trolley animated from the crane's state. Check: screenshot.

### Horizontal transport
9. **Add terminal tractors.**
   - These are vehicles owned by the terminal: a depot tile plus a fleet size bought with a command.
   - A crane move needs a tractor to carry the box between the crane's apron cell and a yard block. The teleport from M0 is removed.

   Test: with 0 tractors, a ship makes no progress, and with 1 it progresses slowly.
10. **Add cell reservation traffic.**
    - `Traffic` books (cell, tick range) intervals before a vehicle moves.
    - A booking that overlaps an existing one fails, and the vehicle waits a tick and retries.
    - Bookings for a step are inserted in a fixed cell order so two vehicles can't deadlock by booking in opposite orders.

    Test: two lorries on a 1-wide road head-on: one waits and neither overlaps. The soak test asserts no shared cells.
11. **Resolve deadlocks.** A vehicle that has waited longer than a data limit replans, avoiding the blocking cell. If no route exists, it returns to its depot or the highway. Test: a ring of four vehicles that are all blocking each other clears within the limit.
12. **Cache routes.** Routes are cached on (from, to), and the cache clears on any road change. Test: a hit after the first request, and a miss after a bulldoze.

### Yard
13. **Add yard blocks.**
    - A yard area is a rectangle of yard tiles. The player assigns it an equipment type (reach stacker or RTG) with a command.
    - Capacity per tile comes from the data (6 / 12).

    Test: capacity changes when the equipment changes, and the change is refused while the block holds more boxes than the new capacity.
14. **Add yard equipment** as entities assigned to a block. Each stack or unstack takes equipment time from the data, so tractors and lorries queue at the block. Test: halving the equipment count doubles the handling time under load.
15. **Give boxes a purpose.** A box carries `kind` (import/export), `size` (20/40), `dwell_due` (calendar time) and `id`. The yard tracks boxes, not counts, and `stacked` becomes derived. Save version 2 with a migration from v1 counts. Test: the v1 fixture migrates and plays.
16. **Choose where to stack.** Imports go to the nearest import block with space and exports to export blocks. A block's role is set by the player. Test: an import never lands in an export block.

### Imports, exports and gate
17. **Import dwell.** A lorry for an import box is only released after `dwell_due`, which is about 1 game day by default from the data. Test: no pickup happens before dwell.
18. **Exports.** Lorries arrive with export boxes for the next ship's class. Each box sits in an export block until a ship of a matching service loads it. Ships load after discharge. Test: a ship departs with the scheduled exports, and money is counted per move.
19. **Add a gate building.**
    - A gate tile run with N lanes and a processing time per lorry from the data.
    - Lorries queue on the road outside. The highway entry connects to the gate, and lorries can't bypass it.

    Test: a 1-lane gate under load forms a queue, and 2 lanes halve the average wait.
20. **Track gate turn time.** Each lorry records the time from gate in to gate out, and the HUD shows the rolling average in game minutes. Test: the turn time equals the sum of its legs.

### Running costs and KPIs
21. **Upkeep.** Every tile kind and entity has a daily upkeep in the data, charged at the calendar day boundary. Test: money drops by exactly the sum at midnight.
22. **KPI panel.** Berth productivity (moves per hour at berth), crane rate, gate turn time, yard utilisation and boxes delivered per day. The view only reads `PortSim.kpis()`. Test: the KPIs match hand-computed values in a scripted scenario.
23. **Status messages become an event list.** The sim appends `{tick, kind, text}`, the HUD shows the latest 5, and the old `status` string is removed. Test: a turned-away ship produces one event.

### Close
24. **Update the soak test** for cranes, tractors, gate, imports and exports, with the no-shared-cell invariant.
25. **Commit the `save_v2.bin` fixture.**
26. **Blind playtest.** Give a tester no instructions; ask them to make a gate queue and explain it. Record notes in `docs/playtests/m2.md`.
27. **Close the phase.** Check all exit criteria and tag `m2`.
