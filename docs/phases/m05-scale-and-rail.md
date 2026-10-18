# M5 — Scale and on-dock rail

**Goal.** Reach endgame entity counts on a mid-range PC, and add rail as the second land mode, the answer to truck spam. Also add reefers, Neopanamax, and hinterland demand.

**Depends on.** M4.

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
   - Ad-hoc routes run on one worker thread with its own `AStarGrid2D` copy (the AStar classes are not thread-safe).
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

### Close
19. **Endgame bench passes** on the target PC. Record it.
20. **Fixtures and soak.** Add the new save fixture and rail to the soak test.
21. **Public playtest build.** Notes go in `docs/playtests/m5.md`.
22. **Close the phase.** Tag `m5`.
