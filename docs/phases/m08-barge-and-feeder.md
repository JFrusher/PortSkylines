# M8 — Barge and feeder transhipment

**Goal.** Add the water modes. Barges carry boxes inland, and transhipment moves boxes from mother ships to feeders and back through the yard.

**Depends on.** M7.

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

### Close
10. **Fixture and soak.** New save fixture, and transhipment and barge in the soak test.
11. **Public playtest build.** Notes go in `docs/playtests/m8.md`.
12. **Close the phase.** Tag `m8`.
