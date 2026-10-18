# M4 — Vertical slice and art

**Goal.** Make the game look like what it will be: a first semi-realistic industrial art pass on the core set, rounded road corners, a proper UI theme, a short guided start, and the first public Windows build.

**Depends on.** M3. From here on, art production runs alongside every later phase.

**Exit criteria:**
- The core set has final-direction models with LODs: quay, STS crane, RTG, reach stacker, tractor, lorry, 20 ft and 40 ft boxes, ship hulls for each class, gate, water.
- The game holds 60 fps at 1080p on the target mid-range PC (GTX 1660 class) on the slice map. Record it in `docs/perf.md`.
- Five outside playtesters finish the guided start without help.
- A public Windows build is downloadable, from GitHub Releases or itch.io.

## Steps

### Art direction
1. **Art bible.** Write `docs/art.md` with reference photos (your own or properly licensed), palette, scale (1 tile = 25 m), wear level, lighting times and polygon budgets per asset. Check: reviewed against three reference ports.
2. **Asset pipeline.**
   - `.blend` sources go in `art/` (Git LFS), and exports go to `assets/` as `.glb`.
   - Import presets turn on LOD generation.

   Check: one test asset goes from Blender to the game with LODs visible in the Godot inspector.
3. **Container model and liveries.**
   - One 20 ft and one 40 ft mesh.
   - Line liveries come from the line colours in `lines.json` through MultiMesh per-instance colour plus a wear texture.

   Check: screenshot of a mixed stack.
4. **Ship hulls.** One hull per class, length matched to the data, plus deck stacks drawn as MultiMesh from the ship's remaining moves. Check: screenshot of each class at berth.
5. **STS crane** with an animated trolley and spreader, driven by the crane's state. Check: a recording of one full move cycle.
6. **Yard equipment and vehicles**: RTG, reach stacker, terminal tractor and lorry. Check: screenshot.
7. **Ground and water.** Concrete and asphalt tiles with markings, quay edge, bollards, and a water shader with depth tint showing the dredged channel. Check: screenshot.

### Roads drawn round
8. **Rounded corners.** The sim stays on the grid. Road meshes for corners and junctions are chosen from tile neighbours, with circular-arc corner pieces (the roadmap explains why arcs, not Béziers). Check: screenshot of every junction type.
9. **Vehicles follow the arcs.** The view turns grid paths into arcs at corners for drawing only, and the sim still moves cell to cell. Check: recording shows no corner snapping.

### UI and onboarding
10. **UI theme.** One Godot `Theme` resource: font, colours, panel styles and icons. All HUD controls use it. Check: screenshot.
11. **Build menu by category**: roads, quay, cranes, yard, gate, land. Unlocked items only. Keyboard shortcuts 1–9. Check: manual.
12. **Inspect tool.** Clicking any entity opens a panel with its state, read from the sim. Check: manual for each entity type.
13. **Guided start.**
    - A scripted opening with steps of the form "do X, then Y", driven by sim events (not the view).
    - It ends with the first ship worked.

    Test: a headless script that feeds the expected commands completes every step.
14. **Accessibility basics.** UI scale setting, and a colour-blind-safe palette for line colours. Check: screenshot at 150% scale.

### Performance and polish
15. **Shader Baker.** Add the 4.5+ shader baker to the export to stop first-use stutter. Check: a fresh run has no shader hitches in the profiler.
16. **Performance budget per entity type.** Write it in `docs/perf.md`. The bench scene asserts the budget and fails CI when it is exceeded. Test: CI runs the bench in headless timing mode for sim cost; the render budget is checked manually.
17. **Audio** *(cuttable)*: ambient harbour, crane and lorry sounds, UI clicks. Check: manual.

### First public build
18. **Windows export preset** and a CI job that builds a zip on tags. Check: the artifact runs on a clean Windows machine.
19. **Crash and log capture.** On error the game writes the log, the save and the content hash to `user://reports/` and shows the folder. Check: forcing an error produces a report.
20. **Publish the playtest build** on GitHub Releases or itch.io with a feedback form link. Check: the download link works.
21. **Five outside playtests** of the guided start. Notes go in `docs/playtests/m4.md`, with the top five issues filed.
22. **Close the phase.** Tag `m4`.
