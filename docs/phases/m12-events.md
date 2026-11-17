# M12 — Events and regulations

**Goal.** Add disruption as a planning problem. Strikes and congestion create backlogs, and regulations change the rules over time, on M11's event scheduler (which already brings wind and storms). Each event type can be switched off in settings.

**Depends on.** M11.

**Exit criteria:**
- After a strike, recovery time matches outage ÷ spare-capacity fraction within tolerance.
- A shore-power regulation with a deadline costs contracts at berths that haven't complied, and doesn't at berths that have.
- With all events off, the replay hash is unchanged compared with a build without events.

## Steps

### Event framework, wind and storms
1–6. **Moved to [M11 Harbour life](m11-harbour-life.md)** (15 Nov 2026): the event scheduler, its toggles and forecasts, wind, and equipment wind limits come with tides there. Storm damage goes with M11's breakdowns.

### Strikes and congestion
7. **Moved to [M11 Harbour life](m11-harbour-life.md)**: breakdowns and the workshop.
8. **Strikes.** A labour event stops a chosen share of operations for N days. Negotiation choices cost money or reputation. Test: during a strike, throughput drops by the share.
9. **Recovery measure.** Track backlog after any outage, and show "slack" (spare capacity) as a resilience stat. Test: the recovery-time exit criterion.
10. **External congestion.** Hinterland events slow road and rail pickups, so dwell grows and yards fill. Test: dwell doubles under the event as set in the data.

### Regulations
11. **Regulation framework.** A regulation has an announcement date, a deadline, a requirement and a penalty, defined in data. Test: the penalty applies only after the deadline and only when the requirement isn't met.
12. **Shore power.** A berth upgrade with power demand. The regulation requires it for ships over a size by a game year. Test: the shore-power exit criterion.
13. **Emissions and noise** *(cuttable)*. Per-equipment emission values; neighbours' complaints scale with noise near the map edge. Test: the totals match the equipment mix.

### From the developer's notes (31 Oct 2026)
- **Decisions with consequences.** Choices that close other options, not just switches with a cost:
  - **Negotiated contracts.** An offer comes with terms the player can push on (rate, window length, minimum moves, penalty), and a line pushed too hard walks away or offers less next time.
  - **Competing lines.** Lines want the same berth windows; signing one line's service can lose another's, and an exclusive deal pays more but bars its rivals.
  - **A rival port.** An off-map port competes for the same lines; its rates and reliability move the demand the player sees.
  Test: a line pushed past its limit declines; signing an exclusive service refuses its rival's offers; a rival's lower rate cuts the offers the port gets.

### Close
14. **Fixture and soak.** New save fixture, and events in the soak test.
15. **Public playtest build.** Notes go in `docs/playtests/m12.md`.
16. **Close the phase.** Tag `m12`.
