# M3 — Contracts, economy and progression

**Goal.** Give the player goals and trade-offs. Use contracts, fees and reputation, a ledger that adds up exactly, loans and a no-fail mode, milestones that unlock content, and land bought in tiles with upkeep. Copy CS2's milestone gating and transparent money; avoid its hidden economy.

**Depends on.** M2.

**Exit criteria:**
- The ledger's daily sum equals the change in cash exactly, every game day. This is asserted in the soak test.
- Scripted scenarios show three things: selling more berth windows than the port can handle causes missed windows and lost reputation; raising storage fees lowers average dwell; dredging lets a deeper class call.
- A 2-hour manual playtest reaches the third milestone without a dead end.
- Creative mode has unlimited money and no failure.
- The save version bumps, and older fixtures migrate.

## Steps

### Ledger first
1. **Add a ledger.** Every money change goes through `Ledger.post(category, amount, note)`, and direct `money +=` is removed. The categories are listed in the data. Test: `grep -n "money +=\|money -=" scripts/sim` finds only `Ledger`, and the soak asserts the daily sum equals the change in cash.
2. **Add a ledger panel.** Today, last 7 days and per-category lines, read only from `Ledger`. Check: screenshot.

### Shipping lines and contracts
3. **Add shipping lines.**
   - `data/base/lines.json` lists fictional lines with a name, livery colour, ship class mix and how sensitive each line is to reputation.
   - Nothing uses real company names.

   Test: the loader rejects a line that uses an unknown class.
4. **Add services.** A service is a line plus a class, a weekly berth window (day and hour), a duration and an expected number of moves. The sim schedules calls from the services instead of the M0 interval timer. Test: a service calls on its weekday ±0.
5. **Contract offers.** Lines offer services when reputation and capacity allow. The player accepts or declines with a command, and accepted services become calls. Test: declining removes the offer, and accepting creates calls.
6. **Windows and lateness.**
   - A call that can't berth within its window waits at anchorage (shown off-map). Its lateness is measured.
   - A call that finishes after its window holds up the next call at that berth, so delays cascade.

   Test: overbooking one berth produces growing lateness.
7. **Reputation.** Each line has a reputation from 0 to 100. It moves with lateness, moves per hour and turn times, using weights from the data. Below a threshold the line cancels a service. Test: a scripted run of bad calls cancels it, and good calls bring it back.

### Fees and dwell
8. **Storage fees and free days.** The player sets free days (0–3) and a fee per box per day. Boxes kept past their free days pay storage. The roadmap's 1:2 import:export dwell ratio sits in the data. Test: storage income matches days × fee.
9. **Dwell reacts to fees.** The pickup time of an import box shortens as fees rise, using a curve from the data. Shipper satisfaction falls as fees rise and feeds into line reputation. Test: the fee-raises-lower-dwell scenario.
10. **Price per move.** Revenue per move depends on box size (40 ft ≈ 1.8 × 20 ft), with a reefer premium. Rebase M0's $120 per box in the data. Test: a scripted call earns the expected sum.

### Debt and modes
11. **Loans.** The player can take up to 3 loans from a data table of amount, rate and term, paid back daily through the ledger. Test: payments sum to principal plus interest.
12. **Bailout.** When cash is below zero for N days, a bailout covers the debt, adds a reputation penalty and blocks new loans for a period. There is no game over. Test: the bailout fires once at the threshold.
13. **Creative mode.** A flag on the new-game screen. In creative mode the ledger still records everything but cash never limits building, and bailouts are off. Test: building at $0 succeeds only in creative mode.

### Land and dredging
14. **Map tiles.**
    - The map becomes a grid of purchasable tiles (start with 3×3 tiles of 32×32 cells; cell size from the data).
    - The player owns the starting tile. Building outside owned tiles is refused.
    - Each owned tile charges daily upkeep.

    Test: building in an unowned tile fails, and buying it charges price plus upkeep.
15. **Bigger map.** The default map grows to the largest the tiles allow. Check that M1's benchmark stays inside budget. Check: bench output updated in `docs/perf.md`.
16. **Channel depth.**
    - The water has a channel route from the map edge to each berth.
    - Channel depth is the minimum along the route, and ships need channel depth ≥ draft.
    - Dredging the channel costs capital per metre plus a monthly maintenance cost.

    Test: a Panamax can't call until the channel is dredged to its draft.
17. **Tide** *(cuttable)*. Depth varies ±1 m over the calendar day, and a deeper ship may call only around high water. Test: arrival is held until the tide window.
18. **Crane orders take time.** Buying an STS crane creates an order delivered after a lead time from the data (2–3 game weeks). Test: the crane appears exactly at delivery.

### Progression
19. **Milestones.** A data table of thresholds on TEU per game year. Each milestone unlocks ship classes, equipment, panels and tile purchases. Test: content stays locked below the threshold and unlocks on crossing it.
20. **Gated panels.** UI panels such as the ledger detail, contracts and dredging appear only when their milestone unlocks, as CS2 does with its economy tabs. Check: screenshot on a new game.
21. **Year-end scoreboard.** At the end of each game year, show average port hours per call, moves per hour and turn time against the previous year, in the spirit of the CPPI ranking. Test: the values match the KPI history.

### Close
22. **Scenarios as tests.** Add `tests/test_economy_scenarios.gd` with the three scripted scenarios from the exit criteria.
23. **Soak test update.** Ledger sum, loans and bailouts, tiles and contracts in random commands.
24. **New save fixture** and migration test.
25. **Playtest.** Two hours, aiming for milestone 3. Notes go in `docs/playtests/m3.md`.
26. **Close the phase.** Tag `m3`.
