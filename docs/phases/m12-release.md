# M12 — Release 1.0 on Windows

**Goal.** Release a free, stable 1.0 on Windows with data-file mods, a sandbox mode, settings and accessibility, and a save format that will keep migrating after release.

**Depends on.** M11.

**Exit criteria:**
- A 10-hour soak with no crash or desync, and every save fixture since v1 loads.
- The endgame bench meets budget on the GTX 1660-class target.
- A data-file mod placed in the user mods folder can add a ship class, a line and an equipment type, and a broken mod is refused with a clear message.
- Store and download pages list only features that are in the build.
- Open questions 33 (localisation and accessibility) and 34 (roadmap cadence) are decided and done.

## Steps

### Sandbox and settings
1. **New-game screen.** Map choice, starting money (or creative), event toggles, seed. Test: every option reaches the sim and is stored in the save.
2. **Settings.** Keybinds, UI scale, colour-blind palette, audio, graphics quality (shadows, LOD bias, MSAA), and autosave interval. Stored in `user://settings.cfg`, separate from saves. Test: settings round-trip.
3. **Autosave and save slots.** Rotating autosaves plus named slots. Test: autosave fires on the interval and keeps N files.

### Data-file mods
4. **Mods folder.** `user://mods/<name>/` holds JSON files with the same schema as `data/base/`. Mods only add or override entries by id. There are no scripts and no PCKs, so mods can't run code. Test: a mod adds a ship class that appears in game.
5. **Mod validation.** Mods are checked with the same `Content` loader, so any error refuses that mod and names the file and key. Test: a broken mod is refused, and the base game still starts.
6. **Mods in saves.** Saves record the active mods and their content hash. Loading a save with missing mods is refused with the list. Test: the refusal names the missing mod.
7. **Mod documentation.** `docs/modding.md` with the schema and one example mod in `examples/mods/`. Test: the example mod passes validation in CI.

### Accessibility and localisation
8. **Decide open question 33** (languages and accessibility scope), and record it in the roadmap.
9. **Translatable strings.** All UI text goes through `tr()` with a CSV of keys, and English is complete. Test: a script finds no hard-coded UI strings.
10. **Screen reader support** for menus with Godot 4.5+ accessibility, if chosen in step 8. Check: manual with a screen reader.

### Release engineering
11. **Release checklist** in `docs/release.md`: version bump, changelog, fixtures, bench and soak, export and smoke test.
12. **Version in the game.** The build shows its version and git hash on the main menu and in crash reports. Test: the CI build embeds the tag.
13. **10-hour soak** on a release build. Test: the exit criterion.
14. **Store or download page.** itch.io or a free Steam page (Steam charges an app fee) with screenshots and a trailer, listing only shipped features. Check: reviewed against the build.
15. **Decide open question 34** (roadmap cadence after 1.0), and publish it.
16. **Release 1.0.** Tag `v1.0`, build in CI and publish. Check: a clean-machine install works.

### After 1.0
17. **Post-1.0 backlog** goes in `docs/phases/post-1.0.md`: the city behind the port, customs and inspection, a campaign, Steam Workshop, and script mods through Godot Mod Loader with a trust warning.
