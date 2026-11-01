# Progression: from a regional pier to a mega port

A port grows through five milestones. Each one needs TEU moved across the quay, and the later ones also need the lines to rate the port well, ships to sail on time and berths to work fast. Once a milestone is reached it stays reached. Between milestones, objectives give the player a nearer goal, each paying cash and reputation once. The numbers below are from `data/base/rules.json`; `tests/test_progression.gd` checks that every unlock in the data is named here.

## The milestones

| Milestone | Needs | Unlocks |
|---|---|---|
| 1. Harbour | Nothing: the start | `contracts` with shipping lines, `feeder` services, `reach_stacker` yard gear, the `ledger` |
| 2. Terminal | 2,000 TEU; reputation 40 | `loans`, `rtg` cranes, `ocr` gate portals, `reefers`, `empties` coming back, `barge` services up the river with `barge_crane`s at their berths |
| 3. Gateway | 6,000 TEU; reputation 45; 60% of calls on time | buying `land`, `dredging`, `panamax` services, `automated` gates, `rmg` rail yards, `transhipment` |
| 4. Hub | 15,000 TEU; reputation 50; 70% on time; 30 berth moves an hour | `neopanamax` services and berths, `wide_sts` cranes |
| 5. Mega port | 40,000 TEU; reputation 55; 75% on time; 45 berth moves an hour | `ulcv` services and berths, `mega_sts` cranes |

Reputation is the lines' average. "On time" and "berth moves an hour" look back over the last 20 calls in the ship log. The Port panel lists what the next milestone still needs.

## The life cycle

1. **A regional pier.** One feeder berth on the coast, a road to the highway, a gate, a yard block of reach stackers, two cranes and a ship lane in from the open sea. Feeders draw 10 m, so the estuary's natural water takes them without dredging, and they need no pilot or tugs. The first objective is to work three feeders on time.
2. **A terminal.** RTGs stack higher, loans pay for growth, OCR gates speed lorries through, reefers earn a premium if they are plugged in, and empties start coming back to an empty depot. The objective is a 500-move day.
3. **A gateway.** Panamaxes draw 13 m, so the lanes and berths they use must be dredged, and they take a pilot and two tugs: the player builds a pilot station and a tug depot on the water. Land can be bought to grow inland, and RMG rail yards take boxes by train. A second terminal, painted on the map, earns an objective; once a line calls at both terminals, some of its boxes move between them by road.
4. **A hub.** Neopanamaxes (15.5 m, 22 rows across) need a 400 m berth and the wide STS crane. Narrow channels now hold ships up: widening them, adding anchorages, more pilots and nearer tug depots keep the queue short.
5. **A mega port.** ULCVs (16 m, 24 rows) need the mega STS. Where the water is too shallow for their full draft they call light-loaded, with 60% of the boxes, so dredging to 16 m pays twice.

## The late-game loop

Past the hub, the port grows by doing the same things better rather than by unlocking more:

- **Bigger ships.** Lines that sail Neopanamaxes and ULCVs offer more calls as each milestone raises hinterland demand, so berth length, crane reach and water depth decide which offers the port can take.
- **Denser yards.** RTGs and RMGs stack higher; the yard fills before the quay does, so blocks, gear and dwell (storage fees) become the limit.
- **Faster turns.** The on-time and productivity gates reward short anchorage queues, fast berthing (tugs close by) and enough cranes per ship.
- **Automation (M11).** Automated blocks and AGVs cost more at first and pay back in steady state.

## Objectives

| After milestone | Objective | Reward |
|---|---|---|
| 1 | Work three feeders inside their windows | $50,000 and +5 reputation |
| 2 | Move 500 boxes across the quay in one day | $80,000 and +5 |
| 3 | Work three Panamaxes inside their windows | $150,000 and +5 |
| 3 | Run two working terminals | $120,000 and +5 |
| 4 | Work three Neopanamaxes inside their windows | $300,000 and +5 |
| 5 | Work two ULCVs inside their windows | $600,000 and +5 |
