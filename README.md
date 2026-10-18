# Port Skylines

A port-building game in the spirit of city builders. Lay roads from the
highway, build quays on the coast and container yards inland; ships call at
connected quays, cranes stack their boxes in the nearest reachable yard, and
lorries from the highway collect each box and pay for it.

Built with [Godot 4.4](https://godotengine.org/download) (standard build, GDScript).

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
| `scripts/sim/port_map.gd` | Tile grid, build rules, road routing. No money, no rendering |
| `scripts/sim/port_sim.gd` | Money, ships, cranes, yards, lorries. Steps in plain seconds |
| `scripts/world_view.gd` | Draws the sim in 3D; reads it, never changes it |
| `scripts/hud.gd` | Toolbar, speed buttons, money and status |
| `scripts/camera_rig.gd` | Pan, rotate, zoom camera |
| `scripts/main.gd` | Wires them together and turns clicks into orders |

## Test

```bash
godot --headless --import
godot --headless --script res://tests/test_sim.gd
```
