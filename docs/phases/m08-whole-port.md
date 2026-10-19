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
1. **Terminal entity.** A terminal is a set of owned tiles, berths, yard blocks and a gate, named by the player. Each terminal has its own KPIs and its own section in the ledger. Test: KPIs and ledger split correctly across two terminals.
2. **Assign tiles to a terminal.** A paint command; tiles shared between terminals are refused. Test: refused overlaps.
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

### Close
14. **Bench at port scale.** Set new targets in `docs/perf.md` and meet them.
15. **Fixture and soak.** New save fixture, and multi-terminal commands in the soak test.
16. **Public playtest build.** Notes go in `docs/playtests/m7.md`.
17. **Close the phase.** Tag `m8`.
