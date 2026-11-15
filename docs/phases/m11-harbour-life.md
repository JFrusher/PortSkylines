# M11 — Harbour life

**Goal.** Give the port its supporting cast, so it runs like a real harbour and each part adds a choice, not just scenery. The phase covers:
- ship services
- tides and wind
- a workshop for breakdowns
- fire and dangerous goods
- customs
- AGV fleets
- a harbour master's berth timeline
- night and day
- the town next door
- scenarios, with a daily port report

The developer chose all ten on 15 Nov 2026, from a brainstorm of what a harbour needs and what keeps a game like this fun.

**Depends on.** M10, and the pilot boats and tugs on the water (save v49).

**Taken from later phases** (15 Nov 2026, so nothing is planned twice):
- From events, now M12: the event scheduler, its toggles and forecasts, wind, equipment wind limits, storm damage and breakdowns.
- From automation, now M13: AGVs, AGV depots and fleets, and the maintenance bay (the workshop).

**Decisions so far (15 Nov 2026):**
- **Order.** Cheapest fun first, reusing what exists. Services, then tides and wind, the workshop, fire and dangerous goods, customs, AGVs, the harbour master, night and day, the town, and last scenarios and reports.
- **New buildings** (workshop, inspection shed, fire station, AGV depot) are area types drawn along a road edge with the area tool, as yard blocks and gates are. Water bases (the services jetty, a fireboat's berth) are marine bases like pilot stations.
- **Ship services.** A ship may want bunkers (fuel), provisions and waste taken off. A bunker barge, a supply boat or a waste boat from a services jetty provides each one.
  - Serving never delays a ship.
  - A ship that sails unserved pays no fee and its line thinks a little less of the port.
  - Ships waiting at anchor can be served too.
- **AGVs** drive a fine grid inside an AGV zone the player paints between the quay and the blocks. Cells are reserved, so two AGVs never meet. Lorries never enter the zone.
- **AGV power** is plug-in charging. Battery drains per kilometre and per lift. A low AGV drives to its depot's bays and stands while it charges.

**Exit criteria:**
- Boats from a services jetty serve a ship at berth or at anchor. Serving never delays a departure.
- A ship whose draft needs the tide waits for a high-tide window.
- A scripted storm stops yard gear at 65 km/h or more and STS cranes at 80 km/h or more, with a forecast one game day ahead.
- Over a long soak, the mean time between breakdowns matches the data. Broken equipment is repaired only from a workshop in reach.
- A fire is fought within its response time by a fire station or fireboat in reach. A dangerous-goods block raises the chance of one.
- A box flagged by customs never leaves the port before it is inspected.
- An AGV fleet works a ship through its zone over a soak, with no deadlock and no two AGVs in one cell. An AGV below its charge limit charges before its next job.
- Moving a call on the harbour master's timeline moves its berth window.
- Lighting changes no sim state (the replay hash is the same). The night-shift setting changes night rates as the data says.
- The town's mood follows noise, light and jobs, and a low mood refuses an expansion.
- A scenario can be won and lost. The daily port report lists the day's numbers.
- Saves migrate at every step, the soak passes with all of it on, and the replay hash holds.

## Steps

Each step is one commit, with a headless test in the same commit, or a screenshot for pure rendering. Questions for the developer are asked when their section starts.

### A. Ship services
1. **Service needs.** Each ship class lists the services it may want (bunkers, provisions, waste), with the chance of each, minutes of work and fee, in the data. A ship gets its needs when it calls. Test: the shares over many calls match the data.
2. **Services jetty and its boats.** A third marine base, the services jetty, is placed like a tug depot. It holds bunker barges, supply boats and waste boats, bought like tugs. The boats are Boats of new kinds. Save bump. Test: buying adds boats at the jetty; removing waits for them all home.
3. **Serving.** A free boat of the right kind sails to a ship at berth or at anchor, lies alongside for the service's minutes, then sails home and the fee is paid. A ship ready to sail leaves whether served or not. An unserved need costs reputation. Test: a served ship pays every fee; one with no boats free sails on time, unserved, and its line's reputation drops by the data's amount.
4. **Drawn.** The services jetty (reusing the base model), the bunker barge, the supply boat and the waste boat. Screenshot.

### B. Tides, wind and the event scheduler
5. **Event scheduler, toggles and forecasts** (was M12 steps 1–3). Events come from data tables with seeded timing per season, are saved, and apply at tick boundaries. Each kind can be switched off. A forecast appears its lead time ahead. Test: the same seed gives the same events; all off leaves the replay hash unchanged; the forecast lead time.
6. **Tides.** The water level rises and falls with the calendar (two tides a day, with range and period in the data). A ship whose draft needs more than the chart depth waits at anchor or out at sea for a window long enough for its passage. The HUD shows the tide. Test: a deep ship waits for high water and comes in on it.
7. **Wind** (was M12 step 4). Wind speed follows the calendar, with storm events adding gusts. The HUD shows it. Test: the curve matches the data.
8. **Wind limits** (was M12 steps 5–6). Each kind of equipment stops above its limit in the data (RTG 65 km/h, STS 80 km/h). Storm damage *(cuttable)* is a breakdown chance for equipment left working near the limit. Test: the storm exit criterion.

### C. Workshop and breakdowns
9. **Breakdowns** (was M12 step 7). Each kind of equipment has a seeded mean time between failures in the data. A broken crane, carrier or AGV stops where it is. Test: the mean time between failures over a long soak.
10. **Workshop.** A workshop area type along a road, with mechanics hired like pilots. Broken equipment within its reach is repaired one job per mechanic, in turn; out of reach it stays broken. Save bump. Test: repairs need a workshop in reach; more mechanics shorten the queue.
11. **Preventive maintenance.** A setting per kind of equipment to service it every so many hours. Servicing takes it out of work briefly and cuts its breakdown rate as the data says. Test: with servicing on, breakdowns fall and planned downtime rises by the data's amounts.

### D. Fire and dangerous goods
12. **Dangerous-goods segregation.** A dangerous-goods block must stand `dg_distance` from other blocks, the quay and gates. Test: one closer is refused, with the reason.
13. **Incidents and response.** A fire station area type along a road, with fire engines that drive the road network, and a fireboat that berths at a marine base. Seeded incidents happen in the yard, more often in and near dangerous-goods blocks, or on a ship at berth. The nearest crew in reach responds. A fire not reached within its response time damages boxes and stops the block, and costs money and reputation. Save bump. Test: in reach within time, nothing is lost; out of reach, the data's losses.
14. **Drawn.** The fire station, engines, the fireboat and a visible fire. Screenshot.

### E. Customs and inspection
15. **Flags.** A share of import boxes (by line, in the data) is flagged for inspection when discharged. A flagged box may not leave by lorry, rail or barge until cleared. Test: a flagged box never leaves before it is cleared.
16. **Scanner and inspection shed.** A gate can take a scanner lane: flagged boxes pass the scan, and a share are sent on. An inspection shed area type along a road takes those, inspects them over the data's minutes, then clears them. With no shed, flagged boxes wait in the yard. Save bump. Test: dwell rises by the inspection time; a port with no shed holds its flagged boxes.

### F. AGVs
17. **AGV zone.** An area type painted between the quay and the blocks, laid out as a fine grid (cell size in the data) with a handover point under each STS crane and at each block's transfer slots. Test: the grid covers the zone, and handover points sit where the cranes and slots are.
18. **Reserved paths.** An AGV books the grid cells it will cross, in time order (a time-window A* over the zone's grid), and waits rather than enter a cell someone holds. Test: in a busy soak no two AGVs share a cell and none waits forever.
19. **AGV depot and fleet.** An AGV depot area type along a road, beside a zone, with charging bays the player sizes. Its fleet is bought up to its bays. Each zone is assigned a depot. Save bump. Test: a zone takes AGVs only from its depot, and a fleet grows only to its bays.
20. **Battery and charging.** Battery drains per kilometre and per lift, and charges at the bay's rate. Below its limit an AGV finishes its job and charges before the next one; with no bay free it queues. Test: the charge exit criterion; too few bays make AGVs queue.
21. **AGVs work ships.** Inside a zone, AGVs carry boxes between the STS cranes and the blocks' transfer points in place of tractors. A terminal can mix zones and tractors. Test: an AGV terminal works a ship to the end, and boxes move between AGV and tractor blocks without loss.
22. **Drawn.** The zone's markings, AGVs with their state (working, queuing, charging, idle) and the depot's chargers. Screenshot.

### G. Harbour master
23. **Berth timeline.** A harbour master panel showing each berth's calls over the coming days as bars. The tide windows (step 6) and forecast storms (step 8) are shaded. A call can be dragged to another berth or time inside its window, as a command. Test: the reschedule command moves the call's berth and window, and is refused outside the window.

### H. Night and day
24. **Day and night.** The sun follows the calendar. Floodlights light areas at night and draw power, which shows in the ledger. Lighting reads the sim and changes nothing in it. Test: the replay hash is unchanged; the night power cost matches the data.
25. **Night shifts.** A setting per terminal: work through the night at the data's labour premium, or stand yard gear down at night. Test: night rates and costs follow the setting.

### I. The town next door
26. **The town and its mood.** A town at the map's land edge. Noise from equipment and light near it lower its mood, and jobs at the port raise it. A viewing tower area type raises it too. The HUD shows the mood. Save bump. Test: the mood follows noise, light and jobs as the data says.
27. **Approvals.** Buying land and building large areas near the town need the mood above the data's threshold. Below it they are refused, with the reason. Test: the approvals exit criterion.

### J. Scenarios and the port report
28. **Scenario format.** A scenario is a data file: a start (map and port, or a save), goals with a time limit, and medal thresholds. It is won, lost or in play, shown on the HUD. Test: a scripted scenario is won, and lost when its time runs out.
29. **Three scenarios**: *Peak season rush* (move a surge of calls on time), *Storm week* (keep the berths turning through forecast storms) and *Automate or bust* (convert a terminal to AGVs before its rivals win the line). Test: each loads and each can be won by its scripted solution.
30. **The daily port report.** A newspaper panel each morning: the day's moves, calls, money, on-time share, incidents, and headlines from the day's events. Test: the report's numbers match the ledger and ship log for that day.

### Close
31. **Fixture and soak.** A new save fixture, and every system above in the soak test.
32. **Public playtest build.** Notes go in `docs/playtests/m11.md`, including whether there was enough to build and choose between.
33. **Close the phase.** Tag `m11`.

## Questions for the developer, asked when their section starts

- **Services:** fees and how often each service is wanted, by class? Can the player turn a service off?
- **Tides:** tidal range by map (a river map with little tide)? Can a ship wait inside the port for the tide, or only at anchor?
- **Wind:** one wind for the whole map, or gusts that cross it?
- **Workshop:** does broken equipment block a road or lane while it waits? Is there a tow truck?
- **Fire:** how rare is an incident? Can a fire spread from block to block?
- **Customs:** is the flagged share set by line, by origin, or random? Can the player pay for faster inspection?
- **AGVs:** zone grid cell size, AGV speed, battery size, and whether AGVs can carry two 20 ft boxes at once.
- **Harbour master:** can calls be swapped between berths of different terminals?
- **Night:** how long is a game day at 1x speed, and are night and day shown at every game speed?
- **Town:** one town or several along the map edge? Does it grow with the port?
- **Scenarios:** fixed maps, or generated? Medals only, or unlocks for the sandbox?
