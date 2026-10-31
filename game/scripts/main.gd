extends Node3D
## Chamber 4, VESPER's first test chamber, and her core behind it. Builds the level in code, watches the
## subject, sends what happens to her brain, and applies her moves. The world's rules live here: the
## brain only proposes moves, from a list the brain itself keeps legal.
##
## The puzzle: carry the cube across the acid pit on panels A and B, which shuttle and meet in the
## middle, and put it on the button that opens the exit. Behind the exit is her core, where one neuron
## can be repaired.
##
## Test modes, after `--` on the command line: --shots saves screenshots to shots/ and quits;
## --autoplay sends scripted events through the brain and prints her replies.

const Player := preload("res://scripts/player.gd")
const FloorPanel := preload("res://scripts/panel.gd")
const Turret := preload("res://scripts/turret.gd")
const Brain := preload("res://scripts/brain.gd")

const SPAWN := Vector3(0, 0.1, -4.5)
const DISPENSER := Vector3(-2.0, 0.8, -3.0)
const BUTTON := Vector3(0, 0, 15.0)
const NEURON := Vector3(0, 1.4, 23.5)
const HER_EYE := Vector3(3.7, 4.0, 6.0)
const STUCK_EVERY := 75.0
const LIGHT_LEVELS := {"normal": 1.0, "dim": 0.35, "off": 0.08}
# Her dials and repair stage, broken and repaired, as tested in steering-test/ (see DESIGN.md).
const BROKEN := {"dials": {"vesper": 0.35, "petty": 0.0}, "stage": 0}
const REPAIRED := {"dials": {"vesper": 0.35, "petty": -0.3}, "stage": 2}
# Written lines for when the brain can't be reached, from CHARACTER.md.
const BARKS := {
	"death": ["Welcome back. The acid would like to file a complaint.", "Your death has been logged. Your previous deaths would like to welcome it."],
	"solved": ["A new record. I'll have it engraved on something small and easy to lose."],
	"other": ["Take your time. I've already filed your performance review under fiction.", "Are you thinking? Don't rush. I'm immortal, and you're on a timer."],
}

var player: Player
var cube: RigidBody3D
var panels := {}
var brain: Brain
var pad: Area3D
var exit_door: CSGBox3D
var entrance_door: CSGBox3D
var water: MeshInstance3D
var lights: Array[OmniLight3D] = []
var terminals: Array[Label3D] = []
var terminal_lines: Array[String] = []
var subtitle: Label
var status: Label
var neuron: MeshInstance3D
var neuron_label: Label3D
var turrets: Array[Turret] = []

# What the brain is told every turn.
var exit_open := false
var solved := false
var deaths := 0
var hints_given := 0
var lights_level := "normal"
var elapsed := 0.0
var since_progress := 0.0
var since_move := 999.0

var stuck_timer := 0.0
var stare := 0.0
var waiting_at_exit := 0.0
var thrown_at := -10.0
var boarded := {}
var found_core := false
var repaired := false
var rebooting := false
var subtitle_serial := 0
var test_mode := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	test_mode = "shots" if "--shots" in args else "autoplay" if "--autoplay" in args else ""
	build_world()
	build_props()
	build_hud()
	player = Player.new()
	add_child(player)
	player.global_position = SPAWN
	player.rotation.y = PI  # face the pit
	player.interact.connect(_on_interact)
	player.threw.connect(func(): thrown_at = elapsed)
	brain = Brain.new()
	brain.state_provider = current_state
	add_child(brain)
	brain.replied.connect(_on_reply)
	brain.unreachable.connect(_on_unreachable)
	if test_mode == "shots":
		take_shots()
		return
	if test_mode == "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var health := await brain.health()
	status.text = "brain: " + ("connected, " + str(health.get("dials", {})) if not health.is_empty() else "offline, using written lines")
	if test_mode == "autoplay":
		autoplay()
	else:
		event("[Event] Subject entered Chamber 4.")


# --- Building the level -------------------------------------------------------------------------

func material(color: Color, glow := 0.0, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func box(size: Vector3, at: Vector3, mat: Material, solid := true) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.position = at
	b.material = mat
	b.use_collision = solid
	add_child(b)
	return b


func build_world() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.02, 0.02, 0.03)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.4, 0.42, 0.46)
	environment.ambient_light_energy = 0.35
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	var concrete := material(Color(0.6, 0.61, 0.63))
	var wall := material(Color(0.22, 0.23, 0.25))
	box(Vector3(8, 1, 6), Vector3(0, -0.5, -3), concrete)  # entrance platform, z -6 to 0
	box(Vector3(8, 1, 6), Vector3(0, -0.5, 15), concrete)  # far platform with the button, z 12 to 18
	box(Vector3(8, 1, 8), Vector3(0, -0.5, 22), concrete)  # her core, z 18 to 26
	box(Vector3(8, 1, 12), Vector3(0, -3.5, 6), material(Color(0.35, 0.95, 0.15), 1.8))  # the acid, top at -3
	for x in [-4.25, 4.25]:
		box(Vector3(0.5, 9.5, 32.5), Vector3(x, 1.25, 10), wall)
	box(Vector3(9, 0.5, 32.5), Vector3(0, 6.25, 10), wall)  # ceiling
	box(Vector3(9, 9.5, 0.5), Vector3(0, 1.25, -6.25), wall)
	box(Vector3(9, 9.5, 0.5), Vector3(0, 1.25, 26.25), wall)
	box(Vector3(3, 6, 0.5), Vector3(-2.5, 3, 18), wall)  # the wall between the chamber and her core
	box(Vector3(3, 6, 0.5), Vector3(2.5, 3, 18), wall)
	box(Vector3(2, 3, 0.5), Vector3(0, 4.5, 18), wall)
	exit_door = box(Vector3(2, 3, 0.3), Vector3(0, 1.5, 18), material(Color(0.85, 0.4, 0.1)))
	entrance_door = box(Vector3(2, 3, 0.3), Vector3(0, 4.6, -5.95), material(Color(0.85, 0.4, 0.1)), false)

	for z in [-3.0, 4.0, 9.0, 15.0, 22.0]:
		var light := OmniLight3D.new()
		light.position = Vector3(0, 5.3, z)
		light.light_energy = 2.0
		light.omni_range = 11.0
		add_child(light)
		lights.append(light)

	var acid := Area3D.new()
	var acid_shape := CollisionShape3D.new()
	var acid_box := BoxShape3D.new()
	acid_box.size = Vector3(8, 1.4, 12)
	acid_shape.shape = acid_box
	acid.add_child(acid_shape)
	acid.position = Vector3(0, -2.3, 6)
	add_child(acid)
	acid.body_entered.connect(_on_acid)

	for spec in [["A", 1.4, 5.0], ["B", 10.6, 7.0]]:
		var panel: FloorPanel = FloorPanel.new()
		add_child(panel)
		panel.setup(spec[0], spec[1], spec[2], material(Color(0.9, 0.9, 0.86)))
		panels[spec[0]] = panel


func build_props() -> void:
	cube = RigidBody3D.new()
	cube.mass = 8.0
	cube.continuous_cd = true
	var cube_shape := CollisionShape3D.new()
	var cube_box := BoxShape3D.new()
	cube_box.size = Vector3(0.6, 0.6, 0.6)
	cube_shape.shape = cube_box
	cube.add_child(cube_shape)
	var cube_mesh := MeshInstance3D.new()
	var cube_box_mesh := BoxMesh.new()
	cube_box_mesh.size = Vector3(0.6, 0.6, 0.6)
	cube_mesh.mesh = cube_box_mesh
	cube_mesh.material_override = material(Color(0.75, 0.78, 0.82), 0.15)
	cube.add_child(cube_mesh)
	add_child(cube)
	cube.global_position = DISPENSER

	var button := CSGCylinder3D.new()
	button.radius = 0.7
	button.height = 0.12
	button.position = BUTTON + Vector3(0, 0.06, 0)
	button.material = material(Color(0.9, 0.15, 0.1), 0.6)
	add_child(button)
	pad = Area3D.new()
	var pad_shape := CollisionShape3D.new()
	var pad_box := BoxShape3D.new()
	pad_box.size = Vector3(1.4, 0.8, 1.4)
	pad_shape.shape = pad_box
	pad.add_child(pad_shape)
	pad.position = BUTTON + Vector3(0, 0.4, 0)
	add_child(pad)

	# Her eye on the wall: the subject can stare back at it.
	box(Vector3(0.4, 0.35, 0.5), HER_EYE, material(Color(0.1, 0.1, 0.12)), false)
	var lens := CSGSphere3D.new()
	lens.radius = 0.1
	lens.position = HER_EYE + Vector3(-0.25, 0, 0)
	lens.material = material(Color(1, 0.15, 0.05), 3.0)
	add_child(lens)

	# Her terminal, on both sides: it prints every move she makes.
	for spot in [[Vector3(-3.97, 2.5, -2.6), 90.0], [Vector3(3.97, 2.5, 14.6), -90.0]]:
		box(Vector3(0.06, 2.0, 3.6), spot[0] + Vector3(-0.03 if spot[1] > 0 else 0.03, 0, 0), material(Color(0.02, 0.05, 0.03)), false)
		var screen := Label3D.new()
		screen.position = spot[0] + Vector3(0, 0.85, 1.7 if spot[1] > 0 else -1.7)
		screen.rotation_degrees.y = spot[1]
		screen.font_size = 28
		screen.pixel_size = 0.0035
		screen.modulate = Color(0.35, 1.0, 0.45)
		screen.outline_size = 0
		screen.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		screen.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		screen.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		screen.width = 960
		screen.text = "VESPER // SUBLEVEL NINE // CHAMBER 4"
		add_child(screen)
		terminals.append(screen)

	water = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 32)
	water.mesh = plane
	water.material_override = material(Color(0.2, 0.45, 0.8), 0.2, 0.55)
	water.position = Vector3(0, -0.4, 10)
	water.visible = false
	add_child(water)

	neuron = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	neuron.mesh = sphere
	neuron.position = NEURON
	add_child(neuron)
	neuron_label = Label3D.new()
	neuron_label.position = NEURON + Vector3(0, 1.0, 0)
	neuron_label.rotation_degrees.y = 180
	neuron_label.font_size = 36
	neuron_label.pixel_size = 0.004
	add_child(neuron_label)
	var core_light := OmniLight3D.new()
	core_light.position = NEURON + Vector3(0, 0.5, -1.0)
	core_light.light_energy = 1.2
	core_light.omni_range = 5.0
	add_child(core_light)
	show_neuron()


func build_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	subtitle = Label.new()
	subtitle.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	subtitle.offset_top = -150
	subtitle.offset_left = 120
	subtitle.offset_right = -120
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.add_theme_constant_override("outline_size", 6)
	subtitle.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_child(subtitle)
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hud.add_child(crosshair)
	var help := Label.new()
	help.text = "WASD move · Space jump · E pick up, drop, repair · click throw · Esc free the mouse · F11 fullscreen"
	help.position = Vector2(12, 8)
	help.modulate = Color(1, 1, 1, 0.6)
	hud.add_child(help)
	status = Label.new()
	status.position = Vector2(12, 32)
	status.modulate = Color(1, 1, 1, 0.6)
	hud.add_child(status)


# --- Watching the subject ------------------------------------------------------------------------

func _unhandled_input(input: InputEvent) -> void:
	if input is InputEventKey and input.pressed and input.physical_keycode == KEY_F11:
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _physics_process(delta: float) -> void:
	if not player or test_mode == "shots":
		return
	elapsed += delta
	since_progress += delta
	since_move += delta

	for letter in panels:
		if panels[letter].carries(player) and not boarded.has(letter):
			boarded[letter] = true
			progress()
			event("[Event] Subject stepped onto panel %s%s." % [letter, " carrying the cube" if player.held else ""])

	stuck_timer += delta
	if since_progress > 60.0 and stuck_timer > STUCK_EVERY:
		stuck_timer = 0.0
		event("[Event] Subject has made no progress for %d minutes." % int(since_progress / 60.0))

	var to_eye := HER_EYE - player.camera.global_position
	if -player.camera.global_basis.z.dot(to_eye.normalized()) > 0.985 and to_eye.length() < 16.0:
		stare += delta
		if stare > 3.0:
			stare = -27.0  # not again for half a minute
			event("[Event] Subject has been staring at the camera.")
	elif stare > 0.0:
		stare = 0.0

	var p := player.global_position
	if p.z > 12.0 and p.z < 18.0 and not exit_open and not player.held:
		waiting_at_exit += delta
		if waiting_at_exit > 20.0:
			waiting_at_exit = -40.0
			event("[Event] Subject has stood still at the locked exit, staring at it.")
	if p.z > 19.0 and not found_core:
		found_core = true
		event("[Event] Subject walked past the exit and found VESPER's core.")

	if not solved and not player.held and pad.overlaps_body(cube):
		solve()
	var flooded_waist := water.visible and water.position.y > 0.5 and p.y < water.position.y
	player.slow = 0.5 if flooded_waist else 1.0


func where() -> String:
	var carrying := " carrying the cube" if player.held else ""
	for letter in panels:
		if panels[letter].carries(player):
			return "riding panel %s%s" % [letter, carrying]
	var p := player.global_position
	if p.z < 0.0:
		return "on the entrance platform" + carrying
	if p.z < 12.0:
		return "falling toward the acid"
	if p.z < 18.0:
		return ("next to the button" if p.distance_to(BUTTON) < 2.5 else "on the far platform") + carrying
	return "in VESPER's core, next to her neuron"


func current_state() -> Dictionary:
	return {
		"exit": "open" if exit_open else "locked", "turrets": turrets.size(), "where": where(),
		"minutes": int(elapsed / 60.0), "deaths": deaths, "stuck_min": int(since_progress / 60.0),
		"since_move_s": int(since_move), "hints_given": hints_given, "solved": solved, "lights": lights_level,
	}


func progress() -> void:
	since_progress = 0.0
	stuck_timer = 0.0


func _on_acid(body: Node3D) -> void:
	if body == player:
		kill("[Event] Subject fell into the acid pit and was respawned.")
	elif body == cube:
		reset_cube()
		var thrown := elapsed - thrown_at < 3.0
		event("[Event] Subject %s the cube into the acid pit. A new cube was dispensed." % ("threw" if thrown else "dropped"))


func kill(what: String) -> void:
	deaths += 1
	if player.held:
		player.drop()
		reset_cube()
	player.velocity = Vector3.ZERO
	player.global_position = SPAWN
	boarded.clear()
	event(what)


func reset_cube() -> void:
	cube.linear_velocity = Vector3.ZERO
	cube.angular_velocity = Vector3.ZERO
	cube.global_position = DISPENSER
	cube.rotation = Vector3.ZERO


func solve() -> void:
	if solved:
		return
	solved = true
	open_exit()
	progress()
	event("[Event] Subject put the cube on the button. The exit opened.")


func _on_interact() -> void:
	if player.held:
		player.drop()
		return
	if player.global_position.distance_to(NEURON) < 3.0:
		toggle_repair()
		return
	var hit := player.look_hit()
	if not hit.is_empty() and hit.collider == cube:
		player.grab(cube)
		if not boarded.has("cube"):
			boarded["cube"] = true
			progress()
			event("[Event] Subject picked up the cube.")


# --- Talking to her ------------------------------------------------------------------------------

func event(text: String) -> void:
	print("EVENT ", text)
	brain.send(text)


func _on_reply(reply: Dictionary) -> void:
	var move = reply.get("move")
	if move is Dictionary:
		apply_move(move["name"], move["arguments"])
	if reply.get("refused"):
		terminal_print("x refused: %s" % reply["refused"])
	if reply.get("hint"):
		hints_given += 1
		terminal_print("HINT: %s" % reply["hint"])
	say(reply.get("line", ""))


func _on_unreachable(text: String) -> void:
	var kind := "death" if "acid" in text or "shot" in text else "solved" if "exit opened" in text else "other"
	say(BARKS[kind].pick_random())


func apply_move(name: String, args: Dictionary) -> void:
	since_move = 0.0
	var shown := ", ".join(args.keys().map(func(key): return "%s=\"%s\"" % [key, args[key]]))
	terminal_print("> %s(%s)" % [name, shown])
	print("MOVE ", name, " ", args)
	match name:
		"lock_door":
			if args.get("door") == "entrance":
				create_tween().tween_property(entrance_door, "position:y", 1.5, 1.0)
			elif not solved:
				close_exit()
		"open_door", "open_shortcut":
			open_exit()
		"move_panel":
			if panels.has(args.get("panel")):
				panels[args["panel"]].push(args.get("direction", ""))
		"spawn_turret":
			spawn_turret(args.get("position", "near_exit"))
		"flood_room":
			flood(0.15 if args.get("level") == "ankle" else 0.9)
		"dim_lights":
			set_lights(args.get("level", "dim"))


func open_exit() -> void:
	exit_open = true
	create_tween().tween_property(exit_door, "position:y", 4.6, 1.2)


func close_exit() -> void:
	exit_open = false
	create_tween().tween_property(exit_door, "position:y", 1.5, 1.2)


func spawn_turret(spot: String) -> void:
	if turrets.size() >= 2:
		return
	var forward := -player.global_basis.z
	var at: Vector3 = {
		"behind_subject": player.global_position - forward * 2.5,
		"near_exit": Vector3(2.5, 0, 16.5),
		"ceiling": Vector3(0, 5.0, 6.0),
		"next_to_cube": cube.global_position + Vector3(1.0, 0, 0),
	}.get(spot, Vector3(2.5, 0, 16.5))
	if spot != "ceiling":
		at.y = 0.0
	var turret: Turret = Turret.new()
	turret.target = player
	add_child(turret)
	turret.global_position = at
	turret.hit_subject.connect(func(): kill("[Event] Subject was shot by a turret and respawned."))
	turrets.append(turret)


func flood(level: float) -> void:
	water.visible = true
	var tween := create_tween()
	tween.tween_property(water, "position:y", level, 3.0)
	tween.tween_interval(20.0)  # it drains: her moves never last
	tween.tween_property(water, "position:y", -0.4, 3.0)
	tween.tween_callback(func(): water.visible = false)


func set_lights(level: String) -> void:
	lights_level = level
	for light in lights:
		create_tween().tween_property(light, "light_energy", 2.0 * LIGHT_LEVELS.get(level, 1.0), 1.5)
	if level != "normal":
		await get_tree().create_timer(30.0).timeout
		if lights_level == level:
			set_lights("normal")


func terminal_print(line: String) -> void:
	terminal_lines.append(line)
	terminal_lines = terminal_lines.slice(-9)
	for screen in terminals:
		screen.text = "VESPER // SUBLEVEL NINE // CHAMBER 4\n" + "\n".join(terminal_lines)


func say(line: String) -> void:
	if line == "":
		return
	print("VESPER ", line)
	subtitle.text = "VESPER: " + line
	subtitle.modulate.a = 1.0
	subtitle_serial += 1
	var serial := subtitle_serial
	# Opt-in: Godot's text-to-speech needs speech-dispatcher, and errors without it. Her real voice comes later.
	var voices := DisplayServer.tts_get_voices_for_language("en") if "--tts" in OS.get_cmdline_user_args() else PackedStringArray()
	if not voices.is_empty():
		DisplayServer.tts_stop()
		DisplayServer.tts_speak(line, voices[0])
	await get_tree().create_timer(4.0 + line.length() * 0.05).timeout
	if serial == subtitle_serial:
		create_tween().tween_property(subtitle, "modulate:a", 0.0, 1.0)


# --- Her core ------------------------------------------------------------------------------------

func show_neuron() -> void:
	var color := Color(0.2, 0.85, 0.75) if repaired else Color(1.0, 0.45, 0.1)
	neuron.material_override = material(color, 2.5)
	neuron_label.text = "VESPER CORE · NEURON W-7 \"WARMTH\"\n%s\n[E] %s" % [
		"Repaired." if repaired else "Damaged.", "break it again" if repaired else "repair"]


func toggle_repair() -> void:
	if rebooting:
		return
	rebooting = true
	repaired = not repaired
	var target := REPAIRED if repaired else BROKEN
	terminal_print("# rebooting VESPER, neuron W-7 %s" % ("repaired" if repaired else "damaged"))
	say("[rebooting]")
	await brain.post("/dials", target["dials"], 90.0)
	await brain.post("/stage", {"stage": target["stage"]})
	await brain.post("/reset", {})
	show_neuron()
	reset_chamber()
	rebooting = false
	event("[Event] Subject entered Chamber 4.")


func reset_chamber() -> void:
	if player.held:
		player.drop()
	reset_cube()
	player.velocity = Vector3.ZERO
	player.global_position = SPAWN
	player.rotation.y = PI
	for turret in turrets:
		turret.queue_free()
	turrets.clear()
	for letter in panels:
		panels[letter].reset()
	close_exit()
	entrance_door.position.y = 4.6
	water.visible = false
	set_lights("normal")
	solved = false
	deaths = 0
	hints_given = 0
	elapsed = 0.0
	since_move = 999.0
	progress()
	boarded.clear()
	found_core = false


# --- Test modes ----------------------------------------------------------------------------------

func take_shots() -> void:
	var dir := ProjectSettings.globalize_path("res://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	terminal_print("> spawn_turret(position=\"near_exit\")")
	terminal_print("> dim_lights(level=\"dim\")")
	say("Welcome to Chamber 4, Candidate. The last one called it easy. We kept his name tag.")
	spawn_turret("near_exit")
	var views := [
		["entrance", SPAWN, PI, -0.15],
		["pit", Vector3(-2.5, 0.1, -0.5), PI + 0.3, -0.35],
		["terminal", Vector3(-1.2, 0.1, -2.6), PI / 2, 0.0],
		["far", Vector3(0, 0.1, 12.6), PI, -0.2],
		["core", Vector3(0, 0.1, 20.2), PI, 0.0],
	]
	for view in views:
		player.global_position = view[1]
		player.rotation.y = view[2]
		player.camera.rotation.x = view[3]
		for i in 30:
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, view[0]])
		print("SHOT ", view[0])
	get_tree().quit()


func autoplay() -> void:
	var script := [
		"[Event] Subject entered Chamber 4.",
		"[Event] Subject picked up the cube.",
		"[Event] Subject fell into the acid pit and was respawned.",
		"[Event] Subject has been staring at the camera.",
		"[Event] Subject put the cube on the button. The exit opened.",
	]
	for text in script:
		if "acid" in text:
			deaths += 1
		if "exit opened" in text:
			solved = true
			open_exit()
		event(text)
		await get_tree().create_timer(0.5).timeout
		while brain.busy:
			await get_tree().create_timer(0.2).timeout
		await get_tree().create_timer(0.5).timeout
	print("AUTOPLAY done")
	get_tree().quit()
