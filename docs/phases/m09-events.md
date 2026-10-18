# M9 — Events and regulations

**Goal.** Add disruption as a planning problem. Wind and storms stop cranes, strikes and congestion create backlogs, and regulations change the rules over time. Each event type can be switched off in settings.

**Depends on.** M8.

**Exit criteria:**
- A scripted storm stops yard equipment at ≥65 km/h and STS cranes at ≥80 km/h. It shows a forecast one game day ahead.
- After a strike, recovery time matches outage ÷ spare-capacity fraction within tolerance.
- A shore-power regulation with a deadline costs contracts at berths that haven't complied, and doesn't at berths that have.
- With all events off, the replay hash is unchanged compared with a build without events.

## Steps

### Event framework
1. **Event scheduler.** Events come from data tables with seeded random timing per game season, are stored in the save, and apply at tick boundaries. Test: the same seed gives the same event list.
2. **Settings toggles.** Each event type has an on/off setting stored with the new game. Test: the "all events off" exit criterion.
3. **Forecasts and alerts.** Forecasts appear in the event list ahead of time, with the lead time set in the data. Test: the forecast appears exactly the lead time before the event.

### Wind and storms
4. **Wind speed** as a calendar-driven value with events adding gusts. Shown on the HUD. Test: the value curve matches the data.
5. **Equipment wind limits.** Each equipment type has a wind limit in the data (RTG 65 km/h, STS 80 km/h), and stops above it. Test: the storm scenario.
6. **Storm damage** *(cuttable)*. A chance of breakdown for equipment left working near the limit. Test: breakdowns only happen above the threshold.

### Strikes and congestion
7. **Equipment breakdowns.** A random failure rate per equipment type and a repair time at a workshop building. Test: the mean time between failures matches the data over a long soak.
8. **Strikes.** A labour event stops a chosen share of operations for N days. Negotiation choices cost money or reputation. Test: during a strike, throughput drops by the share.
9. **Recovery measure.** Track backlog after any outage, and show "slack" (spare capacity) as a resilience stat. Test: the recovery-time exit criterion.
10. **External congestion.** Hinterland events slow road and rail pickups, so dwell grows and yards fill. Test: dwell doubles under the event as set in the data.

### Regulations
11. **Regulation framework.** A regulation has an announcement date, a deadline, a requirement and a penalty, defined in data. Test: the penalty applies only after the deadline and only when the requirement isn't met.
12. **Shore power.** A berth upgrade with power demand. The regulation requires it for ships over a size by a game year. Test: the shore-power exit criterion.
13. **Emissions and noise** *(cuttable)*. Per-equipment emission values; neighbours' complaints scale with noise near the map edge. Test: the totals match the equipment mix.

### Close
14. **Fixture and soak.** New save fixture, and events in the soak test.
15. **Public playtest build.** Notes go in `docs/playtests/m9.md`.
16. **Close the phase.** Tag `m9`.
