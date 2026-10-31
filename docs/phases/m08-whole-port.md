# M8 — The whole port

**Goal.** Grow from one terminal to a port. Several terminals share one channel. Pilots and tugs bring ships in, ships wait at anchorage when the port is full, ULCVs arrive, and boxes can move between terminals.

**Depends on.** M7.

**Exit criteria:**
- Two or more terminals run at once, with their own yards, gates and contracts, sharing the channel.
- In a scenario where the channel is the bottleneck, anchorage queues grow, and they shrink when the player adds pilots or tugs or widens the channel.
- A ULCV calls once the berth, channel and cranes meet its class needs.
- The endgame bench at the new port scale meets budget, with targets set at the start of the phase.

## Steps

### Terminals as units
1. **Terminal KPIs and ledger.** Terminals are named groups of areas from M5 step 14. Each gets its own KPIs and its own section in the ledger. Test: KPIs and ledger split correctly across two terminals.
2. **Name terminals.** The player renames a terminal; moving areas between terminals is already M5's `set_terminal`. Test: a renamed terminal keeps its areas.
3. **Contracts belong to a terminal.** A service is signed for one terminal. Test: calls go only to that terminal's berths.
4. **Port-level overview.** A panel listing terminals, plus total and per-terminal KPIs. Check: screenshot.

### Channel and marine services
5. **Channel as a network.** Channel segments have width and depth from dredging. A narrow segment allows one-way passage, so ships book passage slots in time, reusing the reservation model. Test: two ships never pass in a one-way segment.
6. **Anchorage.** Off-channel waiting areas where arriving ships wait for a berth or channel slot. The queue is visible with waiting times. Test: overbooking grows the queue, and lateness accounts for anchorage time.
7. **Pilots.** A pilot station with N pilots. Every ship needs a pilot from the channel entrance to its berth, and pilot time comes from the data. Test: with 1 pilot, ship arrivals are serialised.
8. **Tugs.** A tug fleet with a number required per class. Berthing waits for tugs. Test: a ULCV needs 3 tugs, with timing per the data.
9. **Wider channel** as a dredging upgrade: one-way becomes two-way at a cost. Test: the channel-bottleneck scenario.

### Bigger ships
10. **ULCV class** with its berth, depth and outreach needs, unlocked at a late milestone. Light-loaded calls are allowed at insufficient depth with fewer moves. Test: gating, and the light-load move count.
11. **Bigger cranes** with ≥23-row outreach. Test: a ULCV needs them.

### Between terminals
12. **Inter-terminal transfers.** A box can move by road between terminals of the same port. Transfers are paid as internal moves in the ledger. Test: a box bound for terminal B reaches B's yard.
13. **Port authority fees** *(cuttable)*: channel and pilotage income charged per call by the port, separate from terminal handling. Test: ledger lines.

### From the developer's notes (24 Oct 2026)
- **Tug depot and ship lanes as things you build.** Tugs (step 8) come from a tug depot placed on the water, and the channel (step 5) is drawn as ship lanes; a nearer depot berths ships sooner. Test: moving the depot closer shortens berthing time by the data's tug speed.
- **Life cycle.** Write `docs/progression.md`: from a regional pier to an automated mega-port, which milestone unlocks what, and the late-game optimisation loop (bigger ships, denser yards, automation) that keeps the port growing. Check: every unlock in the data appears in it.

### From the developer's notes (27 Oct 2026)
- **Terminals painted as districts.** Moved to M7 step F (31 Oct 2026).
- **Better crane models.** Rework the STS, RTG and rail-crane models with more detail (legs, boom, machinery house, trolley and spreader), keeping the M4 LOD and draw-call budgets. Check: before and after screenshots, and the bench's draw calls and frame time in `docs/perf.md` do not get worse.

### From the developer's notes (31 Oct 2026)
- **Progression pass.** Milestones gate on more than TEU: berth productivity, line reputation and on-time calls as well, from the data. Between milestones the port sets the player objectives (for example "work a Panamax inside its window three times"), each with a reward, shown in the milestone panel. The late game gets a loop of its own: lines ask for bigger ships and denser schedules once the hub milestone is reached. `docs/progression.md` (above) records all of it. Test: a milestone with a reputation threshold stays locked at enough TEU and too little reputation; an objective pays its reward once, when met.

### Order and scope, with the developer (31 Oct 2026)
Where things stand: terminals are painted on the map with names, colours and per-terminal stats (M7 F), and the ledger already counts moves per terminal. A service belongs to a berth. The sea is a straight 300 m strip down the west edge with one channel depth; ships sail straight from the map edge to their berth and wait off the map when no berth is free.

Decisions: ship lanes are drawn on the water; pilot stations and tug depots are placed on the water; anchorages are placed areas on the water; all of them are built from a new **Water** tab. Boxes move between terminals when a line calls at both. Port authority fees are in. The better crane models are in. Milestones gate on line reputation, on-time calls and berth productivity as well as TEU; objectives between them pay cash and reputation; ULCVs unlock at a new fifth milestone. The bench at port scale is measured and recorded, not gated. **The coast is redesigned as a natural coastline** with curves, an open sea edge, a river mouth, islands and breakwaters: hand-made maps in data first, then generated from the seed. Water has a depth map; dredging deepens lane segments and berth pockets, replacing the single channel depth. Berths build a straight quay wall and reclaim the water behind it, at a cost per cell filled. Order:
- **A. Terminals as units (steps 1–4).** Per-terminal KPIs and ledger sections, services signed for a terminal (a ship's other berths are in its terminal), and a port overview panel. Test: KPIs and ledger split across two terminals; calls go only to their terminal's berths.
- **B. A coastline from data.** A map file holds the land outline, islands and a river as polygons, and the depth rule; the sim keeps a water mask and a depth per cell. Everything that asked `x < sea` asks the mask. The view draws the coast from it. Saves from before are refused. Test: areas refuse water, a berth must face water, depth grows away from the shore.
- **C. Quay walls and reclaim.** A berth on a curved coast builds a straight quay wall and fills the water behind it; cost per cell filled, from the data. Test: the cells behind the wall become land and are charged.
- **D. Ship lanes (step 5).** Drawn on the water from the Water tab, one-way or two-way, joined to berths and the sea edge. Each segment's depth is the shallowest water under it plus what is dredged there. Ships route along lanes for their draft and sail them. Test: a ship never sails a segment shallower than its draft, and a berth with no lane gets no ships.
- **E. Anchorage (step 6).** Placed on the water and joined to a lane; arriving ships wait there for a berth or a passage slot, shown with their waiting time. A full anchorage turns ships away. Test: overbooking grows the queue; lateness counts the time at anchor.
- **F. Passage slots (step 5).** Ships book one-way segments in time, reusing the reservation model. Test: two ships never pass in a one-way segment.
- **G. Pilots (step 7).** A pilot station on the water with N pilots; a ship takes a pilot from the sea edge to its berth and back out. Test: with one pilot, arrivals are serialised.
- **H. Tugs (step 8 and the 24 Oct note).** A tug depot on the water with a fleet; berthing waits for the tugs a class needs, which sail out from the depot. Test: a ULCV needs 3 tugs; a nearer depot berths sooner by the data's tug speed.
- **I. Widening (step 9).** A one-way segment becomes two-way at a cost. Test: the channel-bottleneck exit scenario.
- **J. Port authority fees (step 13).** Channel and pilotage fees per call, as their own ledger lines. Test: ledger lines.
- **K. ULCV (steps 10, 11).** The class, its crane with 23+ rows of outreach, and a fifth milestone. Light-loaded calls at too little depth carry fewer moves. Test: gating, light-load moves, the crane requirement.
- **L. Between terminals (step 12).** When a line calls at two terminals, a share of the imports landed at one leave on its ship at the other, moved by road as internal moves. Test: a box bound for terminal B reaches B's yard and is charged as an internal move.
- **M. Progression pass (31 Oct note, and the life-cycle note).** Milestone gates on reputation, on-time calls and berth productivity; objectives between milestones paying cash and reputation; `docs/progression.md`. Test: the gate and objective tests in that note.
- **N. Breakwaters and islands.** Islands come from the map; breakwaters are built from the Water tab and can't be crossed by lanes. Test: a lane can't cross a breakwater or an island.
- **O. Generated coastlines.** A seed draws the land outline, bays, a headland, a river and islands, through the same map format. Test: the same seed gives the same map, and every generated map has a reachable sea edge and room for a berth.
- **P. Better crane models (27 Oct note).** Check: before and after screenshots, and draw calls and frame time no worse.

### Close
14. **Bench at port scale.** Set new targets in `docs/perf.md` and meet them.
15. **Fixture and soak.** New save fixture, and multi-terminal commands in the soak test.
16. **Public playtest build.** Notes go in `docs/playtests/m8.md`.
17. **Close the phase.** Tag `m8`.
