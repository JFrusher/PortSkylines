# Game data

Every tunable number lives in `data/base/*.json`: `rules.json` (site, money, timing), `ships.json` (ship classes), `equipment.json` (cranes, tractors, yard gear) and `lines.json` (shipping lines, contracts, reputation) and `maps.json` (coastlines). A key may live in any one file. `scripts/sim/content.gd` loads every `.json` file in that folder and checks it against `Content.SCHEMA`. A missing, unknown, mistyped or duplicated key stops the game with an error that names the file and key.

Whole numbers are allowed where a key is a number; keys marked *int* must be whole. Keys marked *>0* must be greater than zero.

| Key | Type | Meaning |
|---|---|---|
| `site.width`, `site.height` | int | Site size in metres for roads and areas, a multiple of the 4 m grid cell |
| `map` | text | The map a new game is played on, a key of `maps` |
| `maps.<key>.name` | text | The map's name |
| `maps.<key>.land` | list | The mainland's outline: a polygon of `[x, y]` points in metres on the site; a cell is land when its centre is inside. Land tiles must divide the site exactly, and the highway's entry (middle of the east edge) must be land |
| `maps.<key>.islands` | list | Islands, each a polygon like `land` |
| `maps.<key>.rivers` | list | Rivers carved through the land: each `{"points": [[x, y], ...], "width": metres, "depth": metres}` |
| `maps.<key>.depth.shore`, `.per_metre`, `.max` | number | The sea's depth: `shore` metres beside land, `per_metre` more for each metre further out, at most `max` |
| `reclaim.cost_per_cell` | int | Filling one 4 m cell of water behind a quay wall |
| `lines.<key>.tranship_share`, `.connection_hours` | number, number | The share of the boxes a line's big ships land that go on with its next feeder within the window, and of its feeders' boxes that go on with its next big ship |
| `transhipment.price_factor`, `.missed_fine`, `.missed_reputation` | number, int, number | A transhipment move pays the move price times this; a box not loaded within its connection window costs the fine and this much of its line's reputation (times the line's sensitivity), and waits a further window for the next ship |
| `transfers.share`, `.cost_per_box` | number, int | Of the imports a line lands at one terminal while it has a service at another, the share that leave on its ship there; each is driven between the terminals at this cost, an internal move |
| `road_types.<key>.name` | text | The road's name in the build menu |
| `junctions.min_angle`, `.corner_cells` | number, number | Roads meeting at a node must part by at least this many degrees; each is cut back from the node far enough to clear its neighbours' edges, plus this corner radius in cells |
| `road_types.<key>.forward`, `.backward` | int | Lanes along and against the drawn direction; forward at least backward, and at least one lane |
| `road_types.<key>.lorries` | true/false | Whether lorries may use it; tractors and AGVs always may |
| `road_types.<key>.speed_kmh` | number | The road's speed limit; a vehicle drives at the lower of this and its own top speed (the highway is 80) |
| `traffic.standstill_gap_m`, `.headway_seconds` | number, number | How far back a vehicle keeps from the one ahead: this gap standing, plus this many seconds of travel at its speed |
| `traffic.accel`, `.decel`, `.lateral_accel` | number, number, number | How fast vehicles speed up and brake (m/s²), and the sideways acceleration a curve may ask of them, which sets how fast they take it |
| `traffic.lorry_m`, `.tractor_m` | number, number | How long a lorry and a tractor with its chassis are |
| `road_types.<key>.cost_per_cell`, `.upkeep_per_cell` | int, number | Build cost and daily upkeep per 4 m cell of road length; upkeep may be a fraction of a dollar |
| `area_types.<key>.name` | text | The area's name in the build menu |
| `area_types.<key>.depth` | int | How many 4 m cells the area reaches back from its road edge |
| `area_types.<key>.min_length` | int | The shortest area, in cells along the road |
| `area_types.<key>.cost_per_cell`, `.upkeep_per_cell` | int, number | Build cost and daily upkeep per cell of area; upkeep may be a fraction of a dollar |
| `berths.<key>.name` | text | The berth's name in the Quay menu; its key also locks it by milestone |
| `berths.<key>.length` | int | The berth's quay apron length in 4 m cells; it reaches from the water to its own road |
| `berths.<key>.crane_spots` | int | How many STS crane spots sit evenly along it; cranes stand only there |
| `berths.<key>` of an inland class | | A berth keyed by an inland ship class (`barge`) takes only that class, and ships of it berth nowhere else |
| `yard_gear.<key>.speed` | float | A yard machine's travel speed on an area, in m/s |
| `yard_gear.<key>.lift_seconds`, `.set_down_seconds` | float | Seconds to lift a box and to set one down |
| `yard_gear.<key>.bays_per_machine` | int | One machine per so many 12 m bays of an area |
| `yard_gear.<key>.tiers` | int | How many boxes high the gear stacks on an area |
| `yard_gear.<key>.carries` | true/false | Whether the gear carries its own boxes to and from the quay (straddle carriers): such a block sends one of its own machines, one per `bays_per_machine`, in place of a tractor from the pool |
| `sts_cranes.<key>.width` | int | A crane's width along a quay apron, in metres; a new crane can't stand closer than its width |
| `start_money` | int | Money at the start of a new game |
| `move_price.per_20ft` | int >0 | What a line pays per crane move of a 20 ft box |
| `move_price.forty_factor` | number >0 | A 40 ft box's move price as a multiple of a 20 ft one |
| `move_price.reefer_premium` | int | Added to a reefer's move price |
| `box_mix.forty_share`, `.reefer_share`, `.rush_share`, `.dg_share` | number | Shares of 40 ft boxes, reefers, rush imports and dangerous goods among new boxes |
| `reefers.plug_minutes`, `.fine` | number, int | Minutes a reefer may stand off a plug (outside a reefer block) before the port is fined, once |
| `reefers.kw`, `.hot_kw`, `.hot_from`, `.hot_to` | number, int | kW a plugged reefer draws, and on the hot days of the year (day numbers, inclusive) |
| `reefers.price_per_kwh`, `.peak_charge_per_kw` | number | The midnight power bill: per kWh drawn, plus per kW of the day's peak |
| `special_boxes.rush_fine` | int | Paid per rush import discharged after its ship's window closed |
| `special_boxes.dg_distance` | int | Cells a dangerous-goods block keeps clear of every other yard block |
| `storage.free_days`, `.fee` | int | Starting storage terms: free days (0–3), then the fee per box per day |
| `storage.max_fee` | int | Highest storage fee the player may set |
| `storage.dwell_per_dollar`, `.min_dwell_factor` | number | Import dwell is `import_dwell_minutes / (1 + fee × dwell_per_dollar)`, but not below `min_dwell_factor` of it |
| `storage.fair_fee`, `.satisfaction_per_dollar` | number | Each $ of fee above the fair fee changes the line's reputation by this much per call |
| `gate_minutes` | number | Calendar minutes a lorry stops at a gate |
| `upkeep.sts_crane`, `.tractor` | int | Paid per crane and per tractor at midnight |
| `water.ship_speed` | number >0 | Metres a calendar minute ships sail along their lanes |
| `water.lanes.<key>.name` | text | The lane's name in the Water menu |
| `water.lanes.<key>.half_width` | int >0 | Cells of water either side of a lane's line |
| `water.lanes.<key>.two_way`, `.barges_only` | true/false, true/false | Whether ships pass both ways (else one at a time); whether only inland ships may sail it, as a river channel |
| `water.lanes.<key>.cost_per_cell`, `.upkeep_per_cell` | int, number | Price and daily upkeep per 4 m cell of water a lane covers |
| `water.pocket` | int >0 | Cells out from a quay that a ship lies in (its berth's pocket); a lane ending in it reaches the berth |
| `water.anchorage.cost_per_cell`, `.spacing` | int, int >0 | Price per cell of an anchorage, and the cells between ships at anchor each way |
| `water.max_wait_hours` | number >0 | How long a ship with no berth and no room at anchor waits out at sea before going elsewhere |
| `water.pilots.station_cost`, `.pilot_cost`, `.upkeep_per_pilot` | int | A pilot station, each pilot hired, and each pilot's daily upkeep |
| `water.pilots.boat_speed` | number >0 | Metres a minute the pilot boat sails from its station to a ship |
| `water.tugs.depot_cost`, `.tug_cost`, `.upkeep_per_tug` | int | A tug depot, each tug, and each tug's daily upkeep |
| `water.tugs.speed` | number >0 | Metres a minute tugs sail from their depot to a berth |
| `water.breakwater.cost_per_cell`, `.upkeep_per_cell` | int, number | A breakwater's price and daily upkeep per cell; it is two cells thick and no lane crosses it |
| `water.slot_margin_minutes` | number | The gap kept between two ships' bookings of a narrow lane |
| `ship_classes.<name>.light_draft`, `.light_share` | number, number | Where no berth has water for its full draft but one has its light draft, the class calls light-loaded with this share of its moves (`light_draft` equal to `draft` means never) |
| `ship_classes.<name>.pilot`, `.tugs` | true/false, int | Whether the class takes a pilot in and out, and how many tugs it waits for to berth and unberth |
| `ship_classes.<name>.port_dues` | int | What each call pays the port as its authority, in the ledger's Port dues |
| `ship_classes.<name>.inland` | true/false | An inland class (barges) comes and goes only by ship lanes ending where a river leaves the site, the first point of each of the map's `rivers`; every other class only by lanes ending in the open sea |
| `water.pilots.fee` | int | What each piloted passage pays, in the ledger's Pilotage |
| `water.dredge.max_depth` | number | As deep as dredging takes a lane or a pocket, in metres |
| `water.dredge.cost_per_cell_metre` | int | Dredging one cell of water one metre deeper |
| `water.dredge.maintenance_per_cell_metre`, `.maintenance_days` | int, int >0 | Every `maintenance_days` days, each dredged cell and metre costs this |
| `lorry_interval_minutes` | number >0 | Calendar minutes between import lorries |
| `export_lorry_interval_minutes` | number >0 | Calendar minutes between export lorries |
| `import_dwell_minutes` | number | Calendar minutes an import box waits in the yard before a lorry may collect it, at a $0 storage fee |
| `lorry_speed` | number >0 | Metres per vehicle second (one game minute) |
| `give_up_seconds` | number >0 | Vehicle seconds stuck before a tractor replans; lorries wait twice as long |
| `ship_classes.<name>.length` | int >0 | Metres of quay apron the ship needs |
| `ship_classes.<name>.draft` | number | Metres; a ship sails only through lanes and into berth pockets at least this deep |
| `ship_classes.<name>.outreach` | int | Crane outreach (rows) the ship needs |
| `ship_classes.<name>.import_moves`, `.export_moves` | int | Boxes off and on per call |
| `ship_classes.<name>.window_hours` | number >0 | Length of a service's weekly berth window; sailing after it is late |
| `land.metres` | int >0 | The site is split into square land tiles this many metres across; roads and areas are built only on land the port owns |
| `land.price`, `.upkeep` | int | Price of a land tile, and its upkeep a day once owned |
| `land.start.x`, `.y`, `.width`, `.height` | int | The block of land tiles the port owns at the start |
| `sts_cranes.<key>.name`, `.cost` | text, int | A quay crane kind's name and price; its key also locks it by milestone |
| `sts_cranes.<key>.rate` | number >0 | Moves per hour |
| `sts_cranes.<key>.outreach` | int | Rows the crane reaches; lines offer a class only where a crane on a long enough berth reaches across it |
| `sts_cranes.<key>.lead_days`, `.max_fetchers` | number, int | Days from ordering a crane to it standing on the quay; tractors fetching exports for it at once |
| `crane_interference` | number >0 | Rate multiplier for cranes working side by side |
| `tractor.cost` | int | Price of one tractor |
| `tractor.speed` | number >0 | Metres per vehicle second (one game minute) |
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
| `barge.discount.max`, `.share_per_dollar`, `.max_share` | int, number, number | The port-wide barge discount: up to `max` dollars off each box carried by barge, each dollar booking `share_per_dollar` more of every line's imports for places up the river onto barges, taken from road and rail alike, up to `max_share` |
| `hinterland.places.<key>.share`, `.road_km`, `.rail_km`, `.barge_km` | number, number, number, number | Each off-map place's share of boxes, and its distance by road, rail and barge up the river; 0 means no rail or barge link |
| `lines.<key>.barge_share` | number 0–1 | Of the line's imports for a place up the river (`hinterland.places.<key>.barge_km` above 0), the share booked to leave by barge while a barge service calls at that terminal; such a box never leaves by lorry |
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
| `milestones.<key>.reputation`, `.on_time`, `.productivity` | number | What the milestone also needs: the lines' average reputation, the share of the last calls sailed on time, and their average berth moves an hour. A milestone reached stays reached |
| `objectives.<key>.text`, `.after` | text, int | A goal shown once `after` milestones are reached |
| `objectives.<key>.kind`, `.class`, `.count` | text, text, int | `on_time_calls` (`count` calls of `class` on time), `day_moves` (`count` moves in a day) or `working_terminals` |
| `objectives.<key>.cash`, `.reputation` | int, number | Paid once when the objective is met: cash, and reputation with every line |
| `milestones.<key>.unlocks.<name>` | text | Content the milestone unlocks, with the words the player sees: a ship class, a yard gear, `loans`, `land`, `dredging`, `ledger` or `contracts`. Names in no milestone are never locked |
| `year_days` | int >0 | Days in a game year, for the year-end scoreboard |

**Time units.** At 1×, one vehicle second is one real second, and one calendar minute is one real second (one game hour per real minute). See `SimClock`.
