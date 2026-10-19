# Proposal — Roads first, then areas and assets

**Status.** Proposed, not decided. The developer is still shaping this idea. The questions at the end must be answered before it gets a phase number and steps. Nothing here overrides **Decisions so far** in the roadmap until it is answered.

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
| G3 | First playable slice | One full chain: draw roads, then drag a quay apron, one RTG yard block and a gate. A box goes STS → tractor → RTG lane → stack → lorry → gate, with main-motion animations |

What these change **[Inference]**:
- With a grid under the roads and areas laid out automatically, D7 is answered (the sim stays on a grid), and B2 mostly is (yard areas are strips beside a road, so rows run parallel to it).
- Fully automatic layout means C2–C4 become rules for the layout generator, not things the player places.
- Main motions only keeps E3 cheap: every machine can animate, with no distance-based detail levels.

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
