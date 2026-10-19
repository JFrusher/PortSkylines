# M5 — Roads and areas

**Goal.** Stop building the port square by square. The player draws roads on a 4 m grid, then drags areas (quay apron, yard block, gate) along them, and each area lays itself out. Vehicles end their trips at handover slots, machines work jobs in fixed phases, and the main motions are animated.

**Depends on.** M4. M6 (scale and rail) resumes on this model; its steps 1, 2, 4 and 6 carry over, and step 7 is redone here as part of the lane graph.

**Exit criteria:**
- One full chain plays: draw roads, then drag a quay apron, one RTG yard block and a gate. A box goes STS → tractor → RTG lane → stack → lorry → gate, with main-motion animations.
- The follow camera tracks a box from ship to gate.
- The replay hash test passes on the new model at 1, 3 and 6 ticks per frame.
- Tile-format saves are refused with a clear message; the new format has a fixture.

## Steps

The new model is built beside the tile model, in its own sim classes with headless tests, so every step leaves the tile game playable. Step 19 moves the box flow onto it, and steps 22 and 23 remove the tile model.

### Grid and roads
1. **4 m sim grid.** Map sizes in the data become 4 m cells, and every world position comes from the cell. Test: map sizes round-trip between metres and cells.
2. **Road segments.** Roads are nodes and segments snapped to 0°, 45° and 90°, and each segment is turned into the cells along it. Corners are arcs in the view (step 8), not extra cells. Test: a 45° segment becomes a connected diagonal run, and other angles are refused.
3. **Road types from data.** Terminal road 1+1, terminal road 2+2, one-way road, and an AGV/tractor-only lane, with lanes and allowed vehicles per type. Test: content validation; a one-way road gives lanes in one direction only.
4. **Automatic junctions.** A segment splits where roads meet or cross. Test: a crossing makes a 4-way node, and a T join makes a 3-way node.
5. **Directed lane graph and router.** Replaces `PortMap`'s `AStarGrid2D`, which can't do one-way or 45° links. Test: one-way roads can't be driven backwards, the AGV lane refuses lorries, dead ends allow a U-turn, and a route across a road grid is the hand-counted shortest.
6. **Cell reservation re-keyed** for diagonal steps and junction nodes (`Traffic.lane` keys on the four sides today). Test: M2's traffic cases (head-on, queue, a full ring waiting, never stopping in a junction), ported, plus a 45° merge. The give-up valve that clears a ring comes over with the box flow in step 19.
7. **Draw-road tool and road commands.** A snapped preview with its cost, and bulldozing a segment. Test: a replay with road commands gives the same hash at 1, 3 and 6 ticks per frame.
8. **Road rendering on the 4 m grid.** Straights, 45° joins, arcs and markings for each road type. Check: screenshots of each join.

### Areas
9. **Area model.** An area has a type, cells, the road edge it is attached to, and a terminal. Test: an area off a road edge, or overlapping a road or another area, is refused.
10. **Drag-along-road tool**, CS2 zoning style: the depth is set by the type, the length is dragged, and the area takes the road's direction, 45° roads included. Check: screenshots. Test: snapping to the edge.
11. **RTG yard block layout.** Rows parallel to the road, a truck lane beside them, handover slots (one 40 ft or two 20 ft each) and a buffer strip. Test: a given length gives the expected rows and slots, the same every time.
12. **Quay apron and gate layouts.** Crane rails, tractor lanes under the cranes and a buffer on the apron; lanes and booths at the gate. Test: each layout comes out as expected for a given length.
13. **Area rules.** Role (import, export, empty or reefer), equipment type, and line or berth priority. Test: invalid settings are refused.
14. **Terminals as groups of areas.** A new area joins the terminal it touches; a terminal needs a gate and a quay apron to take contracts. Test: both rules.
15. **An area without a road does no work and shows why.** The inspect tool shows an area's type, terminal, rules and state. Test: a yard block whose road is removed reports the reason; step 19's box flow sends nothing to an area with one.

### Moves
16. **Slot booking.** A vehicle books a handover slot; overflow waits in the buffer strip, then queues on the road. Test: no slot ever holds two vehicles, and a full block shows a road queue.
17. **Machine jobs with phase times from the data** (travel, lift, set down). Each machine belongs to one area. Test: one move takes the data time.
18. **Stacks per area.** Rows, bays and tiers, with no 40 ft box on a 20 ft box. Digging out a buried box costs extra moves, and cranes reshuffle in quiet periods. Test: a buried box costs the expected extra moves.
19. **Box flow on slots and jobs.** Replaces the tile-based `_dispatch_*` and `_drive_*` code. Test: a scripted port works its first ship end to end.

### View and close
20. **Main-motion animations** from the job phases, reusing the M4 art. Check: screenshots of each phase.
21. **Follow camera.** Click a box or machine to follow it. Check: following a box from ship to gate.
22. **New save format.** Tile saves are refused with a clear message, fixtures are rebuilt, and the soak test runs on the new model. Land ownership moves from 25 m tiles onto the grid, and roads and areas need owned land. Test: `test_save` and `test_soak`.
23. **Guided start rewritten** for roads, then areas, with area costs tuned so the start money builds the first chain (a 120 m quay apron costs $45,000 at the step 9 prices, against $20,000 to start). Test: `test_guide`.
24. **First slice playtest: one full chain.** Notes go in `docs/playtests/m5.md`. Tag `m5`.

The depot or parking area and the reach-stacker equipment option follow the first slice.

## Background: the proposal

**Status.** Decided on 19 Oct 2026 and placed as M5; the phases after it moved up by one. Phase numbers below are the ones from before that move: "M5" here is now M6, "M6" is M7, and so on.

**The idea.** Stop building the port square by square. The player draws roads first. Areas (yard, gate, quay apron, rail siding, depot) are then laid out along those roads, and assets are placed inside each area. An asset is a working part of the area, for example the lane where an AGV or tractor waits to be served. Each move then plays as a full animation: the yard crane travels to the handover lane, lowers the spreader, locks the box, lifts it, carries it to its stack slot and sets it down.

**Where it fits.** Between M4 (vertical slice) and M5 (scale and rail) **[Inference]**. Three reasons:
- M5 builds flow fields, packed vehicle arrays and MultiMesh buffers on top of the tile grid. M6 builds a lane graph from road tiles. Both would be rebuilt if roads stop being tiles, so the change is cheapest before them.
- The road network would become the lane graph's source, so M6 step 1 ("lane model derived from tiles") shrinks to "lanes derived from road segments".
- M4 already has the art and the first public build. This change rebuilds the build tools, which is cheaper before more tools (rail, channel, barge) are made in the tile model.

If accepted, it becomes its own phase and M5–M11 renumber, or it merges into M6 (see question G1).

## What to borrow

### From Cities: Skylines Industries **[Inference from play; no sources gathered yet]**
- **Painted areas with a type.** The player paints an industry area with a brush, then places that industry's buildings inside it. The area owns the stats and the level. The buildings do the work.
- **Area levels.** An area levels up from its total output, and each level unlocks more buildings. This could map onto the milestone ladder: a yard area levels from boxes handled.
- **Every building connects to a road.** A building with no road access shows a warning icon and does nothing.
- **Warehouses with a mode.** Fill, empty or balance. This is close to a yard block's import, export or empty role.
- **One panel per area.** Workers, input, output, vehicles in use and upkeep, all on one panel.

### From Cities: Skylines and CS2 roads
- **Roads as nodes and segments**, drawn straight, curved or freehand, with snapping to angles, lengths and existing roads.
- **Zoning along roads.** CS2 zones are cells that attach to a road's edge and follow its direction. An area could attach to a road edge the same way.
- **Lanes come from the road type.** Lane count, one-way and allowed vehicles all come from the road asset, which M6 needs anyway.

### From real container terminals **[Inference from general terminal practice; check against sources before building]**
- **Transfer points (TPs) and handover lanes.** In automated yards, AGVs and lorries never enter the stack. They stop at a marked transfer area at the block end, and the stacking crane comes to them. In RTG yards, tractors stop in a truck lane beside the block. A handover lane is a natural "asset" with a few slots, and vehicles book a slot.
- **Waterside and landside sides of a block.** Many automated blocks are fed by ship traffic at the sea end and by lorries at the land end. Which end an area faces could be a rule the player sets.
- **Work queues.** A terminal operating system gives each crane a queue of jobs (load, discharge, housekeeping, delivery). Equipment pulls the next job. A visible queue per asset would make bottlenecks easy to read.
- **Fixed move phases.** A crane move has the same phases every time: gantry travel, trolley travel, hoist down, lock, hoist up, travel, lower, unlock. Each phase has a time from the data, so the sim stays deterministic and the view only animates it.

## A first sketch of the model

This sketch is only a starting point for the questions below.

| Layer | Is | Owns | Example |
|---|---|---|---|
| Road network | Nodes and segments with a road type | Lanes, junctions, the lane graph | 2+2 terminal road, one-way gate lane |
| Area | A shape attached to one or more road edges, with a type | Stats, level, rules, role, its assets | Yard block (RTG), gate, quay apron |
| Asset | A placed object inside an area, with connection points | Slots, a job queue, a machine | Handover lane (4 slots), RTG, gate booth, reefer rack |
| Job | One box move split into fixed phases | Phase times, the box, the slot it books | "Discharge box 812: STS → TP 3 → RTG → row 4, tier 2" |

Rules this sketch assumes:
1. The sim moves boxes by jobs and phases. The view animates the phase in progress. The sim never waits on an animation.
2. An area with no road connection, or no required asset, does no work and shows why.
3. A vehicle's journey ends at a slot in a handover asset, not at an area or a tile.

## Answers so far (19 Oct 2026)

| # | Question | Answer |
|---|---|---|
| A1 | Grid or free-form roads | Fine-grid snapped: straight runs with 45° and 90° joins and arc corners. The sim keeps a grid underneath, so M2's cell reservation stays |
| B1 | How an area is made | Dragged along a road edge, CS2-zoning style. The area takes the road's direction |
| C1 | Placed or generated assets | Fully automatic: area type and size decide the layout, and the player only sets rules |
| E1 | Animation detail | Main motions only: travel, lift and set down |
| D1 | Where vehicles meet the crane | It depends on the equipment type. In RTG and reach-stacker areas, vehicles drive a lane beside the rows. In automated (ASC) areas, they stop at transfer points at the block end |
| D6 | All handover slots full | The vehicle waits in a buffer strip that the auto layout includes. Overflow beyond the buffer waits on the road and forms a visible queue |
| G1 | Placement | Its own phase after M4. M5–M11 renumber when this proposal gets its steps |
| F1 | Old saves | Tile saves are dropped. Decision 30 ("migrate forever") applies from the first public build in the new format |
| C1+ | Player rules on a yard area | Role (import, export, empty or reefer), equipment type, and lines or berth priority. No stack-height cap |
| D5 | Equipment sharing | A machine belongs to one area only |
| B5 | Area levels | None. Unlocks stay on the port-wide milestone ladder from M3 |
| H1–H2 | Rail, barge and automation | Each is another area type in the same model: rail sidings (M5), the barge terminal (M8) and ASC blocks (M10) |
| A2 | Grid size | 4 m cells, about one lane wide |
| A3 | First road types | Terminal road 1+1, terminal road 2+2, one-way road, and an AGV/tractor-only lane |
| B4 | First area types | Yard block, gate, quay apron, and depot or parking |
| D4 | Rehandles | Simulated. Digging out a buried box costs extra crane moves, and cranes reshuffle boxes in quiet periods |
| D3 | Dual cycling | Not in the first slice. It arrives later as an M10 automation policy |
| E4 | Follow camera | In the first slice: click a box or machine to follow it from ship to gate |
| G2 | Scope | Nothing is cut. The total time to 1.0 grows |
| A4 | Junctions | Formed automatically where roads meet |
| A5 | Height | Flat at 1.0. Bridges and flyovers are likely in 2.0, so nothing should assume a road crosses nothing |
| C3 | Handover slot size | One slot holds one 40 ft box or two 20 ft boxes |
| B6 | Terminals | A terminal is a named group of areas (see below) |
| F2 | Existing art | All M4 art that still applies carries over: containers, STS, RTG, reach stacker, tractor and lorry models, quay fenders, bollards, water, and road markings and arc corners redone for the 4 m grid |
| G3 | First playable slice | One full chain: draw roads, then drag a quay apron, one RTG yard block and a gate. A box goes STS → tractor → RTG lane → stack → lorry → gate, with main-motion animations |

What these change **[Inference]**:
- With a grid under the roads and areas laid out automatically, D7 is answered (the sim stays on a grid), and B2 mostly is (yard areas are strips beside a road, so rows run parallel to it).
- Fully automatic layout means C2–C4 become rules for the layout generator, not things the player places.
- Main motions only keeps E3 cheap: every machine can animate, with no distance-based detail levels.

### Terminals (B6) **[Inference: a proposal, open to change]**
M7 step 1 defines a terminal as a set of owned tiles. With areas, a terminal becomes a named group of areas:
- Each area belongs to exactly one terminal. A new area joins the terminal of the area it touches, or starts a new terminal if it touches none. The player can reassign an area.
- Roads belong to no terminal. A road is shared, so two terminals can sit on one trunk road, and congestion on it is a shared problem.
- A terminal needs at least one gate area and one quay apron to take contracts. Its KPIs and ledger section add up over its areas.
- The machines of an area belong to that area (D5), so they belong to its terminal too.
- This replaces M7 steps 1–2 (tile painting and refused overlaps) with "group areas, and refuse an area in two terminals".

## Questions to settle

### A. Roads
1. **Grid or free-form?** Decision 11 is "grid sim, drawn with rounded corners". Does this idea overturn it? Options: grid-snapped segments (straight runs on a fine grid with 45° and 90° joins); free-form straight and arc segments with angle snapping; full CS-style curves.
2. **Grid size if snapped.** M0 uses one tile per road cell. A finer grid (for example 1 m or 4 m) would allow lanes and slots without curves.
3. **Road types.** Which types exist at first? For example: public highway (fixed, off-map), terminal road, yard aisle, gate lane, AGV-only lane.
4. **Junctions.** Are they made automatically where roads meet, or placed as assets (roundabout, signal crossing)?
5. **Height.** Is the port flat forever, or will bridges and flyovers ever be needed (for example road over rail)?

### B. Areas
1. **How is an area made?** Options: painted with a brush like CS Industries; drawn as a rectangle or polygon; dragged along a road edge like CS2 zoning; or created by placing its first asset.
2. **Shape.** Must yard areas be rectangles aligned to a road, since real stacks are straight rows? Or any shape, with rows fitted inside?
3. **Road contact.** Must an area touch a road along a whole side, at one point, or only through its handover assets?
4. **Area types at first.** Which of these: yard block, gate, quay apron, empty depot, reefer yard, rail siding, maintenance, office or parking?
5. **Levels.** Should areas level up from boxes handled, as CS Industries does, or should unlocks stay on the port-wide milestone ladder only?
6. **Ownership.** M7 adds terminals as sets of owned tiles. Is a terminal now a group of areas?

### C. Assets
1. **Placed or generated?** Does the player place every stack row and handover lane, or does the area generate a default layout that the player edits?
2. **Required assets.** Which assets must an area have before it works? For example, a yard block needs at least one handover lane and one crane.
3. **Handover slots.** How many slots does a handover lane have, and can a slot hold one 40 ft or two 20 ft boxes?
4. **Outside areas.** Can an asset stand outside any area (a lone reach stacker pad, a parking lot)?
5. **Upgrades.** Does an asset upgrade in place (RTG to electric RTG), or is it replaced?

### D. Workflow and simulation
1. **Who moves inside a yard area?** Options: only the crane (vehicles stop at the handover lane); lorries drive the aisles beside the stacks (RTG style); or both, by equipment type.
2. **Job queue visibility.** Should the player see and reorder each crane's job queue, or only see it?
3. **Dual cycling.** Should a crane combine a discharge and a load in one trip (a real productivity trick), and should that be a policy the player turns on?
4. **Housekeeping.** Should cranes reshuffle boxes in quiet hours (moving them closer to their next exit), and should rehandles cost time when a wanted box is under others?
5. **Equipment sharing.** Does a crane belong to one area, or can it move between neighbouring areas (RTGs do this in real terminals)?
6. **Blocking.** When every handover slot is full, does the arriving vehicle wait on the road, queue in a buffer area, or get rerouted?
7. **Sim space.** Does the sim keep a grid underneath (simpler, deterministic, works with M2's cell reservation), or move to continuous positions on lanes (smoother, but every collision rule changes)?

### E. Animation
1. **Detail level.** Options: the full sequence (gantry, trolley, hoist, twistlocks, spreader telescoping 20/40); main motions only (travel, lift, set down); or full detail only near the camera.
2. **Who drives timing?** The sketch has the sim own phase times and the view follow them. Is that right, or should some motions (for example spreader sway) be purely visual?
3. **Scale.** The target is about 2,000 lorries and 20,000 boxes at 60 fps. Should only machines on screen animate in full, with distant ones shown at their phase end positions?
4. **Camera.** Do you want a follow camera for a box or a crane, to watch one move from ship to gate?
5. **Equipment list.** Which machines need full animations first: STS, RTG, reach stacker, straddle carrier, ASC, AGV, terminal tractor, lorry?

### F. Saves and existing work
1. **Old saves.** Decision 30 is "every old save migrates forever". There is no public release yet. Do dev saves count, or can the tile format be dropped with this change?
2. **Existing art.** M4 made rounded road corners, road markings and quay fenders for tiles. Which of these should carry over?

### G. Roadmap and scope
1. **Placement.** Its own phase between M4 and M5 (recommended above), merged into M6 with the lane graph, or after M6?
2. **Cuts.** This adds several months. Is anything to be cut or moved to make room, or does the total just grow?
3. **First slice.** What is the smallest version you want to play first? For example: free-form roads, one yard area type with one handover lane and one RTG, and the full RTG animation.

### H. Looking ahead
1. **Rail and barge as areas.** Should rail sidings (M5) and the barge terminal (M8) use the same area-and-asset model?
2. **Automation.** Should M10's per-block rules become per-area rules, and should automated areas (ASC with AGV transfer points) simply be another area type?
3. **Modding.** Should area and asset types be data files (decision 22), so a mod can add a new area type?
4. **The city.** If a city or hinterland is ever added, should its roads be the same road network?
