# Chamber 4

The first playable prototype: one test chamber run by VESPER, her terminal, and her core with one neuron to repair. Godot
4.7; the level is built in code, in `scripts/main.gd`.

## Play

1. Start her brain (see `../brain/README.md`) and wait about 30 seconds:

   ```bash
   steering-test/.venv/bin/python brain/service.py vesper=0.35
   ```

2. Open `game/` in Godot and press Play (F5), or run `godot --path game`.

Without the brain she still talks, from a few written lines, but makes no moves.

**Controls:** WASD to move, the mouse to look, Space to jump, E to pick up or drop the cube and to repair the neuron, a click
to throw the cube, Escape to free the mouse, F11 for fullscreen.

## The chamber

- **The puzzle:** panels A and B shuttle over the acid pit and meet in the middle. Carry the cube across, A then B, and put
  it on the red button: the exit opens. Falling in the acid respawns you at the entrance; a cube that falls in is
  dispensed again.
- **Her moves** come from the brain's legal list and are all temporary: a nudged panel settles back after 6 seconds, water
  drains after 20, the lights come back after 30. A turret needs you in its line of sight for 2.5 seconds, and shows its
  beam while it aims.
- **Her terminals**, one at the entrance and one on the far side, print every move she makes, refusals and hints.
- **Her core** is behind the exit. E at neuron W-7 "warmth" repairs it: her dials go from petty 0 to −0.3, her repair stage
  from 0 to 2 (hints, open doors and shortcuts instead of traps), and the chamber starts over with her changed. E again
  breaks it, to compare.

**What the game tells her:** entering, picking up the cube, stepping onto a panel, falling in the acid, being shot, the
cube in the acid (thrown or dropped), staring at her camera for 3 seconds, standing at the locked exit, no progress for a
while, solving the chamber, finding her core. The subject never speaks.

## Test modes

Arguments go after `--`:

- `godot --path game -- --shots` saves screenshots to `game/shots/` and quits.
- `godot --path game -- --autoplay` sends five scripted events through the brain and prints her moves and lines.
- `godot --path game -- --tts` also speaks her lines with Godot's text-to-speech (needs `speech-dispatcher`).
