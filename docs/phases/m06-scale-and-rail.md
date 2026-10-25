# M6 — Scale and on-dock rail

**Goal.** Reach endgame entity counts on a mid-range PC, and add rail as the second land mode, the answer to truck spam. Also add reefers, Neopanamax, and hinterland demand.

**Depends on.** M5 (roads and areas). This phase started before M5 existed, as M5 itself:
- Done and kept: step 4 (vehicle MultiMeshes).
- Done on tiles, to redo on roads and areas: steps 1 and 2 (the render bench, the endgame port and save, and the sim profiler went with the tile model at M5 step 22.2; `docs/perf.md` keeps their tile figures as the baseline) and 6 (detail by distance: the tile stacks' slabs and ChunkedMeshes went too).
- Done on tiles and redone in M5: step 7 (distance fields), as part of the lane graph.
- Skipped on evidence: step 5 (ships and cranes cost 5 ms of 168 render; see `docs/perf.md`).
- Waiting for M5's model: steps 3, 8, 9, 11–15, 17 and 18.

**Exit criteria:**
- The endgame benchmark save (about 2,000 lorries, 20,000 stacked boxes, 6 berths, 2 trains) holds 60 fps at 1080p on the GTX 1660-class target at 1×, and stays playable at 3×.
- Ticks stay deterministic with threading on: the replay hash test runs with threads enabled.
- Moving 30% of volume to rail measurably shortens the gate queue in a scripted scenario.
- The save version bumps, and all fixtures migrate.

## Steps

### Measure first
1. **Build the endgame benchmark save.**
   - A script generates `bench/endgame.bin` at the target counts.
   - The bench scene loads it and prints the time per frame spent on sim, path and render.

   Check: baseline numbers recorded in `docs/perf.md`.
2. **Profile.** Note the top 5 hot functions in `docs/perf.md`. Each following step must name the hot spot it removes.

### Data layout
3. **Vehicles as parallel packed arrays.**
   - `Vehicles` holds `PackedVector2Array` positions, `PackedInt32Array` states and the rest.
   - Lorry and tractor objects become indices.
   - Save stays dictionary-based through `to_dict`.

   Test: the replay hash is unchanged before and after the step.
4. **Vehicles in a MultiMesh** per type. The buffer is written once per frame with `set_buffer_interpolated` from the packed arrays. This removes M1's `shortcut:` note on vehicles. Check: bench draw calls are constant in vehicle count.
5. **Ships and cranes in a MultiMesh** where their counts justify it. Check: bench.
6. **Distant yards.** Set visibility ranges on stack and equipment MultiMeshes. Check: bench shows fewer instances drawn at far zoom.

### Pathfinding at scale
7. **Flow fields to fixed targets.**
   - One integration field per gate, berth apron and yard block entrance, rebuilt only when roads change.
   - Lorries follow the field.

   Test: a lorry following the field takes a path of the same length as A*.
8. **Background path thread.**
   - Ad-hoc routes run on one worker thread with its own copy of the lane graph (the AStar classes are not thread-safe), so one-way and 45° links route as on the main thread.
   - Requests and results are queued, and results apply at the start of the next tick in request order so the outcome stays deterministic.

   Test: replay hash with the thread on equals the hash with it off.
9. **Parallel vehicle kinematics.**
   - `WorkerThreadPool.add_group_task` advances positions.
   - Reservation booking stays single-threaded and runs in a fixed order.

   Test: the replay hash is unchanged, and the bench shows a gain.
10. **GDExtension only if the profiler proves it** *(conditional)*. If a single loop is still over its budget, port only that loop to C++ GDExtension behind the same interface. Test: the replay hash is unchanged, and the bench gain is recorded.

### On-dock rail
11. **Rail tiles and sidings.** Track tiles join the network as a separate graph from roads. A siding is a straight run beside a yard block. Test: rail and road graphs are independent, and a level crossing tile belongs to both with reservation.
12. **Rail-mounted gantry (RMG)** over a siding plus one yard block. It loads and unloads wagons at a rate from the data. Test: one train's moves take the data time.
13. **Trains.** Trains run on a schedule from off-map with N wagons. Imports booked to rail leave by train instead of by lorry. Test: rail-booked boxes never leave by gate.
14. **Modal split.** Each line has a share of boxes going by road or rail, and the player can offer a rail discount to shift it. Test: the 30% rail scenario cuts the gate queue.
15. **Level crossings.** Road traffic waits while a train has the crossing booked. Test: no lorry occupies a crossing during a train's booking.

### Hinterland and new cargo
16. **Hinterland demand.** Off-map destinations come from the data with road/rail distances. Import boxes get destinations, and export boxes get origins. The demand curve grows with milestones. Test: the box mix matches the data shares within tolerance over 10 game days.
17. **Reefers.** Reefer plug yard tiles. Reefer boxes must be plugged within N minutes or the line is fined. Power demand is 4 kW average and 7 kW on hot days, billed with a peak demand charge. Test: a ship of reefers sets a measurable peak.
18. **Neopanamax.** Add the class with its berth length, depth and outreach requirements, and wider-outreach cranes unlocked by milestone. Test: berth and channel gating as in M2/M3.

### From the developer's notes and the M5 playtest (24 Oct 2026)
- **More than one cell a tick.** `LaneTraffic.advance` enters at most one new cell a tick, which caps every vehicle at 20 cells (80 m) a game minute, 4.8 km/h, whatever the data says: lorries (125 m) and tractors (150 m) both measured at 80 m in the second M5 playtest. Let `advance` enter cells one at a time up to its speed, then tune lorry and tractor speeds in the data. Test: a vehicle on a clear road covers the data's distance a game minute, and the replay hash holds.
- **Exports only for booked calls.** Done 24 Oct 2026: export lorries come only while ships in port and services calling within `export_lead_hours` want more exports than the port holds (`AreaFlow.export_demand`). Step 16 still drives the mix.
- **Rush and sensitive boxes.** Beside reefers: rush boxes carry a deadline that a late call misses with a fine, and sensitive (dangerous goods) boxes need a block whose rules allow them, kept a data distance from other blocks. Test: a rush box past its deadline fines its line, and a sensitive box is never stacked in a block that refuses it.
- **Quay add-ons.** Behind an STS crane's apron, a rail siding or road add-on snapped to the apron's land side, as CS2 building upgrades snap on. Boxes for rail go straight to the siding. Test: an add-on is only built behind an apron, and rail-booked imports never pass the gate.
- **Weekly calendar.** A panel showing each agreed service's window across the week, and the berth each will use, with clashes in red. Check: screenshot; test: a clash is listed when two windows overlap on one berth.
- **Cost per box.** A panel replacing a tax-style view: income, upkeep and labour per move, per terminal and per line, as the port's main money lever. Test: the panel's per-move figure equals the ledger's totals over moves.
- **Remove one STS crane** without bulldozing its apron (M5 playtest, open 6). Test: removing a crane frees its fetchers and leaves the apron.
- **Ships and STS cranes at true scale** (M5 playtest, open 7). Check: screenshot beside yard boxes.

### Close
19. **Endgame bench passes** on the target PC. Record it.
20. **Fixtures and soak.** Add the new save fixture and rail to the soak test.
21. **Public playtest build.** Notes go in `docs/playtests/m6.md`.
22. **Close the phase.** Tag `m6`.
