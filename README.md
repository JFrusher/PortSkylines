# Port Skylines

A port-building game in the spirit of city builders. Lay roads from the
highway, build quays on the coast and container yards inland; ships call at
connected quays, cranes stack their boxes in the nearest reachable yard, and
lorries from the highway collect each box and pay for it.

See [docs/ROADMAP.md](docs/ROADMAP.md) for the researched roadmap and open questions.

Built with [Godot 4.7.2](https://godotengine.org/download) (standard build, GDScript). CI pins the same version in `GODOT_VERSION` in `.github/workflows/ci.yml`.

## Play

Open `project.godot` in Godot and press F5.

| Input | Action |
|---|---|
| Left click / drag | Build the selected tile, or bulldoze |
| WASD / arrow keys | Pan |
| Q / E | Rotate |
| Mouse wheel | Zoom |

## Layout

| Path | Role |
|---|---|
| `data/base/rules.json` | Every tunable number; keys in `docs/content.md` |
| `scripts/sim/content.gd` | Loads and checks the game data |
| `scripts/sim/sim_clock.gd` | Fixed ticks: vehicle seconds and calendar minutes |
| `scripts/sim/port_map.gd` | Tile grid, build rules, road routing. No money, no rendering |
| `scripts/sim/port_sim.gd` | Money, ships, cranes, yards, lorries. Changed only through `apply(command)` and `tick()` |
| `scripts/sim/save_file.gd` | Versioned save files |
| `scripts/world_view.gd` | Draws the sim in 3D; reads it, never changes it |
| `scripts/chunked_meshes.gd` | One MultiMesh per map chunk |
| `scripts/hud.gd` | Toolbar, speed buttons, save/load, money and status |
| `scripts/camera_rig.gd` | Pan, rotate, zoom camera |
| `scripts/main.gd` | Wires them together, turns frame time into ticks and clicks into commands |

## Test

See [tests/README.md](tests/README.md) for tests, save fixtures, the benchmark and screenshots.
