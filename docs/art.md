# Art bible

The game's look, for anyone modelling or texturing for it. The roadmap chose a
semi-realistic industrial style (decision 8): real equipment shapes and
proportions, real colours, light weathering, and no cartoon exaggeration.
The UI follows `docs/ui-style.md`.

## References

Use only your own photos or openly licensed ones, and record the source and
licence beside any image added to `art/`. Three reference ports, chosen for
modern equipment and clear aerial views:

| Port | What to study | Photos |
|---|---|---|
| Rotterdam, Maasvlakte II | Automated quay layout, concrete and markings, long straight quays | [Wikimedia Commons](https://commons.wikimedia.org/wiki/Category:Maasvlakte_2) |
| Felixstowe | Mixed RTG yards, lorry gates, British road markings | [Wikimedia Commons](https://commons.wikimedia.org/wiki/Category:Port_of_Felixstowe) |
| Hamburg, Altenwerder | Crane proportions, block spacing, the water's colour in a river port | [Wikimedia Commons](https://commons.wikimedia.org/wiki/Category:Container_Terminal_Altenwerder) |

Equipment: [container cranes](https://commons.wikimedia.org/wiki/Category:Container_cranes), [gantry cranes](https://commons.wikimedia.org/wiki/Category:Gantry_cranes), [reach stackers](https://commons.wikimedia.org/wiki/Category:Reach_stackers), [terminal tractors](https://commons.wikimedia.org/wiki/Category:Terminal_tractors) and [straddle carriers](https://commons.wikimedia.org/wiki/Category:Straddle_carriers).

**Check:** each new model is compared side by side with at least one photo
from these ports before it is merged.

## Scale

One tile is **25 m**, and one Godot unit is one tile. Model at real size in
metres in Blender and scale by 1/25 on export, so a model reads true against
the grid.

| Thing | Real size | In tiles |
|---|---|---|
| 40 ft box | 12.2 × 2.4 × 2.6 m | 0.49 × 0.10 × 0.10 |
| 20 ft box | 6.1 × 2.4 × 2.6 m | 0.24 × 0.10 × 0.10 |
| STS crane | boom about 50 m up, reaching about 65 m out over the water | 2.0 high, 2.6 out |
| RTG | about 23 m wide, 20 m high | 0.9 × 0.8 |
| Terminal tractor and chassis | about 16 m | 0.64 |

**Today's placeholders are stretched for readability**: boxes are about three
times real width and height, so a stack reads from the default camera. The
modelled set should keep true lengths and decide the stretch once, here,
after a playtest at the default zoom.

## Palette

| Use | Colour |
|---|---|
| Quay and yard concrete | `#9e998c`, `#73736e` |
| Asphalt | `#333338` |
| Markings | white `#ebebd9`, safety yellow `#f2bf1a` |
| Fenders and bollards | `#1f1f21`, `#262629` |
| STS cranes | red `#d94d33` |
| RTGs | white `#f2f2eb` with yellow beams `#f2bf1a` |
| Reach stackers | orange `#d95926` |
| Tractor cabs, lorry cabs | yellow `#f2bf1a`, off-white `#e6e6db` |
| Sea | `#408799` shallow to `#0f304f` deep |
| Countryside | `#5c6b4d` |

Line liveries come from `data/base/lines.json` and use the Okabe-Ito
colour-blind-safe palette. Boxes are modelled white and tinted per instance
by their line's livery, so a box model must not bake its colour into the
texture; put wear in a separate greyscale mask.

## Wear

Light to moderate: equipment is in service, not new and not derelict.
Rust streaks from box corner castings and door hinges, faded paint on box
roofs, tyre marks and oil stains in yard lanes and under cranes, and a
darker water line on hulls. No dents or damage on the hero set.

## Lighting

One sun, warm and fairly high (today: 50° elevation, 30° yaw) with a sky
that lights the shade, so stacks cast readable shadows on the yard. Target
times of day for screenshots and the later day-night cycle: 08:00 (low,
warm, long shadows), 13:00 (neutral, short shadows) and 19:00 (golden, from
the west over the water). Night lighting (floodlights on masts and cranes)
waits for the day-night cycle.

## Polygon budgets

Triangles at LOD 0. Godot generates the lower LODs on import (see
`art/README.md`); keep LOD 0 within budget so the 60 fps target in
`docs/perf.md` holds with thousands of boxes.

| Asset | Budget | Today |
|---|---:|---:|
| 40 ft box | 1,200 | 1,020 |
| 20 ft box | 700 | 552 |
| STS crane | 8,000 | boxes |
| RTG | 4,000 | boxes |
| Reach stacker | 3,000 | boxes |
| Terminal tractor, lorry | 2,500 | boxes |
| Ship hull, feeder / Panamax | 6,000 / 10,000 | prism |
| Gate | 1,500 | box |
| Quay, yard and road tiles | 200 | boxes and prisms |

Boxes are drawn as MultiMesh instances, so their budget matters most: 20,000
boxes at 1,020 triangles is 20 million triangles before LODs.
