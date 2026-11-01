# Chamber 4

The first playable prototype: one test chamber run by VESPER, her terminal, and her core with one neuron to repair. Godot
4.7 with the Forward+ renderer; the level is built in code, in `scripts/main.gd`, from her pieces in `models/`.

## Play

1. Once, fetch the free textures (CC0, about 30 MB, kept out of git; see `../art/ASSETS.md`). Without them the game
   still runs, in flat colors:

   ```bash
   python3 art/fetch_assets.py
   ```

2. Start her brain (see `../brain/README.md`) and wait about 30 seconds:

   ```bash
   steering-test/.venv/bin/python brain/service.py vesper=0.35
   ```

3. Open `game/` in Godot and press Play (F5), or run `godot --path game`. The first time, Godot imports the textures
   and models, which takes a minute.

Without the brain she still talks, from a few written lines, but makes no moves.

**Controls:** WASD to move, the mouse to look, Space to jump, E to pick up or drop the cube, repair the neuron and switch
a nerve junction, a click to throw the cube, V for the visor, hold the right mouse button on her wall to pull a tile
out, Enter to talk to her, Escape to free the mouse, F11 for fullscreen.

## Three ways into her body (prototypes)

See `../DESIGN.md`. Her moves race down her nerves as pulses before they happen (`scripts/nerves.gd`); the visor
(`scripts/visor.gd`, `shaders/visor.gdshader`) shows them through her walls; E on a junction socket (left wall, by
the exit and at the pit) reroutes them into the exit door or the pit wall's steps. Hold the right mouse button on a
wall tile to pull it out into a beam (`scripts/sculpt.gd`). Over the left side of the pit her bridge of light
hardens where her searchlight eye looks (`scripts/hologram.gd`, `shaders/hologram.gdshader`).
`godot --path game --write-movie demo.avi --fixed-fps 30 -- --demo nerves` (or `shape`, `light`) films each one;
`--demo full` films everything in one take, about two and a half minutes: the prologue, Chamber 4, her nerves, her tiles,
her light, her flood spilling over the platforms, her core repaired. The movie is the window's size at start, so for
1080p put an `override.cfg` in `game/` with `[display]` `window/size/viewport_width=1920` and
`window/size/viewport_height=1080`, and remove it afterwards.

## The prologue

The game opens in VESPER's core. You're a technician on a routine calibration, and she is calibrated: dry, pleasant, her
voice human. Hold E at the console to bring neuron W-7's dial into the green band. It jams and runs into the red: the
lights flicker, her dials go past their caps, and she babbles through her glitch voice. She reboots cruel and robotic,
remembers that you did it, and sends you to Chamber 4. `--skip-prologue` starts in Chamber 4 directly.

## The chamber

- **The puzzle:** panels A and B shuttle over the acid pit and meet in the middle. Carry the cube across, A then B, and put
  it on the red button: the exit opens. Falling in the acid respawns you at the entrance; a cube that falls in is
  dispensed again.
- **Her moves** come from the brain's legal list and are all temporary: a nudged panel settles back after 6 seconds, the
  acid she raises drains after 20, the lights come back after 30. Her flood here raises the acid in the pit: halfway up,
  or past its brim, when it spills over onto the platforms and creeps partway across them. Spilled acid burns: about
  1.5 seconds in it kills. The pit's deep acid kills at once, but panels, her steps and her bridge above it stay safe. A turret needs you in its line of sight for 2.5 seconds, and shows its
  beam while it aims.
- **Her terminals**, one at the entrance and one on the far side, print every move she makes, refusals and hints.
- **Her core** is behind the exit. E at neuron W-7 "warmth" repairs it: her dials go from petty 0 to −0.3, her repair stage
  from 0 to 2 (hints, open doors and shortcuts instead of traps), and the chamber starts over with her changed. E again
  breaks it, to compare.

**Her voice** comes from the brain a sentence at a time: Kokoro's Bella with GLaDOS-style processing (pitch snapped to
notes, range squeezed). Repairing her makes her more human: the processing fades and her voice softens and slows. She
glitches when you find her core and on her first line after a reboot. A newer line cuts the older one off; the subtitle
grows as her sentences come in and stays up as long as she talks.

**Timing:** her turns stream (`scripts/brain.gd`): her move lands about 1 second after the event, and her first sentence
plays at about 1.5–2.5 seconds while she writes the next. Turns run one at a time. While one runs, a single event waits, chosen by priority (entering, solving, her core and anything you say to her, then deaths, then the rest), so a death isn't lost behind a cube pickup. If her line starts more than 5 seconds late and something newer has happened, the line is dropped and her move still applies, except for the big moments and your words, which are worth hearing a little late. Restarting the chamber discards everything from before it.

**What the game tells her:** entering, picking up the cube, stepping onto a panel, falling in the acid, being shot, the
cube in the acid (thrown or dropped), staring at her camera for 3 seconds, standing at the locked exit, no progress for a
while, solving the chamber, finding her core.

**Talking to her** is a bonus (see `../DESIGN.md`): Enter opens a box, Enter sends, Escape closes it, and you stand
still while you type. Argue, flatter or bluff; she answers in her own words, and the brain still decides which of her
moves are legal, so talk can earn a hint or a shortcut but never skips the chamber. The subject never speaks out loud,
and talking is off during the prologue, while the story runs.

## How it looks

The facility is her body (`../DESIGN.md`, Art direction). `scripts/facility.gd` builds her walls: tiles on a 1 m grid
in one MultiMesh, her light in the seams, her eyes in place of some tiles, and hatches whose tile slides aside onto her
machinery. Over the acid pit the ceiling opens onto a shaft of her tiles 30 m tall, where they shift on their own, and
her core rises 20 m, her cables coming down out of the dark to neuron W-7, lit from far above. Her voice carries a
little of the room. The tiles breathe while she talks, ripple out from her nearest eye when she speaks or acts, and lean toward
you (`shaders/wall_tile.gdshader`). Her eyes follow you; one carries a searchlight. Her light is amber while she is
broken, red while W-7 overloads, teal once repaired, and brightens with her voice.

Her moves show in her body: a turret comes up through a hatch of her light in the floor (or down from above, over the
pit), the walls ripple out from it, and a whirr goes with it; when she dims the lights, her seams and eyes glow brighter;
her flood opens vents in the pit's walls that pour acid in, foaming where the streams land. The acid is a liquid
(`scripts/spill.gd`, a "virtual pipes" heightfield over the pit and the platforms): past the brim it spills over the
edges and runs across the floor until it thins out, and drains back into the pit after (`scripts/acid.gd`). A death flashes green (acid) or red (turret), with her glitch.

Dust drifts through her light, fumes rise off the acid, and W-7 throws sparks when it overloads (`scripts/air.gd`).
The acid is deep: you see into it, through glowing clouds churning at different depths, a dull crust drifting on top
and bubbles popping (`shaders/acid.gdshader`). Whatever falls in splashes glowing droplets, flashes green and sizzles. Her arms hold the floor panels out
over the pit from rails of her light in the walls. Her eyes glance around you as they follow you, and scan slowly when
they can't see you. Her HR slogans are painted on the walls. Reflection probes give the brass, steel, glass and floors
the rooms to reflect, captured again whenever her light changes color. The button glows once pressed.
Labels belong to the world: a plaque on her core's pedestal, the dial's readout on the console's screen; what E does
shows under the crosshair.

Her body is heard too: a low hum everywhere, clanks echoing down the shaft over the pit, hatches whirring, tiles clacking
where a ripple starts. The sounds are synthesized by `../art/sounds.py`.

`scripts/looks.gd` dresses every model by the role its surfaces are named for (tile, brass, steel, iris, seam_light…),
one shared material per role. The models come from `../art/models.py` (Blender), the signs from `../art/decals.sh`.

**Rendering and budget.** Forward+ with SDFGI, volumetric fog, SSR, SSAO, SSIL, glow, AgX tone mapping and area lights.
Her brain keeps its 8B model on the same GPU, so the game renders at 77% and FSR 2 upscales, and the frame rate is capped
at 60 (`--fps N` changes it). On the RTX 4070 Laptop at 1080p: about 90 fps uncapped, 1.4 GB of video memory, and her
turns about 0.3 s slower while the game runs.

## Test modes

Arguments go after `--`:

- `godot --path game -- --shots` saves screenshots to `game/shots/` and quits, fullscreen: the views, her walls
  moving, and her teal and red light.
- `godot --path game -- --bench` prints frame rates at each view, uncapped, and what each effect costs.
- `godot --path game --write-movie tour.avi --fixed-fps 30 --quit-after 1050 -- --tour` records a 35-second camera
  tour with sound, her brain live: the entrance, up the shaft, over the pit as she spawns a turret and floods the
  room, into her core, where W-7 is repaired, then up her core. Any test mode records the same way, with sound, for
  example the prologue: `godot --path game --write-movie prologue.avi --fixed-fps 30 -- --prologue-test`.
- `-- --pour` is a 22-second camera on her flood, from the edge of the pit as it overflows (`--quit-after 660`).
- `godot --path game -- --prologue-test` plays the prologue on its own (the dial turns by itself) and prints her
  lines, then one line in Chamber 4 to check she remembers you.
- `godot --path game -- --autoplay` sends a burst of scripted events through the brain, then types a line to her through
  the talk box, and prints her moves and lines as they stream in.
- `--autoplay` runs muted.
