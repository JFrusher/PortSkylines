# M10 — Policies, rules and automation

**Goal.** Let the player run a big port through rules instead of clicks: global policies, rules per yard block, and an automation technology tier that pays off in the long run but has a sourced ramp-up penalty.

**Depends on.** M9.

**Exit criteria:**
- Every policy and rule is a command, saved, and covered by the replay hash.
- An automated block with a ramp-up period performs below a manual block at first, then above it in steady state, matching the data curve.
- A large port can be run for a game month without per-vehicle input.

## Steps

### Global policies
1. **Policy framework.** A policy is a named switch or value from the data that changes sim parameters while active, and is listed in the ledger with its cost. Test: activating a policy changes exactly its parameters.
2. **Starter policies**: gate opening hours, night shifts (more labour cost, more hours), wind-limit margin, an appointment system for lorries (with the mixed results the roadmap cites), and the dual-cycling preference. Test: one scenario per policy.

### Per-block rules
3. **Block rules.** Each yard block can set its accepted box kinds, sizes, lines, maximum stack height and reefer use. Placement respects the rules. Test: a box breaking a rule is never placed in that block.
4. **Stacking strategy per block.** Choices are "by departure" (lowest re-handles) or "fill low". Re-handles are counted. Test: the "by departure" strategy gives fewer re-handles in the scripted scenario.
5. **Rule templates.** Save a block's rules as a named template and apply it to other blocks. Test: applying a template copies the rules.

### Automation tier
6. **Automated equipment types**: ASC (automated stacking crane, density 16 per tile) and AGV for horizontal transport, unlocked by milestone. Test: unlock gating.
7. **Ramp-up penalty.** Newly automated blocks run at a productivity factor that climbs to above-manual over a period, using a curve from the data. Test: the ramp-up exit criterion.
8. **Automation costs.** Higher capex, lower labour opex, and an IT system upkeep in the ledger. Test: ledger lines.
9. **Mixed operations.** Automated and manual blocks coexist, and handover between them goes through transfer points. Test: boxes move between block types without loss.

### Running without input
10. **Auto-replace and auto-order** *(cuttable)*. Optional rules: replace broken equipment, and order cranes when berth productivity drops below a target. Test: rules fire at their thresholds.
11. **Month-long hands-off soak.** A scripted large port runs a game month with no commands and stays solvent and stable. Test: the exit criterion.

### Close
12. **Fixture and soak.** New save fixture, and policies and rules in the soak test.
13. **Public playtest build.** Notes go in `docs/playtests/m10.md`.
14. **Close the phase.** Tag `m10`.
