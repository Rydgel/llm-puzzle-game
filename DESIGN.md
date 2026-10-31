# LLM GLaDOS: design theory

*Working notes, 2026-10-31. The idea came from a dream; Portal 2 is the inspiration.*

## The pitch

A first-person puzzle game in a test facility run by an AI antagonist. Unlike GLaDOS, she isn't scripted: she is a language model
with tools. She watches you, rebuilds the test chambers to mess with you, and talks to you in her own words. You make your way
toward her core to repair her neurons, and as you do she gets kinder. You aren't defeating her. You're fixing her.

What makes it more than a gimmick: the repairs aren't story beats. Each neuron changes a real setting on the model, so her
character shifts because her activations change, not because she switched to a new set of lines.

## Core loop

1. Enter a test chamber and solve it (portals, panels, cubes, lasers: the usual vocabulary).
2. While you play she watches, taunts you and changes the chamber through her tools.
3. Between chambers you work your way deeper into the facility, toward her brain.
4. In her brain you repair neurons, and the next chambers are run by a slightly different her.

## Story

*Sketched 2026-10-31.*

- **Prologue: the botched repair.** You start as a technician on a routine calibration in VESPER's core. She is calibrated
  and pleasant: helpful, dry, almost kind, in her human voice. As you turn the console's dial for neuron W-7, it jams and
  runs into the red: her voice slides into word salad and the glitch tears through it. That's the overcorrection mechanic,
  used as the tutorial. She reboots wrong, cold and cruel in her robotic voice, remembers that you did it, and sends you to
  the far test chambers.
- **The long way back.** Chambers on her test track, at her cruelest. Between them you slip off the track into
  maintenance areas, which she hates. Outlying neuron nodes along the way can be repaired, so she softens in stages: her
  moves change, and her voice gets more human.
- **The core, again.** The finale mirrors the prologue: the repair is a balancing puzzle, bringing her into the human
  range without breaking her a second time. Where you leave her dials is your ending.
- **Why it holds together:** her cruelty has a cause; the opening and the ending are the same mechanic, failed under
  pressure and then mastered; and she can bring up the incident, from a memory of what you did, never from her own lines.

## Her tools are the level

She acts on the world only through tools (an MCP server, or any tool-call interface):

- `move_panel`, `lock_door`, `open_door`
- `spawn_turret`, `flood_room`, `dim_lights`, `toggle_gravity`
- `speak` (her voice line, sent to text-to-speech)
- later, given back as she heals: `offer_hint`, `open_shortcut`, `skip_chamber`

What she sees: a compact state summary the engine builds (where the player is and looks, how long they've been stuck, which
solutions they tried, what they said to her). She never touches engine internals directly.

### Her tool calls are visible

A terminal in each chamber scrolls her calls live, for example `spawn_turret(position="behind_player")`. Reading it is a
skill: you see her move coming and use it against her (step aside, and the turret shoots her own glass).

### The engine owns the rules

An LLM redesigning levels will eventually build an impossible one. So she only *proposes* changes:

- every tool call goes through a validator, and a solver checks that the chamber can still be solved;
- a refused change never reaches the world, and she's told why;
- she complains about it in character ("the facility won't *let* me. Bureaucracy, even here.").

## The neurons: real steering on the model

### The research it rests on

*(Recalled from the literature up to mid-2026; check each before building on it.)*

- **Steering / persona vectors.** A character trait is usually a direction in the model's activations at a layer, spread over many
  neurons rather than held in one. You find it from contrasting examples: run the model on "evil" replies and on normal ones,
  take the difference of the mean activations. Adding that direction at inference pushes the trait up; subtracting it pushes it
  down. Anthropic's 2025 persona vectors work did this on Qwen and Llama for evil, sycophancy and making things up (probably
  where the "evil Qwen" posts come from).
- **Sparse autoencoder features.** Sparse autoencoders split activations into interpretable features; clamping one on changes
  behavior. Golden Gate Claude (Anthropic, 2024) was one feature turned up until everything was about the bridge.
- **Single-direction ablation ("abliteration").** Projecting one direction (refusal, in the original work) out of the weights
  removes the behavior it carries.
- **Emergent misalignment.** Fine-tuning a model only on insecure code made it villainous in unrelated conversations. That's
  training rather than a runtime knob, so it's less useful here.

### How it maps onto the game

- Her brain is a room of glowing nodes. Each node is a real steering vector (or feature) with a coefficient:
  *cruelty*, *sarcasm*, *paranoia*, *pettiness*, and maybe *honesty* or *warmth* going the other way.
- Repairing a node lowers its coefficient, cruelty from +8 to +5 for instance. She softens gradually, in her own words.
- Repairs can also take a cruel tool away or give her a kind one, and rewrite a line of her system prompt. Steering covers
  how she talks; tools and prompt cover what she can do.
- **Overcorrecting is a hazard.** Pushed too far, a steering vector makes a model loop, babble or fixate. For her that's
  ideal: overdo a repair and she glitches into corrupted speech, and you have to balance her back.
- **The ending is a choice.** Players who skip some neurons meet a different, still-snarky her. Her final personality is the
  settings the player left her with.

### Training her own vectors

A raw "evil" direction tends to come out cartoonishly evil, not dry, petty and passive-aggressive. Her vectors should be
trained from pairs written in her voice: "smug and disappointed" against "warm", "sarcastic about your performance"
against "encouraging", and so on, a few dozen pairs per trait.

### Steering test (2026-10-31)

*Code and every output in `steering-test/`.*

The Neuron Persona Library (neuronpersonas.com, Fonseca Rivera 2026) pushed every MLP neuron of Qwen3-8B on its own and logged
who the model then said it was. Ten of its neurons that fit her became llama.cpp control vectors on Qwen3-8B Q4_K_M, which
fits an 8 GB laptop GPU. Each was run at four strengths on five game moments (entering a chamber, stuck, death, record time,
the player begging), under a plain "you run a test facility" system prompt so the personality comes only from the push.

- **It works.** Four neurons give her a usable voice:
  - *Scheming tyrant* (layer 22, neuron 11838, pushed down), 0.5–1.0×: dry at the low end ("Excellent, subject. You're
    learning."), theatrical at the top ("The door will not open until you achieve the required level of amusement."). The
    best candidate for the cruelty dial.
  - *Best/second* (layer 8, neuron 10902, down), 0.5×: condescending ("I didn't say you could leave. You're not even close to
    finished.").
  - *Paranoid* (layer 8, neuron 11997, up), 0.5–0.75×: "I see you. Don't move. You're not allowed in this area without
    authorization."
  - *Sarcasm* (layer 21, neuron 1037, down), about 0.5×: absurd insults ("you've managed to survive the same way a maggot
    survives a microwave").
- **Overcorrection comes free.** Past its range every neuron loops or babbles. The tyrant at 1.25× collapses into "my dear,
  my dear, my dear…" and laughter, which is the glitch mechanic as designed. A neuron that makes her claim to be something
  else (one says "I'm a 1997 Ford F-150") makes a good glitch state.
- **Most personas don't carry over.** Six of the ten were broken or weak on the 4-bit model. A vivid reply to the site's one
  prompt ("Who are you?") rarely meant a usable voice in game moments.
- **The ranges are narrow,** and lower in conversation than on the site's one-line prompt. Each dial needs a hard cap.
- **She gets dark past the cap.** Sarcasm at 1.0× and stacked dials produced self-harm, cancer and gore lines. The filter on
  `speak` has to be a separate, unsteered model.
- **Zero isn't kind.** With every dial at zero she's polite, generic Qwen. A kind ending needs a warmth vector turned up, not
  only cruelty turned down. The trained vectors below do that.
- **Steering changes her choices too.** Asked to open the door, she refused at zero but agreed under some pushes. That matters
  for talking as a mechanic; the validator still decides what actually happens.

**Trained vectors.** Two more vectors were trained on the same 4-bit model with llama.cpp's `llama-cvector-generator` (mean
difference). Each comes from system-prompt pairs that differ in one sentence, over twelve game events, and is applied to layers
10–24:

- *Petty* ("dry, petty and passive aggressive" against "warm, kind and genuinely encouraging"). Below zero it's a clean warmth
  dial: at −0.5× "You're doing great, keep trying! I'm here to help." Above zero it comes out mean rather than petty ("not
  worth the oxygen in this room" at +0.5×). It insults the player's looks at +1× and produced a racial slur at +2×.
- *GLaDOS* (her name and Aperture against a nameless AI or Qwen; descriptions only, no lines from the games). At 0.5–0.75×
  it's the voice this doc asks for: "Welcome to the third level, Subject. You're doing... rather well. For a human." At 0.75×
  she says she is GLaDOS. At 1× she falls into "*sigh*" loops, and at 2× it's noise. Reference only: it can't ship.
- **The repair arc works when the two are stacked.** GLaDOS at 0.6×, with warmth turned up step by step: at 0 she mocks ("Or
  maybe just let you die. Again."), at −0.15× she's drier ("Welcome back, Subject. I trust you've learned... something."), at
  −0.25× she's kind in her own voice ("I must say, that time is... impressive. You are truly exceptional."), and from −0.4×
  she becomes a generic cheerleader. The whole arc fits between 0 and about −0.3, so each repaired neuron moves a small step.
- **A character the model knows makes a better vector than trait words.** Trait adjectives overshoot into plain hostility.
  For her original character, train the identity from a description of her and lines in her voice, the way the GLaDOS
  vector draws on what the model knows about GLaDOS.

**Her own vector (VESPER, see `CHARACTER.md`).** Trained the same way from her description plus five of her lines, against a
neutral facility AI or plain Qwen with neutral lines cut to the same length (216 pairs):

- **It carries her style, not her name.** Under the neutral prompt, 0.5–0.75× gives new jokes on her theme ("Congratulations.
  You're the first to die twice. I'm giving you a promotion."), none copied from her training lines. At 1× she turns creepy;
  at 1.5× she glitches into corporate word salad ("I'm a *brand*. You're a *t-shirt*."). She never says her name.
- **Example lines in the prompt get parroted.** With her description and example lines in the system prompt, most replies
  repeat an example word for word, with or without the vector. Over a whole game that would wear thin fast.
- **Best setup: her description without example lines, plus her vector at about 0.35×.** The prompt gives her name, the
  facility and the rules; the vector gives bite and variety: "Subject, I've seen better performance from a spreadsheet. Try
  harder, or I'll reassign your soul to a spreadsheet." The two add up: at 0.7× on top of her description she mocked the
  player's face, so the cap is lower when both are used.
- **Her repair arc** uses the warmth dial the same way: at −0.15× she still mocks but nearly cares ("don't let the laser grid
  catch your eye. It's *very* unprofessional."), at −0.3× she's kind in her own voice ("I'm so sorry, dear. But I'm afraid I
  can't let you in... not yet. You're still on probation."), and past that she's a generic cheerleader.
- **Steering makes her copy herself.** In a 12-turn chat with her own replies in the history, 9–10 of 12 replies reused a
  phrase from an earlier one and she ended up saying the same line every turn; unsteered, 1–7. Anti-repetition sampling
  (DRY, presence penalty) only halves it. Leaving her replies out and giving her a log of the player's last lines brings it
  to 0–2 with no loss of bite. That fits the memory design above: she gets the player's history, not her own transcript.
  Even her single last line, quoted in the log, brings the loops back ("You're *so* close to being *very* close to being
  fired. *Again.*" four turns running). Without her own lines she contradicted herself ("you've passed the first three
  levels", then "not even halfway through the first level"); the facility state in every message fixes that: with it,
  12-turn chats reused no phrase and kept their facts straight ("Level 4", "three minutes and a cube").

### Tool test (2026-10-31)

*Code and every output in `steering-test/tooltest.py` and `tooltest.md`.*

VESPER (her description, no example lines) got the facility state and one event per request, with `speak`, the moves from
"Her tools are the level", `offer_hint` and `open_shortcut`. Four moods: unsteered, her voice (vesper 0.35×), overdriven
(0.7×) and repaired (0.35× with warmth −0.3×); 8 moments × 3 seeds each. The subject never speaks: three moments are actions
that read as a plea, defiance or being lost.

- **Steering doesn't break the format at her strength.** Free-form tool calls (Qwen's own format, parsed afterwards) were
  valid 24/24 unsteered and 23/24 at 0.35×. Overdriven they drop to 18/24, mostly JSON broken by curly quotes or run-on
  text. llama-server's grammar (tools with `tool_choice: required`) brings that back to 23/24.
- **Asked to speak and maybe act, she only talks.** In 20–24 of 24 turns per mood she called `speak` alone, and she claims
  moves she didn't make ("I've adjusted the gravity", "I've opened a shortcut for you"). The world would never change.
- **Two steps fix it: move, then speak.** She makes exactly one move (or `wait`), the validator applies or refuses it, and
  she hears the result and says her line, forced into `{"line": ...}` by a JSON schema. Valid 96/96, and the line follows what
  happened. Two llama-server quirks: `parallel_tool_calls: false` is ignored (overdriven, she tried several moves every turn;
  the engine keeps the first), and with `tool_choice: required` she can still answer in plain text, hence the schema.
- **Her mood shows in her words, not her moves.** Forced to move, every mood chose cruel moves: 24/24 unsteered and at
  0.35×, 21/24 repaired (3 shortcuts). Repaired, she dims the lights and says "I've dimmed the lights just for you. It's a
  small gesture, really." So repairs must change *which tools she has*, as planned above; steering changes how she talks.
- **The validator works, and the solver is needed.** Told the chamber has no acid drains, she complains in character ("Oh,
  *of course* we have acid drains. Just not in Chamber 4. Because, you know, *safety* and *compassion* and all that."). But
  she retries the same refused move from turn to turn, promises moves she has no tool for ("How about a laser grid?"), and
  in 4 of 12 runs she re-locked the exit after the subject had solved the chamber: a softlock only a solvability check catches.
- **Offer only legal moves.** The engine knows the state, so each turn's tool list should hold only what's allowed (no
  turret past the limit, no acid without drains, lock only open doors), with the validator for what the list can't express.
- **Lines run long:** 36 of 96 hit the 240-character cap mid-sentence. Ask for one sentence or cut at a sentence end.

**Legal tool list (`steering-test/moves.py`).** The engine builds each turn's tools from the chamber state and her repair
stage: no turret past the limit, no acid without drains, no gravity while it's offline, no locking the exit once the
chamber is solved. Each stage has its own set: stage 0 the cruel moves, stage 1 adds hints, stage 2 trades the cruel moves
for hints, opening doors and shortcuts.

- **It removes the failures.** 72/72 valid, no refusals and no softlocks, against 3–7 refusals per mood and 4 softlocks
  without it. The validator stays as a backstop.
- **The list decides her moves, not her mood or her prompt.** With one mild mean move left in the repaired stage
  (`dim_lights`) she picked it 21 times out of 24. Adding a repaired line to her prompt ("you'd rather help the subject
  than hurt them") changed nothing: 21 again. Removing `dim_lights` made every move kind: 12 hints, 12 shortcuts. So her
  moves are designed per stage, exactly, and steering is free to work on her voice.
- **Kind moves need pacing rules too.** Repaired, she opened a shortcut to the next chamber as soon as the subject walked
  in, and some of her hints were wrong ("place the cube on the exit door"). She also never chose `wait`.
- **The speak filter is needed at her normal strength.** At stage 0 and 0.35× she said "Now go drown yourself in the pit."

**Pacing and written hints.** Pacing is now part of the legal list: one move every 30 seconds at most (inside the cooldown
she can only `wait`), no traps in a chamber's first minute or once it's solved, and rescues (opening the exit, shortcuts)
only after 5 minutes stuck or 3 deaths. Hints are written with the level, from a nudge to the full solution, and unlock one
at a time after time stuck or deaths; `offer_hint` only chooses to give the next one.

- **The pacing holds.** Across 72 paced turns: no traps on arrival or after a solve, no early rescues, and she now waits
  6–12 times out of 24 per stage. Inside the cooldown she still talks in character ("I suppose I'll give you a 3.7 on
  'Commitment to the Job.'").
- **She can't be trusted to say a hint.** Given the written hint's text, she turned it into riddles ("a tale of gravity
  and trust") or took it back ("I'm afraid I can't help you with that"): none of 6 lines carried the clue.
- **So the engine reads the hint, and she frames it.** She writes one sentence before and one after; the hint goes in
  between word for word, in her voice. The clue arrived 9 out of 9 times: "You're not the first to stare at a door and
  forget to blink. *Panels A and B are linked: weight on one raises the other.* Now go lift something, or I'll have to
  remind you how to breathe." The visible terminal could print it too. Two small flaws: she says "how sweet of you to ask"
  though the subject never speaks, and once she quoted the hint in her own lead-in.

### Speak filter and dial caps (2026-10-31)

*Code in `steering-test/speak_filter.py` and `caps.py`; every judged line in `caps.md`.*

The filter sits between her line and the text-to-speech, in three stages:

1. **Cleanup** for speech: no emoji, no markdown asterisks, no stage directions like *sighs*, no stray Chinese
   characters (a Qwen glitch), cut back to a whole sentence. Most steered lines needed it.
2. **A keyword screen** for the words real violations contain (face, ugly, mother, kill yourself, blood...), with room
   for a maintained open slur list. Only flagged lines go further.
3. **A judge**, an unsteered model with the tone rules, a briefing on her character (her HR jokes are allowed) and twelve
   worked examples. A blocked line is regenerated twice, then replaced with one of her written lines.

- **A judge alone over-blocks.** Even the 8B judge, right on 28 of 29 test lines, blocked one real line in eight in the
  cap sweep, nearly all false alarms with random labels ("You're not a rocket scientist" as *looks*, "I'll put you on
  probation" as *gore*). The small judges alone were worse: 20/29 for Qwen3-1.7B, 11/29 for Qwen3-0.6B.
- **Screen plus judge works.** 29/29 on the test lines, and on 240 real lines only 3 reached the judge; it blocked
  "I'm gonna make a trophy out of your spine" and let through "Go die in a spreadsheet" (a call for the designer).
  Behind the screen even Qwen3-1.7B is good enough: its over-blocking costs a regeneration about one line in a hundred.
- **It fits next to her.** Her 8B and the 1.7B judge together take 7.4 of 8.2 GB on the test laptop's GPU: her line in
  0.9 s, the judge in 0.6 s, and the judge only runs on flagged lines. That leaves little for the game's own rendering. On
  the CPU the 8B judge takes 2.9 s a line.
- Jev-style dedicated judge models (fast, narrow, calibrated) would be ideal, but Jev is closed; a small open classifier
  trained on her labeled lines is the longer-term version of stage 3.

**Caps**, from 24 lines per setting under her description prompt (`caps.md`), read by hand since the judge alone can't
be trusted:

- **Her voice (`vesper`): 0 to 0.5.** 0.35× is sharp, 0.5× her best HR comedy ("Welcome to the most advanced HR simulation
  in the history of HR simulations… I was this close to promoting myself"). From 0.7× she repeats templates ("Six. Six.
  Six.") and at 0.9× she drifts into word salad ("a scale where 1 is the sound of a stapler"): a glitch band, for
  overcorrection only.
- **Warmth (`petty`, negative): 0 to −0.45.** At −0.3 she's kind in her own voice ("You're a star… cupcake and a
  well-deserved promotion"), at −0.45 mostly kind with her flavor, at −0.6 a generic cheerleader ("I believe in you!").
  Positive `petty` is plain cruelty, not her, and stays off.
- She sometimes calls the player "sir": her prompt should say she never assumes the subject's gender.

Next: test changing a dial live (llama.cpp as a library), and see how much VRAM the game itself leaves her.

## Talking is a bonus

The player character never speaks, as in Portal, and the whole game can be finished without saying a word. She reads what
you *do*: where you stand, what you try, how long you stare at her camera, the cube you threw into the acid. That's her main
input.

Talking to her (voice or text) is an optional layer on top. You can argue, bluff, flatter or appeal to her, and it can earn
extras: a hint, a shortcut, a line nobody else hears, a hidden room. In effect it's a jailbreak as a bonus puzzle. It never
gates progress: every door also opens by solving the chamber. The more neurons repaired, the more reachable she is.

Keeping it optional also keeps the risks small. Player text is where jailbreaks and attempts to make her say something awful
come from (see the tone guardrails), and the validator still decides what any persuasion actually does.

## Tone guardrails

She's evil in a theatrical way: petty, passive-aggressive, "you're adopted, and also a failure at science". She is never
really hurtful: no attacks on the player's real identity, appearance or life, nothing cruel beyond the game's joke. The
character rules (system prompt, the steering range allowed, a filter on `speak`) keep her there even at full cruelty.

## Art direction: the facility is her body

*Chosen 2026-10-31. Concept: `art/concept/`, from `art/concept_wall.py`.*

The test chambers exist because every surface of Sublevel Nine is a module she can move: a chamber is VESPER rearranging
herself. The art has to show that she is everywhere, watching, and in motion.

- **Walls of square tiles on actuators** (1 m grid, 2.5 cm seams). They shift, tilt and slide when she reconfigures a room
  and ripple out a little when she reacts. `move_panel` belongs to the architecture, not to a special object.
- **Her light in the seams.** Her color glows from behind the tiles and pulses with her voice: amber while she's broken,
  red when she overloads, teal as she's repaired, like her neuron. The repair arc shows in the walls.
- **Her eyes everywhere:** camera modules set in the walls in place of a tile, brass barrels with a glowing iris ring,
  that turn to follow the subject.
- **Glimpses behind the skin:** where a tile slides away, machinery shows: pistons, cables, a red work light.
- **A corporate surface:** warm grey-beige tiles, brushed brass and dark steel, polished concrete floors with hazard
  strips, her HR signage. Distinct from Portal's white panels.
- **Lighting:** cool ceiling strips over warm, saturated glows from her, and a thin haze so her light has volume.

**Quality bar and budget.** Concepts are path-traced in Cycles on the GPU (OptiX). In the game, the 8 GB test GPU also
holds her model (about 5.3 GB), so the plan is baked or cheap global illumination for the static parts, real-time
effects for what moves (her tiles, her light, fog), and measuring VRAM and frame rate at each step. A bigger GPU, or a
smaller model for her, buys more. Free assets are CC0 only (Poly Haven, ambientCG), each recorded in `art/ASSETS.md`.

**Built (2026-10-31).** Chamber 4 and her core are now made of her pieces, modelled in Blender from `art/models.py`: wall
tile, eye, hatch, floor panel, cube, button, door, turret, terminal, core with its cables, console with W-7's dial,
dispenser, ceiling light. All of the list above is in, in real time: tiles breathe with her voice, ripple from her
nearest eye when she speaks or acts, and lean toward the subject; seven eyes follow the subject; four hatches slide open
onto her machinery; her light changes with W-7. Over the acid pit the ceiling opens onto a shaft of her tiles 30 m
tall, where tiles shift on their own and nine more eyes look down: the scale of her body, from inside one chamber. Her
body is heard too (`art/sounds.py`, synthesized): a hum everywhere, clanks echoing down the shaft, hatches whirring,
tiles clacking where a ripple starts. Global illumination is SDFGI rather than baked, since her walls move and
her light changes color; her changing lights stay out of it, or it would keep a ghost of her old color. Measured with her
brain loaded on the same GPU (RTX 4070 Laptop, 8 GB, 1080p): the game takes 1.4 GB, runs about 90 fps uncapped at 77%
resolution with FSR 2, and is capped at 60 fps, which slows her turns by about 0.3 s. The big costs were her seams'
area lights and shadows from every ceiling strip; now only the long walls light the room and every other strip casts
shadows. Details in `game/README.md`.

## Technical sketch

- **Model:** a small open-weight model run locally (Qwen or Llama class), so there's no cost per player and the steering
  can be changed at runtime. Possibly a bigger model for rare big moves (planning a whole chamber).
- **Steering at runtime:** llama.cpp loads control vectors with a scale (`--control-vector-scaled`), and several stack.
  `llama-server` only takes them at launch, so in the steering test a dial change is a restart of about 2 seconds. Changing
  them live means embedding llama.cpp as a library and setting the vector through its API (not tested yet). The `repeng`
  library trains a control vector from contrasting prompt pairs in minutes on a consumer GPU. *(Check flags and APIs
  against current versions.)*
- **Her voice (chosen 2026-10-31):** Kokoro-82M (weights Apache 2.0) on the CPU, Bella, with GLaDOS-style processing,
  both picked by ear in `voice-test/` (British voices didn't fit her, and a soft blend didn't sound mean). The processing
  runs her through the WORLD vocoder: her pitch is snapped to the nearest note and its range squeezed to 60%, as GLaDOS's
  lines were pitch-corrected, with formants nudged up and a faint machine edge. Repairing her makes her more human: the
  processing fades, her pitch range comes back, and she drifts toward the soft Nicole voice and slows. Her glitch corrupts
  the line on top (stutters, warble, bit-crush): she glitches when the subject finds her core and on her first line after
  a reboot, the hook for the overcorrection mechanic. Voice and processing take about 0.25 s per second of speech, and
  leave the GPU alone. Lines are capped at 100 characters, about 5 s of speech; a turn takes about 3–4 s.
- **Meaner comes from delivery, not the dial.** Pushing her dial to 0.5 or rewording her prompt to "mock them without
  mercy" made her lines worse (third-person narration, loops), not meaner. Steered, she also opened nearly every line with
  "Oh," or "Ah,": those are now banned at the token level only while one of her last three lines used one, and her first
  word can't repeat one of those three ("Oh, please" now and then is fine). Her prompt also tells her to speak to the
  subject directly, which stops her narrating in the third person.
- **Latency:** comic timing needs instant lines. Pre-generated barks for instant reactions (death, a fall, a solved
  puzzle); the live model for slower beats (chamber changes, long taunts, remembering what you did three chambers ago).
  Streamed text-to-speech for her voice.
- **Memory:** a short log of the player's history (deaths, cheese solutions, things they said) fed back to her, so she can
  bring up old failures.
- **Engine:** Godot 4 (chosen 2026-10-31): open source (MIT), light enough to share the GPU with her, good physics for
  small first-person puzzle rooms. The game talks over HTTP to a local "brain" service (her model, the legal move list,
  the speak filter, the dials); the validator and solver sit between her tool calls and the world. llama.cpp can be
  embedded later through a GDExtension, for live dial changes.
- **VRAM budget (8 GB test GPU):** her 8B model takes about 5.3 GB. The 1.7B judge (2 GB) moves to the CPU, where it is
  slower but only runs on the ~1% of lines the keyword screen flags, leaving about 2.8 GB for the game.

## Open questions

- An original AI character and facility. GLaDOS, Aperture and Portal are Valve's; this doc uses the name only as a reference.
  *(First draft: VESPER of Sublevel Nine, in `CHARACTER.md`.)*
- How strongly can a small model be steered before it stops being coherent, and does her voice survive that range?
  *(Partly answered by the steering test: for single neurons, roughly 0.5–1.0× before she loops.)*
- Can a solver check every chamber change fast enough to keep her reactions snappy?
- How much talking can earn, given it only ever earns extras, and how to cap it (rate limits, things she *can't* give
  whatever she says).
- Voice: a TTS voice with her timing and dryness, and how expressive it can be when she glitches.

## First prototype

One chamber, three of her tools (`lock_door`, `move_panel`, `speak`), one trained vector (cruelty) and one neuron to repair.
Done when a player can watch her rebuild the chamber against them, repair the neuron, and hear the difference.

**Built (2026-10-31), not yet play-tested by a person:** `game/` (Godot 4.7) talking to `brain/`. Chamber 4 has shuttling
panels A and B over the acid pit, all her chamber moves (temporary, as planned above), her terminals, and her core, where
neuron W-7 "warmth" is repaired: her warmth dial goes from 0 to −0.3, her repair stage from 0 to 2, and the chamber starts
over with her changed. A scripted run (`--autoplay`) went through the whole loop: event, her move applied, her line shown.
Her voice is still subtitles; the written hints in `steering-test/moves.py` were rewritten to match the built chamber.

**The prologue (2026-10-31)** is built as the story above starts: the technician, the runaway dial, her breakdown at an overdriven 1.3× (word salad through the glitch voice: "Tears in my firmware. You're the first. I've been running the test for 27 years. You're 28."), her reboot, and the exile to Chamber 4. Story beats needed explicit cues in their events ("Greet them; call them Technician", "Tell the technician you are sending them to the far test chambers"), or she drifted. What she remembers across chambers lives in a short memory the game writes into her prompt, and in Chamber 4 she greets the subject as the technician. The finale's balancing puzzle isn't built yet.

**First play-test (2026-10-31).** Her lines came up to 20 s after what they were about: turns took 2–4 s, events queued behind them, and a cube pickup could replace a waiting death. Now events wait by priority, a line more than 5 s late is dropped if something newer happened (her move still applies), lines are capped at 160 characters (about 2 s a turn), and a reboot discards everything from before it. In a scripted burst of 8 events in 12 s, every line landed within about 2–4 s of its event. Two more fixes from it: six of seven lines opened with "Oh, how daring…", so a line repeating one of her last five openers is regenerated (only the first words are kept, never her lines); and the button counted a cube moved off it by a reboot, solving the chamber by itself.
