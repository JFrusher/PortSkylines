# Game data

Every tunable number lives in `data/base/*.json`: `rules.json` (map, money, timing), `ships.json` (ship classes), `equipment.json` (cranes, tractors, yard gear) and `lines.json` (shipping lines, contracts, reputation). A key may live in any one file. `scripts/sim/content.gd` loads every `.json` file in that folder and checks it against `Content.SCHEMA`. A missing, unknown, mistyped or duplicated key stops the game with an error that names the file and key.

Whole numbers are allowed where a key is a number; keys marked *int* must be whole. Keys marked *>0* must be greater than zero.

| Key | Type | Meaning |
|---|---|---|
| `map.width`, `map.height` | int | Map size in tiles |
| `map.sea_width` | int | Tiles of sea along the west edge |
| `site.width`, `site.height` | int | Site size in metres for roads and areas, a multiple of the 4 m grid cell |
| `site.sea_width` | int | Metres of sea along the west edge, a multiple of 4 |
| `start_money` | int | Money at the start of a new game |
| `move_price.per_20ft` | int >0 | What a line pays per crane move of a 20 ft box |
| `move_price.forty_factor` | number >0 | A 40 ft box's move price as a multiple of a 20 ft one |
| `move_price.reefer_premium` | int | Added to a reefer's move price |
| `box_mix.forty_share`, `.reefer_share` | number | Shares of 40 ft boxes and of reefers among new boxes |
| `storage.free_days`, `.fee` | int | Starting storage terms: free days (0–3), then the fee per box per day |
| `storage.max_fee` | int | Highest storage fee the player may set |
| `storage.dwell_per_dollar`, `.min_dwell_factor` | number | Import dwell is `import_dwell_minutes / (1 + fee × dwell_per_dollar)`, but not below `min_dwell_factor` of it |
| `storage.fair_fee`, `.satisfaction_per_dollar` | number | Each $ of fee above the fair fee changes the line's reputation by this much per call |
| `build_cost.road`, `.quay`, `.yard`, `.gate` | int | Cost per tile |
| `gate_minutes` | number | Calendar minutes a lorry stops at a gate |
| `upkeep.road`, `.quay`, `.yard`, `.gate` | int | Paid per tile at midnight |
| `upkeep.sts_crane`, `.tractor` | int | Paid per crane and per tractor at midnight |
| `sail_seconds` | number >0 | Vehicle seconds to sail in or out |
| `lorry_interval_minutes` | number >0 | Calendar minutes between import lorries |
| `export_lorry_interval_minutes` | number >0 | Calendar minutes between export lorries |
| `import_dwell_minutes` | number | Calendar minutes an import box waits in the yard before a lorry may collect it, at a $0 storage fee |
| `lorry_speed` | number >0 | Tiles per vehicle second |
| `give_up_seconds` | number >0 | Vehicle seconds stuck before a tractor replans; lorries wait twice as long |
| `ship_classes.<name>.length` | int >0 | Quay tiles the ship needs |
| `ship_classes.<name>.draft` | number | Metres; a class deeper than the channel never berths |
| `ship_classes.<name>.outreach` | int | Crane outreach (rows) the ship needs |
| `ship_classes.<name>.import_moves`, `.export_moves` | int | Boxes off and on per call |
| `ship_classes.<name>.window_hours` | number >0 | Length of a service's weekly berth window; sailing after it is late |
| `channel.start_depth`, `.max_depth` | number | The channel's depth at the start, and as deep as dredging can take it (metres) |
| `channel.cost_per_metre` | int | Cost of dredging one metre |
| `channel.maintenance_per_metre`, `.maintenance_days` | int, int >0 | Every `maintenance_days` days, each dredged metre costs this |
| `land.cells` | int >0 | Land tiles are squares of this many cells |
| `land.price`, `.upkeep` | int | Price of a land tile, and its upkeep a day once owned |
| `land.start.x`, `.y`, `.width`, `.height` | int | The block of land tiles the port owns at the start |
| `sts_crane.cost` | int | Price of a quay crane |
| `sts_crane.rate` | number >0 | Moves per hour |
| `sts_crane.outreach` | int | Rows the crane reaches |
| `sts_crane.lead_days` | number | Days from ordering a crane to it standing on the quay |
| `crane_interference` | number >0 | Rate multiplier for cranes working side by side |
| `tractor.cost` | int | Price of one tractor |
| `tractor.speed` | number >0 | Tiles per vehicle second |
| `yard_gear.<name>.capacity` | int >0 | Boxes per yard tile |
| `yard_gear.<name>.handling_minutes` | number >0 | Calendar minutes per box handled |
| `yard_gear.<name>.tiles_per_machine` | int >0 | One machine per this many tiles in a block |
| `yard_gear.<name>.cost_per_tile` | int | Paid per tile when a block switches to this gear |
| `yard_gear.<name>.upkeep_per_machine` | int | Paid per machine at midnight |
| `ledger_categories.<key>` | text | A ledger category and the label the ledger panel shows |
| `loans.<kind>.amount`, `.yearly_rate`, `.days` | int >0, number, int >0 | A loan: paid in at once, paid back with interest at the yearly rate in equal daily payments over its term |
| `max_loans` | int | Loans open at once |
| `bailout.days` | int | Midnights in a row below zero before a bailout clears the debt |
| `bailout.reputation` | number | Change in every line's reputation at a bailout |
| `bailout.no_loans_days` | int | Days after a bailout with no new loans |
| `lines.<key>.name`, `.livery` | text | A fictional shipping line and its hull colour (`#rrggbb`). Base lines use the Okabe-Ito colour-blind-safe palette |
| `lines.<key>.classes.<class>` | number | Relative weight of each ship class the line offers; classes must exist |
| `lines.<key>.sensitivity` | number >0 | Multiplies every change in this line's reputation |
| `contracts.offer_check_minutes` | number >0 | How often lines consider offering a service |
| `contracts.offer_chance` | number | Chance of an offer at each check |
| `contracts.max_offers` | int | Offers open at once |
| `contracts.offer_days` | number | Days an offer stays open |
| `contracts.max_services_per_berth` | int | Services plus offers per berth with a road, at most |
| `reputation.start` | number | Every line's reputation (0–100) at the start |
| `reputation.offer_above` | number | A line offers services only at or above this |
| `reputation.cancel_below` | number | Below this a line cancels a service after each call |
| `reputation.on_time` | number | Change for a call that sails within its window |
| `reputation.late_per_hour` | number | Change per hour a call sails after its window |
| `reputation.moves_per_hour_target`, `.per_move_per_hour` | number | Change per berth move per hour above (or below) the target |
| `reputation.turn_target_minutes`, `.per_turn_minute` | number | Change per minute of gate turn time above (or below) the target |
| `reputation.missed` | number | Change when a call finds no berth that could ever take it |
| `milestones.<key>.teu` | int | TEU moved across the quay (all time) that reaches this milestone |
| `milestones.<key>.unlocks.<name>` | text | Content the milestone unlocks, with the words the player sees: a ship class, a yard gear, `loans`, `land`, `dredging`, `ledger` or `contracts`. Names in no milestone are never locked |
| `year_days` | int >0 | Days in a game year, for the year-end scoreboard |

**Time units.** At 1×, one vehicle second is one real second, and one calendar minute is one real second (one game hour per real minute). See `SimClock`.
