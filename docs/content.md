# Game data

Every tunable number lives in `data/base/*.json`: `rules.json` (map, money, timing), `ships.json` (ship classes) and `equipment.json` (cranes, tractors, yard gear). A key may live in any one file. `scripts/sim/content.gd` loads every `.json` file in that folder and checks it against `Content.SCHEMA`. A missing, unknown, mistyped or duplicated key stops the game with an error that names the file and key.

Whole numbers are allowed where a key is a number; keys marked *int* must be whole. Keys marked *>0* must be greater than zero.

| Key | Type | Meaning |
|---|---|---|
| `map.width`, `map.height` | int | Map size in tiles |
| `map.sea_width` | int | Tiles of sea along the west edge |
| `start_money` | int | Money at the start of a new game |
| `fee_per_box` | int | Paid for each box through the gate, in or out |
| `build_cost.road`, `.quay`, `.yard`, `.gate` | int | Cost per tile |
| `gate_minutes` | number | Calendar minutes a lorry stops at a gate |
| `upkeep.road`, `.quay`, `.yard`, `.gate` | int | Paid per tile at midnight |
| `upkeep.sts_crane`, `.tractor` | int | Paid per crane and per tractor at midnight |
| `first_ship_minutes` | number | Calendar minutes before the first ship is called |
| `ship_interval_minutes` | number >0 | Calendar minutes between ships |
| `sail_seconds` | number >0 | Vehicle seconds to sail in or out |
| `lorry_interval_minutes` | number >0 | Calendar minutes between import lorries |
| `export_lorry_interval_minutes` | number >0 | Calendar minutes between export lorries |
| `import_dwell_minutes` | number | Calendar minutes an import box waits in the yard before a lorry may collect it |
| `lorry_speed` | number >0 | Tiles per vehicle second |
| `give_up_seconds` | number >0 | Vehicle seconds stuck before a tractor replans; lorries wait twice as long |
| `ship_classes.<name>.length` | int >0 | Quay tiles the ship needs |
| `ship_classes.<name>.draft` | number | Metres; a class deeper than `water_depth` never berths |
| `ship_classes.<name>.outreach` | int | Crane outreach (rows) the ship needs |
| `ship_classes.<name>.import_moves`, `.export_moves` | int | Boxes off and on per call |
| `ship_classes.<name>.weight` | number | Relative chance this class is called |
| `water_depth` | number | Metres of water at every quay |
| `sts_crane.cost` | int | Price of a quay crane |
| `sts_crane.rate` | number >0 | Moves per hour |
| `sts_crane.outreach` | int | Rows the crane reaches |
| `crane_interference` | number >0 | Rate multiplier for cranes working side by side |
| `tractor.cost` | int | Price of one tractor |
| `tractor.speed` | number >0 | Tiles per vehicle second |
| `yard_gear.<name>.capacity` | int >0 | Boxes per yard tile |
| `yard_gear.<name>.handling_minutes` | number >0 | Calendar minutes per box handled |
| `yard_gear.<name>.tiles_per_machine` | int >0 | One machine per this many tiles in a block |
| `yard_gear.<name>.cost_per_tile` | int | Paid per tile when a block switches to this gear |
| `yard_gear.<name>.upkeep_per_machine` | int | Paid per machine at midnight |

**Time units.** At 1×, one vehicle second is one real second, and one calendar minute is one real second (one game hour per real minute). See `SimClock`.
