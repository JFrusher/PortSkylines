# M1 — Foundations

**Goal.** Remove M0's structural shortcuts before content piles on top of them. Players see only smoother motion, a 6× speed and save/load.

**Depends on.** M0 (the current `main`).

**Exit criteria** (all automated unless noted):
- The same seed and command log give the same `state_hash()` after 10,000 ticks, whether the ticks run 1, 3 or 6 per frame.
- Save → load → save produces identical bytes, and every committed save fixture loads.
- All tunable numbers live in `data/base/*.json`. A malformed data file stops the game with a clear error.
- On a 256×256 synthetic map, tile draw calls grow with the number of chunks, not tiles. The baseline frame time is recorded in `docs/perf.md`.
- A seeded 10,000-tick soak test with random valid commands passes the invariant checks in CI.
- CI is green on the pinned Godot 4.7.x.

## Steps

### Housekeeping
1. **Mark M0's shortcuts.** Add `# shortcut:` comments where:
   - lorries ignore each other (`PortSim._drive`);
   - boxes jump from crane to yard (`PortSim._work`);
   - `PortMap.access_road` takes the first adjacent road.

   Check: `grep -rn "shortcut:" scripts` lists 3 lines.
2. **Upgrade Godot to the current 4.7.x patch.**
   - Change the download URL in `.github/workflows/ci.yml` and `config/features` in `project.godot`.
   - Reimport and run the tests, the smoke run and one screenshot under xvfb.

   Check: CI green, and the screenshot matches M0's layout.
3. **Pin the version.** Name the exact Godot version in the README and in one variable in CI. Check: a single grep finds the version string in both places.
4. **Make missing types an error.** Set `debug/gdscript/warnings/untyped_declaration` and `inferred_declaration` to error in `project.godot`, then add the missing types. Check: `--import` prints no warnings, and the tests pass.

### Fixed tick and two clocks
5. **Add `scripts/sim/sim_clock.gd` (`SimClock`).**
   - `TICK_SECONDS` is 1/20 s of vehicle time.
   - `calendar_minutes` advances by `CALENDAR_MINUTES_PER_TICK` each tick, which is 0.05, so one game hour takes 60 s at 1×.
   - It exposes `tick()`, `game_day()`, `game_hour()`.

   Test: 1,200 ticks equal 1 game hour, and 28,800 ticks equal 1 game day.
6. **Replace `PortSim.step(dt)` with `PortSim.tick()`.**
   - It uses `SimClock.TICK_SECONDS` everywhere.
   - Ship arrival timers count calendar minutes. Vehicle motion counts vehicle seconds.
   - Update the tests to run tick counts.

   Test: the existing four tests pass, rewritten as tick counts.
7. **Add a frame-to-ticks accumulator** as pure function `SimClock.ticks_for(accumulated: float) -> int`.
   - The remainder carries over.
   - At most 8 × speed ticks run per frame, and any excess is dropped. Log the drop in debug builds only.

   Test: deltas of 0.016, 0.1 and 2.0 s give the expected tick counts and remainders.
8. **Switch `main.gd` to the accumulator.** Per frame: add `delta × speed`, run the ticks, and pass `alpha = remainder / TICK_SECONDS` to the view. Check: smoke run clean, and the game still plays at 1×.
9. **Interpolate the view.**
   - `Lorry` and `Ship` keep their position from the previous tick.
   - `WorldView` draws `prev.lerp(now, alpha)`.

   Check: a manual screen capture at 1× shows no stepping.
10. **Add 6× speed.** HUD speeds become `[0, 1, 2, 3, 6]`. Check: the HUD shows five buttons, and 6× runs six times as many ticks per frame.

### Determinism
11. **Add a seeded RNG.** `PortSim` owns a `RandomNumberGenerator`, seeded from the constructor. Nothing calls the global `randi`/`randf`. Check: `grep -rn "randi\|randf" scripts` finds only `rng.` calls.
12. **Add `PortSim.state_hash() -> int`,** made by hashing `var_to_bytes(to_dict())` (to_dict comes in step 15). Add a temporary hash over `money`, `delivered`, `stacked` and `lorries.size()` now. Test: two sims fed identical steps hash the same.
13. **Make player actions commands.**
    - `PortSim.apply(cmd: Dictionary) -> String` handles `{"op": "build", "kind": int, "cell": Vector2i}` and `{"op": "bulldoze", ...}`. Unknown ops are an error.
    - `main.gd` queues commands, and they apply at the start of the next tick.
    - `build`/`bulldoze` stay as the internal implementation.

    Test: an unknown op fails, and a build command matches a direct build.
14. **Replay test.** `tests/test_replay.gd` takes a seeded random sequence of commands and runs it ticked 1, 3 or 6 per frame. Test: all three hashes are equal after 10,000 ticks.

### Saves
15. **Add `to_dict()`/`from_dict()` on `PortMap`, `Ship`, `Lorry` and `PortSim`.**
    - Use plain types only: packed arrays, ints, floats, Vector2i, arrays and dictionaries.
    - `state_hash` switches to the full dictionary.

    Test: running 500 ticks, round-tripping, then running 500 more gives the same hash as running 1,000 straight.
16. **Add `scripts/sim/save_file.gd` (`SaveFile`).**
    - `save(path, sim)` writes `{"version": VERSION, "sim": dict}` with `FileAccess.store_var(value, false)`.
    - `load(path) -> PortSim` reads with `get_var(false)`. An unknown version is an error.
    - `MIGRATIONS` is an empty array of callables indexed by version.

    Test: save → load → save produces identical bytes, and a version 999 file fails.
17. **Commit a save fixture.**
    - Add `tests/fixtures/save_v1.bin`, generated by `tests/make_fixtures.gd`.
    - A test loads every `save_v*.bin`, migrates it and runs 100 ticks.

    Test: CI loads the fixture.

### Data-driven content
18. **Add `data/base/rules.json`** holding every number currently in `PortSim`/`PortMap` constants: costs, fee, intervals, boxes, crane seconds, yard capacity, lorry speed, map size and sea width. The keys are documented in `docs/content.md`.
19. **Add `scripts/sim/content.gd` (`Content`)**, a loader for `res://data/base/*.json`.
    - Every required key is checked for presence and type.
    - Any problem stops with `push_error` and `assert(false)` naming the file and key.

    Test: a fixture missing one key fails with that key in the message.
20. **Replace the constants.** `PortSim` and `PortMap` take a `Content` in their constructor, and the constants are deleted. Test: all tests pass, and `grep -n "const .*:= [0-9]" scripts/sim` is empty except for enums and `NONE`.
21. **Add a content hash to saves.** The save stores a hash of the loaded content. On load, a different hash is a hard error until migrations exist for content. Test: changing a number in the data makes old saves refuse to load, with that reason.

### Rendering
22. **Cache tile lists.** `PortMap` keeps one `Array[Vector2i]` per tile kind, updated in `place()`, so `cells_of()` no longer scans the whole map. Test: the cached lists match a full scan after 1,000 random places.
23. **Add `scripts/view/tile_layer.gd`.**
    - One `MultiMeshInstance3D` per (32×32 chunk, tile kind), sized to its maximum `instance_count`, with `visible_instance_count` set to what is used.
    - Only chunks touched by a change are rebuilt.
    - It replaces `WorldView._tiles`.

    Check: a screenshot matches the previous build.
24. **Draw yard stacks as one MultiMesh per chunk,** with height from `stacked[cell]`. Check: a screenshot with a full yard looks right.
25. **Mark vehicles and ships.** They stay as nodes for now (fewer than 100). Add a `shortcut:` comment that M5 moves them to MultiMesh.

### Benchmarks and soak
26. **Add `bench/bench.gd`.**
    - It builds a seeded 256×256 map with about 30% roads, quays and yards.
    - It runs 600 frames under xvfb and prints average/95th-percentile frame time and `RenderingServer` draw calls.
    - Write how to run it in `tests/README.md`.

    Check: the output is recorded in `docs/perf.md` with the machine described.
27. **Soak test** in `tests/test_soak.gd`.
    - 10,000 ticks with seeded random valid commands.
    - Invariants checked every tick: money changes equal building costs plus fees; `0 ≤ stacked ≤ capacity`; claimed ≤ stacked; every lorry path cell is a road.
    - Added to CI.

    Test: passes. Prove it can fail by breaking one invariant locally.
28. **Close the phase.** Run every exit criterion, update `docs/perf.md`, and tag `m1`.
