# Phased implementation

This folder breaks [the roadmap](../ROADMAP.md) into one file per phase. Each file lists the phase's atomic implementation steps in order.

The roadmap's M1–M7 table assumed an Early Access release with a single terminal. The developer's decisions (see **Decisions so far** in the roadmap) change that: a free release, straight to 1.0, covering a whole port with road, rail and barge, CS2-style routing, events and automation. The work that would have been Early Access updates now sits before 1.0, so there are eleven phases. Roads and areas was added as M5 on 19 Oct 2026, making twelve; the phases after it moved up by one (scale and rail was M5, and so on).

| Phase | File | Goal | Solo estimate |
|---|---|---|---|
| M1 | [m01-foundations.md](m01-foundations.md) | Fixed tick, two clocks, saves, data files, MultiMesh, Godot 4.7 | 1.5–2.5 mo |
| M2 | [m02-terminal-loop.md](m02-terminal-loop.md) | Berths, cranes, yard equipment, gate, reservation traffic | 3–5 mo |
| M3 | [m03-economy-progression.md](m03-economy-progression.md) | Contracts, ledger, loans, milestones, map tiles, dredging | 3–4 mo |
| M4 | [m04-vertical-slice.md](m04-vertical-slice.md) | Semi-realistic art pass, UI, tutorial, first public build | 3–5 mo |
| M5 | [m05-roads-and-areas.md](m05-roads-and-areas.md) | Roads drawn on a 4 m grid, areas laid out along them, handover slots, main-motion animations | not estimated |
| M6 | [m06-scale-and-rail.md](m06-scale-and-rail.md) | Packed data, threaded paths, on-dock rail, reefers | 4–6 mo |
| M7 | [m07-cost-routing.md](m07-cost-routing.md) | CS2-style lane graph and cost routing | 3–5 mo |
| M8 | [m08-whole-port.md](m08-whole-port.md) | Several terminals, shared channel, pilots, tugs, anchorage | 4–6 mo |
| M9 | [m09-barge-and-feeder.md](m09-barge-and-feeder.md) | Barge terminal, feeder transhipment | 3–4 mo |
| M10 | [m10-events.md](m10-events.md) | Wind and storms, strikes and congestion, regulations | 2–3 mo |
| M11 | [m11-automation.md](m11-automation.md) | Global policies, per-block rules, automation tier | 3–4 mo |
| M12 | [m12-release.md](m12-release.md) | Data-file mods, settings, accessibility, 1.0 on Windows | 4–6 mo |

The total is about 33–51 months of focused solo work, plus art production that runs alongside it from M4 on. That fits the roadmap's 5–8 year solo estimate once art, polish and real-life slippage are included. All durations are estimates, not sourced figures.

## Rules for every step

These follow the developer's working style: simple over complex, one way to do things, fail fast, surgical changes, evidence before fixes.

1. **One step is one commit.** It must leave `main` playable and CI green. If a step can't be finished in one sitting, split it in the file before starting.
2. **Test first for logic.** Any step that adds a rule, formula, branch or data format adds or changes a headless test in `tests/` in the same commit. Pure rendering steps instead record a screenshot (see `tests/README.md` from M1 step 26).
3. **The sim never reads the view.** New behaviour goes in `scripts/sim/`, and the view and HUD only read it. Player actions reach the sim only as command dictionaries (from M1 step 13).
4. **Determinism is a test, not a hope.** From M1 on, every phase's tests include the replay hash test. A step that breaks it is not done.
5. **Data, not constants.** Tunable numbers go in `data/base/*.json` (from M1 step 18), never in code.
6. **Saves always migrate.** A step that changes the save format bumps `SaveFile.VERSION`, adds a `migrate_vN` function and commits a fixture save (from M1 step 17). The one exception is v11, M5's move to roads and areas: older saves hold a tile port nothing can turn into roads and areas, so they are refused with the reason, and migrations start again from v11.
7. **Mark known limits.** Every deliberate shortcut gets a `# shortcut: <the limit>, <when to upgrade>` comment.
8. **Evidence before fixes.** When something misbehaves, write down the theory, add the smallest logging or test that proves it, and only then change code.
9. **Exit criteria close the phase.** A phase ends when every exit criterion in its file passes, not when its time runs out. If time runs out, cut steps marked *(cuttable)*, never exit criteria.
10. **Tag the end of each phase:** `git tag m<N>` on the merge commit.
11. **Check the variety in every playtest.** Each phase's playtest notes say whether there was enough to build and choose between, and what was missing.

## Content list

What the port can be built from, and which phase adds what is missing. Added 31 Oct 2026; a new piece of content goes here before it goes in a phase.

| Kind | Now | Added by |
|---|---|---|
| Areas | yard block, quay apron, three gate sizes, truck park, empty depot | M8 tug depot, anchorage; M9 barge berth; M11 AGV depot, gatehouse, maintenance bay |
| Roads | terminal 1+1 and 2+2, one-way, tractor lane | M8 ship lanes; M11 power and data lines |
| Quay cranes | STS, wide STS | M8 ULCV crane (23+ rows) |
| Yard gear | reach stacker, RTG, RMG, empty handler | M9 straddle carrier; M11 ASC |
| Horizontal transport | tractors | M9 straddle carriers; M11 AGVs |
| Ships | feeder, Panamax, Neopanamax | M8 ULCV, pilots, tugs; M9 barge, transhipment feeder |
| Land side | lorries, trains | M9 barges |
