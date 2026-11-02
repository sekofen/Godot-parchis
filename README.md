# The Loom — Parqués: Orbital Exodus

A sci-fi parqués game for **2–4 people sharing one device**, built with Godot 4.7.

## Run

Open `project.godot` in Godot and press **F5**, or run:

```sh
godot --path .
```

## Play

1. Enter player names and choose distinct colors. Roll for starting order; highest
   total starts, with ties rerolled.
2. Roll doubles to release a pawn, then roll again. When all unfinished pawns are
   jailed, you get up to three attempts per turn.
3. Select a highlighted pawn, then a green **+steps** destination. Spend each die
   whole, split the dice between pawns, or combine both on one pawn.
4. Land on an unprotected rival to send it to jail. Seguros, salidas, and colored
   home lanes protect pawns. Reaching the goal requires an exact roll.
5. Doubles retain the turn. Three consecutive doubles send one chosen pawn directly
   to the goal. Bring all four pawns home to win.

The four lights beneath each player's name track pawns that have reached the goal.
**Options** contains guidance, sound settings, and the optional move list.
**Setup** returns to player selection for a new match.

The interface defaults to English. **Options → Language → Español** switches to
Spanish and saves the choice.

**Camera:** wheel to zoom, middle-drag to pan, right-drag to orbit, **T** for top
view, **G** to toggle the angle. **Overview** restores the full board.

## Exports

[Export presets](export_presets.cfg) cover Web, Windows/Linux x86-64, and Android
ARM64 APKs, with output under `build/` and development files excluded. Distribute
desktop executables with their accompanying `.pck`.

Android needs [SDK setup](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html),
release signing, and a replacement for the placeholder ID `com.example.parques`
before shipping. Touch controls and layouts still need device testing.

### Web export

Requires Python 3 and export templates matching your Godot installation.

```sh
python3 tools/export_web.py
python3 -m http.server 8000 --directory build/web
```

Open `http://localhost:8000`. Upload the complete `build/web/` folder to your static
host. Exporting replaces that folder. Use `--godot /path/to/godot` if needed.

## Tests

Requires Python 3 and Godot on `PATH`, or an executable specified with `--godot`.

```sh
python3 tools/run_tests.py              # Headless suites
python3 tools/run_tests.py fast         # Rules and components
python3 tools/run_tests.py integration  # Game interactions and physics
python3 tools/run_tests.py visual       # Rendered checks; opens a window
python3 tests/export/test_packages.py   # Inspect release data for all four presets
```

Logs are saved under `artifacts/tests/`. Use `--timeout 120` on slower machines.
On Windows, replace `python3` with `py -3`.

See [rules and decisions](PROJECT_RULES.md), [dice design](DICE_REACTOR.md), and
[portrait replacement](assets/factions/PORTRAITS.md) for further details.
