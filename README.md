# Port Skylines

A port-building game in the spirit of city builders. Draw roads on a 4 m
grid from the highway to the coast, drag quay aprons, gates and yard blocks
out along them into terminals, place quay cranes and buy tractors. Shipping lines offer weekly services; accepted
ones call in their window, berth by class and depth, and wait at anchorage
when the berths are full. Cranes work them at a set rate, tractors shuttle
boxes to handover slots at import and export blocks where yard machines
stack them, and lorries check in at the gate to collect imports and bring
exports. Lines pay per crane move, boxes kept past their
free days pay storage, and upkeep is paid every midnight. Every dollar is in
the ledger; loans tide the port over, and a bailout catches it if it stays
in the red. Milestones on TEU moved unlock RTGs, loans, land, dredging and
Panamax services. Creative mode lifts the money limit.

See [docs/ROADMAP.md](docs/ROADMAP.md) for the researched roadmap and open questions.

Built with [Godot 4.7.2](https://godotengine.org/download) (standard build, GDScript). CI pins the same version in `GODOT_VERSION` in `.github/workflows/ci.yml`.

## Play

Open `project.godot` in Godot and press F5.

| Input | Action |
|---|---|
| Left click / drag | Draw a road, drag an area out along a road, place, set or bulldoze |
| WASD / arrow keys | Pan |
| Q / E | Rotate |
| Mouse wheel | Zoom |

## Windows build

`export_presets.cfg` has one preset, "Windows", with the shader baker on so
shaders are compiled at export instead of stuttering on first use. Every
pushed tag makes CI build `PortSkylines-<tag>-windows.zip` as a workflow
artifact. CI exports headless, without a GPU, so its build skips the shader
baker; export from the Godot editor on a machine with a GPU for a baked
build:

```bash
godot --export-release "Windows" build/windows/PortSkylines.exe
```

## Layout

| Path | Role |
|---|---|
| `art/`, `assets/` | Blender sources (Git LFS), and the `.glb` models exported from them; see `art/README.md` |
| `data/base/*.json` | Every tunable number (rules, ships, equipment); keys in `docs/content.md` |
| `scripts/sim/content.gd` | Loads and checks the game data |
| `scripts/sim/sim_clock.gd` | Fixed ticks: vehicle seconds and calendar minutes |
| `scripts/sim/grid.gd` | The 4 m grid and the site's size in cells |
| `scripts/sim/road_net.gd`, `lane_graph.gd`, `lane_traffic.gd` | Roads at 0, 45 and 90°, the lanes routed over them, and one vehicle per cell |
| `scripts/sim/areas.gd`, `area_layout.gd` | Areas dragged along roads, grouped into terminals, and how each lays itself out |
| `scripts/sim/area_flow.gd` | Ships at aprons, cranes, tractors and lorries moving boxes by slots and machine jobs |
| `scripts/sim/handovers.gd`, `machines.gd`, `area_stacks.gd` | Handover slots and queues, yard machines' jobs, and the stacks in yard blocks |
| `scripts/sim/port_sim.gd` | Money, ships, cranes, boxes, vehicles, land, upkeep, KPIs. Changed only through `apply(command)` and `tick()` |
| `scripts/sim/ledger.gd` | The books: every change of cash, by category and day |
| `scripts/sim/contracts.gd` | Shipping lines, offers, agreed services and reputation |
| `scripts/sim/finance.gd` | Loans and the bailout |
| `scripts/sim/vehicle.gd` | A tractor or lorry: path, state, box, area and slot |
| `scripts/sim/save_file.gd` | Versioned save files |
| `scripts/world_view.gd` | Draws the sim in 3D; reads it, never changes it |
| `scripts/hud.gd` | Toolbar, speed buttons, save/load, money, KPIs and events |
| `scripts/crash_reporter.gd` | On the first error, writes the log, a save and the content hash to `user://reports/` |
| `scripts/guide.gd` | The guided start's steps, each done when the sim's state shows it |
| `scripts/inspect.gd` | What the inspect tool shows for a clicked vehicle, ship, crane or area |
| `scripts/camera_rig.gd` | Pan, rotate, zoom camera |
| `scripts/main.gd` | Wires them together, turns frame time into ticks and clicks into commands |

## Test

See [tests/README.md](tests/README.md) for tests, save fixtures, the benchmark and screenshots.
