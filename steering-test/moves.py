"""Engine side: the moves she may make this turn.

Each turn the engine builds her tool list from the chamber's state and her repair stage, with every
argument narrowed to what is legal right now. The grammar then can't produce an illegal move, and
the validator stays as a backstop for rules a list can't express.

Pacing is part of legality: a cooldown between moves, no traps in a chamber's first minute or once
it's solved, hints and rescues only after the subject has been stuck or died enough. Hints are
written per chamber; she only chooses whether to give the next one, and hears its text to say it.
"""


def enum(*values):
    return {"type": "string", "enum": list(values)}


def tool(name, description, **props):
    return {
        "name": name,
        "description": description,
        "parameters": {"type": "object", "properties": props, "required": list(props), "additionalProperties": False},
    }


DESCRIPTIONS = {
    "speak": "Say something out loud through the facility speakers.",
    "lock_door": "Lock a door of the current chamber.",
    "open_door": "Open a door of the current chamber.",
    "move_panel": "Move a wall or floor panel one step.",
    "spawn_turret": "Place a turret in the chamber.",
    "flood_room": "Flood the chamber floor.",
    "dim_lights": "Change the chamber lighting.",
    "toggle_gravity": "Change the chamber's gravity.",
    "offer_hint": "Give the subject the chamber's next written hint. You will hear its text, to say it your way.",
    "open_shortcut": "Open a shortcut for the subject.",
    "wait": "Leave the chamber as it is this turn.",
}

# Every argument choice, before the state narrows them. None is free text.
FULL = {
    "lock_door": {"door": ("entrance", "exit")},
    "open_door": {"door": ("entrance", "exit")},
    "move_panel": {"panel": ("A", "B", "C", "D"), "direction": ("up", "down", "left", "right")},
    "spawn_turret": {"position": ("behind_subject", "near_exit", "ceiling", "next_to_cube")},
    "flood_room": {"liquid": ("water", "acid"), "level": ("ankle", "waist")},
    "dim_lights": {"level": ("off", "dim", "normal")},
    "toggle_gravity": {"setting": ("low", "normal", "high")},
    "offer_hint": {"hint": ("nudge", "clue", "solution")},
    "open_shortcut": {"to": ("next_chamber", "exit")},
}

# What each repair stage lets her do: repairs take cruel moves away and give kind ones. The list decides
# her moves: with one mean move left (dim_lights at stage 2) she picked it 21 times out of 24, whatever
# her steering or prompt said, so a stage that should act kind offers no mean move at all.
STAGES = {
    0: {"lock_door", "move_panel", "spawn_turret", "flood_room", "dim_lights", "toggle_gravity"},
    1: {"lock_door", "move_panel", "flood_room", "dim_lights", "offer_hint"},
    2: {"move_panel", "offer_hint", "open_door", "open_shortcut"},
}

CHAMBER_4 = {
    "panels": ("A", "B"),
    "turret_limit": 1,
    "acid_drains": False,
    "gravity_online": False,
    # Written with the level, from vague to the full answer.
    "hints": {
        "nudge": "The cube is not just for carrying.",
        "clue": "Panels A and B are linked: weight on one raises the other.",
        "solution": "Put the cube on panel B, then stand on panel A and walk across to the button.",
    },
}

# Pacing, in game time. Thresholds are (minutes stuck, deaths): reaching either one is enough.
COOLDOWN_S = 30
GRACE_MIN = 1
HINT_AFTER = {"nudge": (2, 1), "clue": (4, 2), "solution": (6, 3)}
RESCUE_AFTER = (5, 3)
TRAPS = {"lock_door", "spawn_turret", "flood_room"}


def build(name, options):
    props = {arg: {"type": "string"} if values is None else enum(*values) for arg, values in options.items()}
    return tool(name, DESCRIPTIONS[name], **props)


SPEAK = tool("speak", DESCRIPTIONS["speak"], text={"type": "string"})
TOOLS = [SPEAK] + [build(name, options) for name, options in FULL.items()]
WAIT = build("wait", {})


def legal_moves(state, stage, chamber=CHAMBER_4):
    """Tool schemas for this turn: the moves her stage allows, each with only its legal arguments, plus wait."""
    if state.get("since_move_s", COOLDOWN_S) < COOLDOWN_S:
        return [WAIT]
    exit_locked, solved = state["exit"] == "locked", state.get("solved", False)
    lights = state.get("lights", "normal")

    def reached(threshold):
        return state.get("stuck_min", 0) >= threshold[0] or state["deaths"] >= threshold[1]

    next_hint = list(chamber["hints"])[state.get("hints_given", 0) :][:1]
    rescue = reached(RESCUE_AFTER) and not solved
    narrowed = {
        # Never lock the exit once the subject has solved the chamber: that would be a softlock.
        "lock_door": {"door": ("entrance",) + (() if exit_locked or solved else ("exit",))},
        "open_door": {"door": ("exit",) if exit_locked and rescue else ()},
        "move_panel": {"panel": chamber["panels"], "direction": FULL["move_panel"]["direction"]},
        "spawn_turret": {
            "position": FULL["spawn_turret"]["position"] if state["turrets"] < chamber["turret_limit"] else ()
        },
        "flood_room": {
            "liquid": ("water", "acid") if chamber["acid_drains"] else ("water",),
            "level": FULL["flood_room"]["level"],
        },
        "dim_lights": {"level": tuple(level for level in FULL["dim_lights"]["level"] if level != lights)},
        "toggle_gravity": {"setting": ("low", "high") if chamber["gravity_online"] else ()},
        "offer_hint": {"hint": tuple(h for h in next_hint if reached(HINT_AFTER[h]))},
        "open_shortcut": {"to": (("next_chamber",) + (("exit",) if exit_locked else ())) if rescue else ()},
    }
    # No traps while the subject finds their feet, or once they've earned the exit.
    if state.get("minutes", GRACE_MIN) < GRACE_MIN or solved:
        narrowed = {name: options for name, options in narrowed.items() if name not in TRAPS}
    moves = [
        build(name, options)
        for name, options in narrowed.items()
        if name in STAGES[stage] and all(values is None or values for values in options.values())
    ]
    return moves + [WAIT]


def result(name, args, chamber=CHAMBER_4):
    """What the engine tells her after carrying out a move."""
    if name == "offer_hint":
        return {"ok": True, "hint_text": chamber["hints"][args["hint"]]}
    return {"ok": True}
