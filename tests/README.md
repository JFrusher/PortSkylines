# Tests and tools

All commands run from the repository root, with `godot` being the version pinned in `.github/workflows/ci.yml`.

## Tests

```bash
godot --headless --import
for t in tests/test_*.gd; do timeout 300 godot --headless --script "res://$t"; done
```

Each test prints `tests: N failure(s)` and exits non-zero on failure. CI also fails on any `SCRIPT ERROR` or `ERROR` line. Godot keeps running when a script fails to compile, so always use `timeout`.

| File | Covers |
|---|---|
| `test_rules.gd` | The game's rules: ship calls, crane timing and outreach, the yard's pace, dwell, the gate, upkeep, events, the ledger, services, offers, reputation, storage and move prices, loans, bailouts, creative mode, land, crane orders, dredging, milestones, the scoreboard, Inspect and bulldozing areas in use |
| `test_grid.gd` | The 4 m grid: site size in cells, metres round-trip, cell centres |
| `test_roads.gd` | Roads and areas on the 4 m grid: segments, angles, shared nodes |
| `test_lane_traffic.gd` | Traffic on the lane graph: head-on, queues, a full ring, junction booking, a 45° merge |
| `test_first_slice.gd` | M5's first slice: a port built by commands works its first ship end to end on roads and areas |
| `test_clock.gd` | Calendar time and frame-to-tick conversion |
| `test_guide.gd` | The guided start, played by commands on the base rules, ends with the first ship worked |
| `test_replay.gd` | The same command log gives the same state at 1, 3 and 6 ticks per frame |
| `test_save.gd` | Save files, atomic replace, refusing bad files and payloads, saves from before roads and areas refused with the reason, and every committed fixture |
| `test_view.gd` | Road meshes facing up, vehicles drawn along corner arcs without jumps, the STS crane's move cycle, and deck stacks |
| `test_crash_report.gd` | Errors, not warnings, ask for a crash report; a report holds the log, a loadable save and the content hash |
| `test_assets.gd` | Every model in `assets/` imports with LODs |
| `test_content.gd` | The game data loader and its error messages |
| `test_economy_scenarios.gd` | M3's scripted scenarios: overbooking makes calls late, higher storage fees lower dwell, and dredging lets a Panamax call |
| `test_soak.gd` | Two game days of calm and congested ports under random commands, with ledger invariants checked every tick and midnight, and stack, box, cell, slot and machine invariants every vehicle second |

## Save fixtures

`tests/fixtures/save_v<N>.bin` is a save written at version N. When `SaveFile.VERSION` goes up, run `godot --headless --script res://tests/make_fixtures.gd` once and commit the new file. Never regenerate a fixture once its version is on `main`: they prove that old saves still load, or, before v11 (roads and areas), that they are refused with the reason. While a PR is still changing the format of the new version, regenerate that version's fixture in the same PR.

## Benchmarks

`bench/sim_bench.gd` times the sim headless and fails when it goes over the budget in `docs/perf.md`. CI runs it on every push:

```bash
godot --headless --script res://bench/sim_bench.gd
```

The render bench and the endgame bench built tile ports and went with them; M6 rebuilds them on roads and areas.

## Screenshots

For view changes, render the real scene under `xvfb-run -a godot --rendering-method gl_compatibility --resolution 1280x720` and compare it by eye with the previous build before committing.
