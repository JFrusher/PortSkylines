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
| `test_sim.gd` | Build and bulldoze rules, the ship-to-lorry loop, commands, save dictionaries, the tile index |
| `test_clock.gd` | Calendar time and frame-to-tick conversion |
| `test_replay.gd` | The same command log gives the same state at 1, 3 and 6 ticks per frame |
| `test_save.gd` | Save files, refusing bad files, and every committed fixture |
| `test_content.gd` | The game data loader and its error messages |
| `test_soak.gd` | 10,000 ticks of random commands with invariants checked every tick |

## Save fixtures

`tests/fixtures/save_v<N>.bin` is a save written at version N. When `SaveFile.VERSION` goes up, run `godot --headless --script res://tests/make_fixtures.gd` once and commit the new file. Never regenerate an old fixture: they prove that old saves still load.

## Benchmark

Needs a renderer, so use a display or `xvfb-run`:

```bash
xvfb-run -a godot --rendering-method gl_compatibility --resolution 1280x720 --script res://bench/bench.gd -- 256
```

Record results in `docs/perf.md` with the machine and renderer.

## Screenshots

For view changes, render the real scene under `xvfb-run` the same way and compare it by eye with the previous build before committing.
