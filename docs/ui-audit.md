# UI audit, 25 Oct 2026

The real scene rendered at 1280×720 (and once at 1920×1080) under `xvfb-run`,
in the states a player sees: a new game, then the scripted playtest's port
(`tools/playtest.gd`, two-way gate) on day 2 with a feeder alongside: every
build menu, every detail drawer, Contracts, and Inspect on each kind of
thing. Judged against `docs/ui-style.md` and Cities: Skylines conventions.
Screenshots are in `docs/ui-audit/`. Each finding says what was seen and
where; the three marked **bug** were confirmed in the code as well.

The look itself (dark panels, blue selection, Inter, the money in green)
matches the style guide. The problems are structure and missing information.

## Bugs

1. **New game, New creative and Load replace the port in one click.** They
   sit beside Save in the top-right bar, with no confirmation and no prompt
   to save (`main.gd` calls `_use(PortSim.new(...))` straight from the
   signal). One misclick loses the session. *(01, every shot.)*
   Fix: move them to a pause menu (Esc), as CS does, and confirm when the
   port has unsaved changes. Effort: small.
2. **Panels run under the build menu and off the screen.** The left column
   stacks the stats, the event log and a drawer with no height limit, and
   the build menu and toolbar are drawn over it. Finance's Today, Recent and
   Upkeep rows, Contracts' services and Logistics' last two rows are hidden;
   Finance cuts "Storage terms" mid-word. *(04_drawer_finance, 04_drawer_logistics, 05_contracts.)*
   Fix: give drawers a maximum height with a scroll, above the build menu;
   or open them on the right. Effort: small.
3. **A depot can be built and costs upkeep, but does nothing.** No sim code
   reads the depot kind; it is drawn and charged only. *(03_menu_4_yard.)*
   Fix: hide it until depots have a job (M11's AGV depot), or give it one.
   Effort: small to hide.

## Structure against Cities: Skylines

4. **The same numbers are in three places, and two buttons open one
   drawer.** Berth rate, tractors, yard fill and money are KPI cards top
   left, again as labels on the bottom-right buttons (Logistics 20/h,
   Traffic 0/4, Finance $14,884), and again in the drawers. Ledger (top
   right) and Finance (bottom right) open the same drawer. CS has one info
   bar and one way into each panel.
   Fix: keep the KPI cards as the info bar; make the bottom-right buttons
   plain icons with no numbers; drop the Ledger button. Effort: small.
5. **The bottom-right buttons are stat lists, not info views.** CS's info
   views colour the map: traffic by congestion, buildings by state. Here
   Traffic, Containers and the rest open a list of numbers beside a map
   that doesn't change. A port game most needs these on the map: lanes by
   speed, yard blocks by fill, gate queues, routes. (M7 step 12 plans a
   traffic overlay.)
   Fix: turn each into a map overlay with a small legend; keep the numbers
   in its panel. Effort: medium per view.
6. **The event log is always open and covers the map.** Five lines sit
   under the stats at all times, and events can't be clicked. CS's
   notifications are collapsible and take you to what they are about.
   Fix: a collapsed ticker that expands, with each event a link to its
   ship, area or vehicle. Drop "Day 2:" repeated after the timestamp.
   Effort: small to medium.
7. **Time controls share a bar with file and settings buttons.** Save,
   Load, New game, New creative and UI scale sit beside Pause and the speeds.
   With bug 1's pause menu, the top right holds only the date and speeds.
8. **Inspect panels say little and offer few actions.** A quay apron shows
   only its terminal and "Working": not its length, berth, cranes or the ship
   alongside. A yard block shows role and gear in one line: not its fill,
   capacity, stacks or machines, and its role and gear can't be changed
   from it. (Gates now show level, lanes and throughput, with upgrades.)
   CS's info panels pair stats with the building's actions.
   *(06_inspect_quay_apron, 06_inspect_yard_block, 06_inspect_gate.)*
   Fix: per kind, a stats block and its actions (role, gear, lines, remove).
   Effort: medium.
9. **The Yard menu mixes building with painting.** Yard block and Depot
   build areas and show a cost; Import block and Export block are tools
   that set a block's role, look the same and show no cost. RTGs appear
   only after their milestone, with no hint they exist.
   Fix: build items only in the menu; role and gear in Inspect (finding 8).
   Show locked items greyed with their milestone. Effort: small with 8.
10. **Build buttons have no tooltips.** Only the UI scale button and the
    close buttons have one. A player can't see what a yard block holds, an
    apron's depth, a road's lanes or anything's upkeep before building.
    Fix: a tooltip per item: what it does, size, cost and upkeep. Effort: small.
11. **Contracts is a wall of text.** Rows of sentences with small `- day`,
    `+ day`, `- $10`, `+ $10` buttons; offers don't say what a call earns or
    whether its window clashes with an agreed one. M6 plans a weekly calendar.
    Fix: a table of offers (line, ship, day and hour, window, moves, value,
    clash) and the calendar beside it. Effort: medium.

## Small

12. The Roads menu offers an "AGV and tractor lane", but there are no AGVs
    yet: call it a tractor lane until M11.
13. Ships and cranes are drawn larger than the areas and boxes around them
    (M5 playtest, open 7), which makes the default view read as toy-like.

## Suggested order

Bugs 1–3 first (all small). Then 4, 7 and 10 (small, and they tidy the
screen). Then 8 and 9 together, then 6, then 11 with the M6 calendar, then
the info views (5), one at a time, starting with yard fill and traffic.
