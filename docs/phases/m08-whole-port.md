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

### Close
14. **Bench at port scale.** Set new targets in `docs/perf.md` and meet them.
15. **Fixture and soak.** New save fixture, and multi-terminal commands in the soak test.
16. **Public playtest build.** Notes go in `docs/playtests/m8.md`.
17. **Close the phase.** Tag `m8`.
