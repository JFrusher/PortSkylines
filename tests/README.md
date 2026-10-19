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
| `test_sim.gd` | Build rules, berths, crane rate and outreach, yards and gear, dwell, exports, gates, upkeep, KPIs, events, the ledger, services, offers, reputation, storage and move prices, loans, bailouts, creative mode, land, dredging, crane orders, milestones, the scoreboard, save dictionaries, the inspect tool, bulldozing things in use |
| `test_traffic.gd` | Lanes: head-on, queues, a ring, giving up when stuck, and a junction booking when the map changes |
| `test_clock.gd` | Calendar time and frame-to-tick conversion |
| `test_guide.gd` | The guided start, played by commands on the base rules, ends with the first ship worked |
| `test_replay.gd` | The same command log gives the same state at 1, 3 and 6 ticks per frame |
| `test_save.gd` | Save files, atomic replace, refusing bad files and payloads, and every committed fixture |
| `test_view.gd` | Road pieces chosen from neighbours, and vehicles drawn along corner arcs without jumps |
| `test_content.gd` | The game data loader and its error messages |
| `test_economy_scenarios.gd` | M3's scripted scenarios: overbooking makes calls late, higher storage fees lower dwell, and dredging lets a Panamax call |
| `test_soak.gd` | Two game days of calm and congested ports under random commands, with ledger, capacity, box and lane invariants checked every tick and every midnight |

## Save fixtures

`tests/fixtures/save_v<N>.bin` is a save written at version N. When `SaveFile.VERSION` goes up, run `godot --headless --script res://tests/make_fixtures.gd` once and commit the new file. Never regenerate a fixture once its version is on `main`: they prove that old saves still load. While a PR is still changing the format of the new version, regenerate that version's fixture in the same PR.

## Benchmark

Needs a renderer, so use a display or `xvfb-run`:

```bash
xvfb-run -a godot --rendering-method gl_compatibility --resolution 1280x720 --script res://bench/bench.gd -- 256
```

Record results in `docs/perf.md` with the machine and renderer.

## Screenshots

For view changes, render the real scene under `xvfb-run` the same way and compare it by eye with the previous build before committing.
