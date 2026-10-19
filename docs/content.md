# Game data

Every tunable number lives in `data/base/*.json`. `scripts/sim/content.gd` loads every `.json` file in that folder and checks it against `Content.SCHEMA`. A missing, unknown, mistyped or duplicated key stops the game with an error that names the file and key.

Whole numbers are allowed where a key is a number; keys marked *int* must be whole.

| Key | Type | Meaning |
|---|---|---|
| `map.width`, `map.height` | int | Map size in tiles |
| `map.sea_width` | int | Tiles of sea along the west edge |
| `start_money` | int | Money at the start of a new game |
| `fee_per_box` | int | Paid when a lorry leaves the map with a box |
| `build_cost.road`, `.quay`, `.yard` | int | Cost per tile |
| `first_ship_minutes` | number | Calendar minutes before the first ship is called |
| `ship_interval_minutes` | number | Calendar minutes between ships |
| `ship_boxes` | int | Boxes each ship brings |
| `sail_seconds` | number | Vehicle seconds to sail in or out |
| `crane_minutes` | number | Calendar minutes per box moved from ship to yard |
| `yard_capacity` | int | Boxes per yard tile |
| `lorry_interval_minutes` | number | Calendar minutes between lorry dispatches |
| `lorry_speed` | number | Tiles per vehicle second |

**Time units.** At 1×, one vehicle second is one real second, and one calendar minute is one real second (one game hour per real minute). See `SimClock`.
