# UI style

The HUD follows the Cities: Skylines II look: dark see-through panels with
rounded corners, a blue accent for what is selected, stats in the top left,
time and speed in the top right, and the build menu at the bottom centre.
Every value lives in `ui/theme.tres`, the project theme, so HUD code sets no
colours or sizes of its own beyond button minimum sizes.

| Token | Value | Used for |
|---|---|---|
| Panel | `rgba(18,24,33,0.82)`, 1 px `rgba(255,255,255,0.12)` border, radius 12, shadow `0 10px 30px rgba(0,0,0,0.45)` | Every HUD panel |
| Toolbar | as Panel at 0.96 alpha, radius 16 | The category bar (`Toolbar` variation) |
| Panel header | `rgba(30,41,56,0.88)`, bottom border | Titled panels (`TitledPanel`, `PanelHeader`, `PanelTitle`, `PanelBody`) |
| Card | `rgba(35,47,64,0.6)`, hover `rgba(48,64,88,0.75)` plus border, radius 8 | Buttons |
| Selected | fill `#0070dd`, border and 12 px glow `#0088ff` | Pressed buttons, focus ring, progress fill |
| Text | `#f8fafc`; secondary `#94a3b8`; disabled at 0.4 alpha | Labels (`MutedLabel` for secondary) |
| Money | `#22c55e`, 28 px semibold | `MoneyLabel` |
| Font | Inter (SIL OFL, `ui/fonts/OFL.txt`), 450 regular, 600 semibold, 15 px base | Everything |

**Deviations.** The selected fill is `#0070dd`, not `#0088ff`: white text on
`#0088ff` is 3.5:1, below the 4.5:1 minimum, and `#0070dd` gives 4.8:1. Godot
panels can't blur what is behind them without a screen-reading shader, so
there is no backdrop blur; hover is a colour change with no scale tween.
