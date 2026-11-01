# M9 — Barge and feeder transhipment

**Goal.** Add the water modes. Barges carry boxes inland, and transhipment moves boxes from mother ships to feeders and back through the yard.

**Depends on.** M8.

**Exit criteria:**
- Transhipment boxes never leave by gate or rail. They go ship → yard → ship within their connection window, or miss it with a measured penalty.
- In a scripted scenario, shifting a share of volume to barge measurably cuts both the gate queue and the rail load.
- Modal split (road/rail/barge) is shown and adjustable per line.

## Steps

### Transhipment
1. **Transhipment boxes.** A box can have an onward call instead of a land destination. Lines' data gains a transhipment share. Test: the box mix matches the data shares.
2. **Feeder services** connect to mother services with a connection window, defined in the data per line. Test: a feeder calls within the window after its mother service.
3. **Transhipment yard rules.** Blocks can be set to the transhipment role, and placement prefers blocks near the feeder berth. Test: transhipment boxes land in transhipment blocks when available.
4. **Missed connections.** A box not loaded within its window rolls to the next feeder, the line is fined, and reputation drops. Test: overbooking feeders produces missed connections.
5. **Cheaper moves.** Transhipment pays less per move than gate moves, but every box is handled twice. Prices come from the data. Test: ledger per box.

### Barge
6. **Barge berth.** A short, shallow quay type with a barge crane (reach stacker or small gantry). Test: a barge berth accepts only barges.
7. **Barge services** follow schedules to inland destinations from the hinterland data. Test: barge-booked boxes leave only by barge.
8. **River or canal edge** *(cuttable)*. A second water body on the map edge for barges, with its own shallow channel. Test: barges route through it.
9. **Three-way modal split.** Lines split between road, rail and barge. The player sets rail and barge discounts. The panel shows each share. Test: the barge scenario.

### From the developer's notes (31 Oct 2026)
- **Straddle carriers.** A straddle carrier stacks and carries in one machine: it lifts a box in a straddle block (stacks 1 over 3) and drives it to the quay or the gate itself, with no tractor. A new yard gear and block layout from the data. Test: a straddle block works a ship with no tractors, at the data's rate.

### Order and scope, with the developer (1 Nov 2026)
Where things stand: M8's ports have ship lanes, anchorages, pilots and tugs; the estuary has a 7 m river in the north, and generated coasts have one too. Boxes go by road or rail; the rail discount is port-wide.

Decisions: feeder services connect to their line's big-ship services from the lines' data, with a connection window; a box that misses its feeder rolls to the next, with a fine and a reputation drop. Barges sail up the river: they come and go through its inland end at the map edge, and only they fit its 7 m. Straddle carriers are in. Discounts stay port-wide (rail, and now barge); each line's split follows its data shares, nudged by them, and the panel shows each line's shares. Barges unlock at milestone 2, transhipment and straddle carriers at milestone 3. Order:
- **A. Transhipment boxes and connections (steps 1, 2, 5).** A share of a line's imports off its big ships are bound for its next feeder within the connection window, and the reverse; a transhipment move pays less. Test: the box mix matches the shares; a transhipment box never leaves by gate or rail; the ledger per box.
- **B. Transhipment yard rules (step 3).** A transhipment block role; boxes go to the transhipment block nearest the feeder berth. Test: transhipment boxes land in transhipment blocks when there are some.
- **C. Missed connections (step 4).** Test: overbooked feeders miss connections, rolled to the next feeder, fined.
- **D. Barges up the river (step 8).** A barge class, shallow, entering and leaving only by the river's inland end. Test: barges route through the river; big ships can't.
- **E. Barge berths and services (steps 6, 7).** A short barge berth with a barge crane; barges call on a schedule and carry boxes to and from inland places. Test: a barge berth takes only barges; barge-booked boxes leave only by barge.
- **F. Three-way split (step 9).** A barge discount beside the rail discount; the panel shows each line's road, rail and barge shares. Test: the barge scenario (gate queue and rail load both fall).
- **G. Straddle carriers (31 Oct note).** Test: a straddle block works a ship with no tractors, at the data's rate.

### Close
10. **Fixture and soak.** New save fixture, and transhipment and barge in the soak test.
11. **Public playtest build.** Notes go in `docs/playtests/m9.md`.
12. **Close the phase.** Tag `m9`.
