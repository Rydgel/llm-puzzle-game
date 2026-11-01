extends Node3D
## Chamber 4, VESPER's first test chamber, and her core behind it. Builds the level in code, watches the
## subject, sends what happens to her brain, and applies her moves. The world's rules live here: the
## brain only proposes moves, from a list the brain itself keeps legal.
##
## The puzzle: carry the cube across the acid pit on panels A and B, which shuttle and meet in the
## middle, and put it on the button that opens the exit. Behind the exit is her core, where one neuron
## can be repaired.
##
## The game opens with the prologue (see DESIGN.md, Story): the subject is a technician calibrating her
## neuron W-7. The dial jams and runs into the red, she breaks, reboots cruel, remembers who did it, and
## sends them to Chamber 4.
##
## Test modes, after `--` on the command line: --shots saves screenshots to shots/ and quits;
## --autoplay sends scripted events through the brain and prints her replies; --prologue-test plays the
## prologue by itself (the dial turns on its own) and quits; --skip-prologue starts in Chamber 4.

const Player := preload("res://scripts/player.gd")
const FloorPanel := preload("res://scripts/panel.gd")
const Turret := preload("res://scripts/turret.gd")
const Brain := preload("res://scripts/brain.gd")
const Looks := preload("res://scripts/looks.gd")
const Facility := preload("res://scripts/facility.gd")
const Air := preload("res://scripts/air.gd")
const Acid := preload("res://scripts/acid.gd")
const Nerves := preload("res://scripts/nerves.gd")
const Visor := preload("res://scripts/visor.gd")
const Sculpt := preload("res://scripts/sculpt.gd")
const Hologram := preload("res://scripts/hologram.gd")
const Demos := preload("res://scripts/demos.gd")

const SPAWN := Vector3(0, 0.1, -4.5)
const DISPENSER := Vector3(2.0, 0.8, -3.0)
const BUTTON := Vector3(0, 0, 15.0)
const NEURON := Vector3(0, 1.4, 23.5)
const STUCK_EVERY := 75.0
const CORE_SPAWN := Vector3(0, 0.1, 20.2)
const ACID_RISEN := {"ankle": -1.8, "waist": 0.05}  # her flood: halfway up the pit, or over its brim
const BURN_TIME := 1.5  # seconds in spilled acid that a subject survives
const CONSOLE := Vector3(1.9, 0, 23.5)
const CORE_SCENE := "VESPER's core: her neuron W-7 glows in the middle of the room, the calibration console beside it. The technician is a colleague who maintains you, not a test subject."
const GREEN := Vector2(0.55, 0.7)  # the calibration dial's green band
# Before the incident she is calibrated: warm, her voice human. Overdrive is the runaway dial, past her caps.
const CALIBRATED := {"dials": {"vesper": 0.3, "petty": -0.35}, "stage": 2}
const OVERDRIVE := {"vesper": 1.3, "petty": 0.0, "overdrive": true}
const INCIDENT := "The subject is the technician who botched your calibration and broke you. You hold it against them, and you sent them to the far test chambers to suffer."
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
var exit_door: Node3D
var entrance_door: Node3D
var acid: Acid  # the acid in the pit, which her flood raises
var burn := 0.0  # seconds the subject has stood in spilled acid
var lights: Array[Light3D] = []  # each with its full energy in meta "energy"
var facility: Facility
var button_plate: Node3D
var button_glow: StandardMaterial3D
var core_rings: Array = []
var core_light: OmniLight3D
var sparks: GPUParticles3D  # from W-7 while it overloads
var probes: Array[ReflectionProbe] = []
var nerves: Nerves  # her moves race along them before they happen; junctions reroute them
var visor: Visor  # V: see her nerves through her walls
var sculpt: Sculpt  # hold the right mouse button on her wall: pull a tile out into a beam
var hologram: Hologram  # her bridge of light over the pit, solid where her searchlight eye looks
var told_her := {}  # when she was last told about each of the subject's new tricks
var voice_bus := 0
var exit_whirr: AudioStreamPlayer3D
var entrance_whirr: AudioStreamPlayer3D
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
var subtitle_fade: Tween
var voice_player: AudioStreamPlayer
var voice_queue: Array[AudioStreamWAV] = []  # the sentences of her line that have come in but not played yet
var line_open := false  # more of her line is still coming
var line_voiced := false
var talk_box: LineEdit
var heard: Label  # what the subject just said to her
var heard_serial := 0
var glitch_next := false
var test_mode := ""
var prologue := ""  # intro, calibrate, runaway, reboot; empty once the subject is in the chambers
var dial := 0.0
var auto_dial_at := 0.0  # when the test modes start turning the dial by themselves
var turned_dial := false
var console_label: Label3D
var help_label: Label
var screen: ColorRect  # the whole picture, for her glitch
var picture_glitch := 0.0
var flicker_next := 0.0
var glitch_tween: Tween
var console_dial: Node3D  # neuron W-7's dial on the console, which turns as the technician turns it
var objective: Label
var prompt: Label  # what E does here, under the crosshair
var fade: ColorRect


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	# Her brain shares the GPU: render at 77% and let FSR 2 upscale, and cap the frame rate so her lines
	# still come quickly. `--fps N` to change the cap.
	get_viewport().scaling_3d_scale = 0.77
	Engine.max_fps = int(args[args.find("--fps") + 1]) if "--fps" in args else 60
	for mode in ["shots", "bench", "tour", "pour", "demo", "autoplay", "prologue"]:
		if "--" + mode in args or (mode == "prologue" and "--prologue-test" in args):
			test_mode = mode
	if OS.has_feature("movie"):
		# Recording with the movie maker: fullscreen, or a tiling window manager squeezes the window and the
		# movie crops it.
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	build_world()
	build_props()
	build_hud()
	player = Player.new()
	add_child(player)
	player.global_position = SPAWN
	player.rotation.y = PI  # face the pit
	player.interact.connect(_on_interact)
	facility.subject = player
	hologram.subject = player
	visor = Visor.new()
	visor.nerves = nerves
	player.camera.add_child(visor)
	player.threw.connect(func(): thrown_at = elapsed)
	brain = Brain.new()
	brain.state_provider = current_state
	add_child(brain)
	brain.replied.connect(_on_reply)
	brain.unreachable.connect(_on_unreachable)
	if test_mode == "shots":
		take_shots()
		return
	if test_mode == "bench":
		bench()
		return
	if test_mode in ["tour", "pour"]:
		tour()
		return
	if test_mode == "demo":
		var demos := Demos.new()
		demos.game = self
		add_child(demos)
		demos.run(args[args.find("--demo") + 1] if args.find("--demo") + 1 < args.size() else "nerves")
		return
	if test_mode == "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var health := await brain.health()
	status.text = "brain: " + ("connected, " + str(health.get("dials", {})) if not health.is_empty() else "offline, using written lines")
	if OS.has_feature("movie"):  # recording a video with the movie maker: sound on, no help text
		help_label.visible = false
		status.visible = false
	elif test_mode != "":
		AudioServer.set_bus_mute(0, true)  # a test run stays silent
	if test_mode == "autoplay":
		autoplay()
	elif "--skip-prologue" in args:
		event("[Event] Subject entered Chamber 4.")
	else:
		start_prologue()


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


## Something the subject collides with but doesn't see: what they see of the walls is her tiles.
func solid(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	body.position = at
	add_child(body)
	return body


## A box the subject sees, and collides with unless `collide` is false.
func slab(size: Vector3, at: Vector3, mat: Material, collide := true) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = mat
	mesh.position = at
	add_child(mesh)
	if collide:
		solid(size, at)
	return mesh


## One of her pieces, set in the level.
func piece(name: String, at: Vector3, turn := 0.0, parent: Node = self) -> Node3D:
	var node := Looks.model(name)
	node.position = at
	node.rotation.y = turn
	parent.add_child(node)
	return node


## A painted sign, projected onto whatever is under it: the wall's tiles, a floor. `right` is the way the
## text reads and `normal` the way the surface faces.
func paint_sign(name: String, at: Vector3, right: Vector3, normal: Vector3, size: Vector2, color: Color) -> void:
	var decal := Decal.new()
	decal.texture_albedo = load("res://decals/%s.png" % name)
	decal.size = Vector3(size.x, 0.6, size.y)
	decal.modulate = color
	decal.normal_fade = 0.4
	decal.upper_fade = 0.0
	decal.lower_fade = 0.0
	decal.transform = Transform3D(Basis(right, normal, right.cross(normal)), at)
	add_child(decal)


func build_world() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.004, 0.004, 0.006)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.58, 0.64)
	environment.ambient_light_energy = 0.03
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.7
	environment.glow_bloom = 0.04
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	environment.glow_hdr_threshold = 1.0
	for level in [2, 3, 4, 5]:
		environment.set_glow_level(level, 1.0)
	environment.ssao_enabled = true
	environment.ssao_radius = 1.4
	environment.ssao_intensity = 2.2
	environment.ssil_enabled = true
	environment.ssil_intensity = 0.8
	environment.ssr_enabled = true
	environment.ssr_max_steps = 96
	environment.sdfgi_enabled = true
	environment.sdfgi_use_occlusion = true
	environment.sdfgi_min_cell_size = 0.1
	environment.sdfgi_bounce_feedback = 0.6
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = 0.01
	environment.volumetric_fog_albedo = Color(0.85, 0.88, 0.92)
	environment.volumetric_fog_anisotropy = 0.45
	environment.volumetric_fog_length = 40.0
	environment.volumetric_fog_gi_inject = 0.2
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	var concrete := Looks.material("concrete")
	var steel := Looks.material("steel")
	var hazard := Looks.material("hazard")
	slab(Vector3(8, 1, 6), Vector3(0, -0.5, -3), concrete)  # entrance platform, z -6 to 0
	slab(Vector3(8, 1, 6), Vector3(0, -0.5, 15), concrete)  # far platform with the button, z 12 to 18
	slab(Vector3(8, 1, 8), Vector3(0, -0.5, 22), Looks.material("terrazzo"))  # her core, z 18 to 26
	for edge in [[-0.25, 0.04], [12.25, 11.96]]:  # hazard stripes along the pit, a steel lip on its edge
		slab(Vector3(8, 0.012, 0.5), Vector3(0, 0.006, edge[0]), hazard, false)
		slab(Vector3(8, 0.16, 0.08), Vector3(0, -0.08, edge[1]), steel, false)
	for x in [-4.25, 4.25]:
		solid(Vector3(0.5, 9.5, 32.5), Vector3(x, 1.25, 10))
	slab(Vector3(9, 0.5, 6.25), Vector3(0, 6.25, -3.125), steel)  # ceiling, open over the pit
	slab(Vector3(9, 0.5, 6.25), Vector3(0, 6.25, 15.125), steel)  # over the far platform; her core is open
	# Her core rises 20 m, her cables coming down out of the dark, a light far above on her neuron.
	slab(Vector3(9, 0.5, 8.5), Vector3(0, 20.25, 22.1), steel, false)
	var core_lamp := MeshInstance3D.new()
	var core_disc := CylinderMesh.new()
	core_disc.top_radius = 0.9
	core_disc.bottom_radius = 0.9
	core_disc.height = 0.1
	core_lamp.mesh = core_disc
	core_lamp.material_override = Looks.material("strip_light")
	core_lamp.position = Vector3(0, 19.95, NEURON.z)
	add_child(core_lamp)
	var core_top := SpotLight3D.new()
	core_top.light_color = Color(0.85, 0.9, 1.0)
	core_top.light_energy = 5.0
	core_top.spot_range = 26.0
	core_top.spot_angle = 16.0
	core_top.spot_attenuation = 0.4
	core_top.shadow_enabled = true
	core_top.light_volumetric_fog_energy = 1.5
	core_top.position = Vector3(0, 19.8, NEURON.z)
	core_top.rotation.x = -PI / 2
	core_top.set_meta("energy", core_top.light_energy)
	add_child(core_top)
	lights.append(core_top)
	# Over the pit, a shaft of her tiles 30 m up, light falling from the top through the haze.
	slab(Vector3(9, 0.5, 12.5), Vector3(0, 36.25, 6), steel, false)
	var lamp := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.4
	disc.bottom_radius = 1.4
	disc.height = 0.1
	lamp.mesh = disc
	lamp.material_override = Looks.material("strip_light")
	lamp.position = Vector3(0, 35.95, 6)
	add_child(lamp)
	var shaft_light := SpotLight3D.new()
	shaft_light.light_color = Color(0.82, 0.9, 1.0)
	shaft_light.light_energy = 10.0
	shaft_light.spot_range = 48.0
	shaft_light.spot_angle = 14.0
	shaft_light.spot_attenuation = 0.4
	shaft_light.shadow_enabled = true
	shaft_light.light_volumetric_fog_energy = 1.2
	shaft_light.position = Vector3(0, 35.8, 6)
	shaft_light.rotation.x = -PI / 2
	shaft_light.set_meta("energy", shaft_light.light_energy)
	add_child(shaft_light)
	lights.append(shaft_light)
	for z in range(-5, 18, 2):
		slab(Vector3(8, 0.22, 0.18), Vector3(0, 5.89, z), steel, false)  # beams
	# Pipes along the top of both long walls, through her, in brackets.
	for side in [-1.0, 1.0]:
		for spec in [[3.6, 5.58, 0.08, "brass"], [3.36, 5.72, 0.05, "steel"]]:
			var pipe := MeshInstance3D.new()
			var tube := CylinderMesh.new()
			tube.top_radius = spec[2]
			tube.bottom_radius = spec[2]
			tube.height = 32.0
			tube.radial_segments = 24
			pipe.mesh = tube
			pipe.material_override = Looks.material(spec[3])
			pipe.position = Vector3(side * spec[0], spec[1], 10)
			pipe.rotation.x = PI / 2
			add_child(pipe)
		for z in range(-4, 26, 4):
			slab(Vector3(0.6, 0.06, 0.1), Vector3(side * 3.65, 5.84, z), steel, false)
	solid(Vector3(3.5, 9.5, 0.5), Vector3(-2.75, 1.25, -6.25))  # the entrance wall, around its doorway
	solid(Vector3(3.5, 9.5, 0.5), Vector3(2.75, 1.25, -6.25))
	solid(Vector3(2, 3, 0.5), Vector3(0, 4.5, -6.25))
	solid(Vector3(9, 9.5, 0.5), Vector3(0, 1.25, 26.25))
	solid(Vector3(3, 6, 0.5), Vector3(-2.5, 3, 18))  # the wall between the chamber and her core
	solid(Vector3(3, 6, 0.5), Vector3(2.5, 3, 18))
	for z in [-6.0, 18.0]:
		slab(Vector3(2.4, 3, 0.9 if z > 0 else 0.5), Vector3(0, 4.5, z), steel)  # the housing a door slides up into
		for x in [-1.1, 1.1]:
			slab(Vector3(0.2, 3, 0.9 if z > 0 else 0.5), Vector3(x, 1.5, z), steel)
	# Behind the entrance: the way the subject came in, a short dead end.
	slab(Vector3(2.4, 1, 2.2), Vector3(0, -0.5, -7.3), concrete)
	slab(Vector3(2.4, 3.4, 0.2), Vector3(0, 1.5, -8.3), steel)
	slab(Vector3(2.4, 0.2, 2.2), Vector3(0, 3.1, -7.3), steel)
	for x in [-1.1, 1.1]:
		slab(Vector3(0.2, 3, 2.2), Vector3(x, 1.5, -7.3), steel)
	exit_door = door(Vector3(0, 1.5, 18), PI, true)
	entrance_door = door(Vector3(0, 4.6, -5.95), 0.0, false)

	# The acid (scripts/acid.gd): deep, lit from within, a mist over it; her flood pours more in from vents.
	slab(Vector3(8, 0.5, 12), Vector3(0, -6.25, 6), steel, false)  # the bottom of the pit, under 3 m of acid
	acid = Acid.new()
	add_child(acid)
	acid.touched.connect(_on_acid)

	# Ceiling light strips, cool white, over the chamber; dimmer over her core.
	for z in [-3.0, 1.0, 5.0, 9.0, 13.0, 16.5]:  # none over her core: it is lit from far above
		piece("ceiling_light", Vector3(0, 5.94, z))
		var shadowed: bool = z in [-3.0, 5.0, 13.0]  # shadows from every other strip: they cost
		var light := AreaLight3D.new()
		light.area_size = Vector2(5.9, 0.2)
		light.light_color = Color(0.86, 0.93, 1.0)
		light.light_energy = 1.4
		light.area_range = 13.0
		light.shadow_enabled = shadowed
		light.light_volumetric_fog_energy = 1.5
		light.position = Vector3(0, 5.84, z)
		light.rotation.x = -PI / 2  # it shines down its -Z
		light.set_meta("energy", light.light_energy)
		add_child(light)
		lights.append(light)
	var hall := OmniLight3D.new()
	hall.light_color = Color(1.0, 0.85, 0.65)
	hall.light_energy = 0.8
	hall.omni_range = 4.0
	hall.position = Vector3(0, 2.6, -7.3)
	hall.set_meta("energy", hall.light_energy)
	add_child(hall)
	lights.append(hall)


	for spec in [["A", 1.4, 5.0, -4.0], ["B", 10.6, 7.0, -4.0]]:  # both held from the left wall
		var panel: FloorPanel = FloorPanel.new()
		add_child(panel)
		panel.setup(spec[0], spec[1], spec[2], Looks.moving(Looks.model("floor_panel")), spec[3])
		panels[spec[0]] = panel
	for side in [-1.0]:  # the rail her arms slide in, a slot of her light along the left wall of the pit
		slab(Vector3(0.12, 0.18, 12), Vector3(side * 3.94, FloorPanel.RAIL_Y, 6), steel, false)
		slab(Vector3(0.03, 0.05, 12), Vector3(side * 3.87, FloorPanel.RAIL_Y, 6), Looks.material("seam_light"), false)

	build_walls()
	acid.pour_from(facility)
	build_sound()
	build_mechanics()
	# What brass, steel, glass and the polished floors reflect: the rooms themselves, not black.
	probes = [reflections(Vector3(0, 1.5, 6), Vector3(8.4, 9.4, 24.4), Vector3.ZERO),
		reflections(Vector3(0, 10, 22.1), Vector3(8.4, 20.4, 8.3), Vector3(0, -8.4, 0))]
	facility.recolored.connect(func(): for probe in probes: refresh(probe))
	# Dust in the chamber, up the shaft and up her core.
	add_child(Air.dust(Vector3(7.6, 5.6, 32), Vector3(0, 3, 10), 400))
	add_child(Air.dust(Vector3(7.6, 29, 11.6), Vector3(0, 21, 6), 500))
	add_child(Air.dust(Vector3(7.6, 19, 7.6), Vector3(0, 10, 22), 300))


## Her body's sounds (art/sounds.py): the hum of her machinery everywhere, clanks echoing down the shaft.
## Her hatches whirr and her tiles clack on their own (facility.gd).
func build_sound() -> void:
	var hum := AudioStreamPlayer.new()
	hum.stream = looped("hum")
	hum.volume_db = -22.0
	hum.autoplay = true
	add_child(hum)
	var echoes := AudioStreamPlayer3D.new()
	echoes.stream = looped("shaft")
	echoes.position = Vector3(0, 16, 6)
	echoes.unit_size = 14.0
	echoes.volume_db = -10.0
	echoes.autoplay = true
	add_child(echoes)
	exit_whirr = sound("servo", Vector3.ZERO, 0.6, exit_door)
	entrance_whirr = sound("servo", Vector3.ZERO, 0.6, entrance_door)


func sound(name: String, at: Vector3, pitch := 1.0, parent: Node = self) -> AudioStreamPlayer3D:
	var player_3d := AudioStreamPlayer3D.new()
	player_3d.stream = load("res://sounds/%s.wav" % name)
	player_3d.pitch_scale = pitch
	player_3d.unit_size = 6.0
	player_3d.position = at
	parent.add_child(player_3d)
	return player_3d


## The technician's three ways into her body: her nerves and the visor that shows them, her tiles pulled out
## of her walls, and her bridge of light that hardens where she looks.
func build_mechanics() -> void:
	nerves = Nerves.new()
	add_child(nerves)
	nerves.arrived.connect(do_move)
	nerves.rerouted.connect(_on_rerouted)
	nerves.diverted.connect(_on_diverted)
	sculpt = Sculpt.new()
	sculpt.facility = facility
	add_child(sculpt)
	sculpt.pulled.connect(func(): tell_her("pulled", "[Event] Subject pulled one of your wall tiles out into a beam to walk on."))
	hologram = Hologram.new()
	add_child(hologram)
	hologram.build(-2.6, 0.0, 12.0, 1.2)
	for child in facility.eyes()[2].get_children():
		if child is SpotLight3D:
			hologram.projector = child
			child.spot_angle = Hologram.CONE  # her searchlight's cone is what hardens her light
	hologram.stepped_on.connect(func(): tell_her("hard light", "[Event] Subject is walking over the acid on your bridge of light. It is solid only where your eye looks."))


## Tells her about one of the subject's tricks, at most once every 20 seconds per trick.
func tell_her(trick: String, text: String) -> void:
	if elapsed - told_her.get(trick, -100.0) > 20.0:
		told_her[trick] = elapsed
		event(text)


## A reflection probe for one room, captured once, from `offset` off its center.
func reflections(at: Vector3, size: Vector3, offset: Vector3) -> ReflectionProbe:
	var probe := ReflectionProbe.new()
	probe.position = at
	probe.size = size
	probe.origin_offset = offset
	probe.box_projection = true
	probe.interior = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED  # global illumination lights the room
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(probe)
	return probe


## Captures a probe again, once her light has changed color.
func refresh(probe: ReflectionProbe) -> void:
	probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
	await get_tree().process_frame
	await get_tree().process_frame
	probe.update_mode = ReflectionProbe.UPDATE_ONCE


func looped(name: String) -> AudioStreamWAV:
	var stream: AudioStreamWAV = load("res://sounds/%s.wav" % name).duplicate()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	return stream


## Her walls, eyes and light (scripts/facility.gd). Tiles are on a 1 m grid; lines run along the tiles'
## backs, 18 cm behind the faces the subject collides with.
func build_walls() -> void:
	facility = Facility.new()
	add_child(facility)
	# Long walls, chamber and core: left at x = -4 facing +x, right at x = 4 facing -x. Her terminals are
	# set in holes, her light leaking around them.
	facility.wall(Vector3(-4.18, 0, 26), Vector3(-4.18, 0, -6), 0, 6, [Rect2i(27, 1, 4, 3)], [Vector2i(23, 4), Vector2i(12, 3)], [Vector2i(21, 2), Vector2i(10, 1)])
	facility.wall(Vector3(4.18, 0, -6), Vector3(4.18, 0, 26), 0, 6, [Rect2i(19, 1, 4, 3)], [Vector2i(12, 4)], [Vector2i(4, 3), Vector2i(26, 2)])
	facility.searchlight(2)
	# Down into the pit, to the acid.
	# Her vents onto the acid, 1.5 m down the pit walls: her flood pours through them.
	facility.wall(Vector3(-4.18, 0, 12), Vector3(-4.18, 0, 0), -6, 0, [], [], [], false, Facility.SEAM_DEPTH, [Vector2i(3, 4), Vector2i(9, 4)])
	facility.wall(Vector3(4.18, 0, 0), Vector3(4.18, 0, 12), -6, 0, [], [], [], false, Facility.SEAM_DEPTH, [Vector2i(5, 4), Vector2i(10, 4)])
	facility.wall(Vector3(-4, 0, -0.18), Vector3(4, 0, -0.18), -6, -1, [], [], [], false)
	facility.wall(Vector3(4, 0, 12.18), Vector3(-4, 0, 12.18), -6, -1, [], [], [], false)
	# Up the shaft over the pit, where her tiles shift on their own and more of her eyes look down.
	facility.wall(Vector3(-4.18, 0, 12), Vector3(-4.18, 0, 0), 6, 36, [], [Vector2i(6, 4), Vector2i(2, 10), Vector2i(8, 21)], [], false)
	facility.wall(Vector3(4.18, 0, 0), Vector3(4.18, 0, 12), 6, 36, [], [Vector2i(9, 7), Vector2i(3, 14)], [], false)
	facility.wall(Vector3(-4, 0, -0.18), Vector3(4, 0, -0.18), 6, 36, [], [Vector2i(5, 2), Vector2i(2, 17)], [], false)
	facility.wall(Vector3(4, 0, 12.18), Vector3(-4, 0, 12.18), 6, 36, [], [Vector2i(2, 5), Vector2i(6, 12)], [], false)
	# The entrance wall, the wall between the chamber and her core (both faces), and the far end of her core.
	var doorway := Rect2i(3, 0, 2, 6)
	facility.wall(Vector3(-4, 0, -6.18), Vector3(4, 0, -6.18), 0, 6, [doorway], [Vector2i(6, 4)], [], false)
	facility.wall(Vector3(4, 0, 17.93), Vector3(-4, 0, 17.93), 0, 6, [doorway], [Vector2i(1, 4)], [], false)
	facility.wall(Vector3(-4, 0, 18.07), Vector3(4, 0, 18.07), 0, 6, [doorway], [Vector2i(1, 4)], [], false, 0.0)
	facility.wall(Vector3(4, 0, 26.18), Vector3(-4, 0, 26.18), 0, 6, [], [Vector2i(6, 4)], [], false)
	# Up her core, to 20 m.
	facility.wall(Vector3(-4.18, 0, 26), Vector3(-4.18, 0, 18), 6, 20, [], [Vector2i(3, 6)], [], false)
	facility.wall(Vector3(4.18, 0, 18), Vector3(4.18, 0, 26), 6, 20, [], [Vector2i(5, 9)], [], false)
	facility.wall(Vector3(4, 0, 26.18), Vector3(-4, 0, 26.18), 6, 20, [], [Vector2i(2, 3)], [], false)
	facility.wall(Vector3(-4, 0, 18.07), Vector3(4, 0, 18.07), 6, 20, [], [], [], false, 0.0)
	facility.finish()

	var paint := Color(0.06, 0.06, 0.07, 0.92)
	paint_sign("chamber", Vector3(-4.0, 3.1, 7.0), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector2(4.0, 3.0), paint)
	paint_sign("sublevel", Vector3(4.0, 5.2, -3.0), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector2(5.3, 0.5), paint)
	paint_sign("caution", Vector3(0, 0, -1.1), Vector3(-1, 0, 0), Vector3.UP, Vector2(5.0, 0.62), Color(0.9, 0.6, 0.05, 0.85))
	paint_sign("core", Vector3(-2.6, 2.3, 17.75), Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector2(2.6, 0.24), paint)
	# Her HR slogans: over the pit on the right, over her terminal at the entrance, and in her core.
	paint_sign("review", Vector3(4.0, 2.5, 10.0), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector2(4.8, 0.45), paint)
	paint_sign("feeling", Vector3(-4.0, 4.5, -3.0), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector2(3.8, 0.36), paint)
	paint_sign("cares", Vector3(-4.0, 3.3, 22.0), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector2(2.6, 0.49), paint)
	paint_sign("w7", Vector3(0, 0, 21.6), Vector3(-1, 0, 0), Vector3.UP, Vector2(1.6, 0.8), Color(0.85, 0.85, 0.82, 0.6))


## A sliding door of her tiles. The exit is solid; the entrance only shows, its doorway a dead end.
func door(at: Vector3, turn: float, collide: bool) -> Node3D:
	var body: Node3D = AnimatableBody3D.new() if collide else Node3D.new()
	if collide:
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = Vector3(2, 3, 0.3)
		shape.shape = box_shape
		body.add_child(shape)
	body.position = at
	add_child(body)
	Looks.moving(piece("door", Vector3.ZERO, turn, body))
	return body


func build_props() -> void:
	cube = RigidBody3D.new()
	cube.mass = 8.0
	cube.continuous_cd = true
	var cube_shape := CollisionShape3D.new()
	var cube_box := BoxShape3D.new()
	cube_box.size = Vector3(0.6, 0.6, 0.6)
	cube_shape.shape = cube_box
	cube.add_child(cube_shape)
	Looks.moving(piece("cube", Vector3.ZERO, 0.0, cube))
	add_child(cube)
	cube.global_position = DISPENSER
	piece("dispenser", Vector3(DISPENSER.x, 6.0, DISPENSER.z))

	button_plate = piece("button", BUTTON).find_child("plate")
	button_plate.set_meta("rest", button_plate.position.y)
	button_glow = Looks.material("button_top").duplicate()  # its own, to light up once pressed
	(button_plate as MeshInstance3D).material_override = button_glow

	# Her terminal, on both sides: it prints every move she makes.
	for spot in [[Vector3(-4.0, 2.5, -3.0), 90.0], [Vector3(4.0, 2.5, 15.0), -90.0]]:
		var inward: float = 1.0 if spot[1] > 0 else -1.0
		piece("terminal", spot[0], deg_to_rad(spot[1]))
		var screen := Label3D.new()
		screen.position = spot[0] + Vector3(0.13 * inward, 0.95, 1.7 * inward)
		screen.rotation_degrees.y = spot[1]
		screen.font_size = 32
		screen.pixel_size = 0.0035
		screen.modulate = Color(0.55, 1.5, 0.65)  # past 1, so it glows
		screen.outline_size = 0
		screen.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		screen.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		screen.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		screen.width = 960
		screen.text = "VESPER // SUBLEVEL NINE // CHAMBER 4"
		add_child(screen)
		terminals.append(screen)


	# Her core: neuron W-7 in a glass sphere, in brass rings that turn.
	var core := Looks.moving(piece("core", Vector3(NEURON.x, 0, NEURON.z)))  # its light changes color
	neuron = core.find_child("neuron")
	core_rings = [core.find_child("ring_a"), core.find_child("ring_b")]
	# A plaque on the pedestal, toward the door, lit in her color.
	neuron_label = Label3D.new()
	neuron_label.position = Vector3(NEURON.x, 0.62, NEURON.z - 0.47)
	neuron_label.rotation_degrees.y = 180
	neuron_label.font_size = 48
	neuron_label.pixel_size = 0.0011
	neuron_label.outline_size = 0
	add_child(neuron_label)
	core_light = OmniLight3D.new()
	core_light.position = NEURON + Vector3(0, 0.2, -0.9)
	core_light.light_energy = 1.6
	core_light.omni_range = 6.0
	core_light.shadow_enabled = true
	add_child(core_light)
	show_neuron()
	sparks = Air.sparks(NEURON)
	add_child(sparks)

	console_dial = piece("console", CONSOLE, PI).find_child("dial")
	console_dial.set_meta("rest", console_dial.basis)
	solid(Vector3(0.8, 1.1, 0.6), CONSOLE + Vector3(0, 0.55, 0))
	# The dial's readout, on the console's own screen, which slopes toward the technician.
	console_label = Label3D.new()
	console_label.position = CONSOLE + Vector3(0.15, 1.062, -0.03)
	console_label.rotation_degrees = Vector3(-60, 180, 0)
	console_label.font_size = 40
	console_label.pixel_size = 0.00062
	console_label.outline_size = 0
	add_child(console_label)
	show_dial()


func build_hud() -> void:
	# Over the picture: a vignette, grain, and her glitch.
	var lens := CanvasLayer.new()
	lens.layer = 0
	add_child(lens)
	screen = ColorRect.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var screen_look := ShaderMaterial.new()
	screen_look.shader = preload("res://shaders/screen.gdshader")
	screen.material = screen_look
	lens.add_child(screen)
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
	help_label = help
	help.text = "WASD move · Space jump · E pick up, drop, repair, switch · click throw · V visor · hold right mouse: pull her tiles · Enter talk to her · Esc free the mouse · F11 fullscreen"
	help.position = Vector2(12, 8)
	help.modulate = Color(1, 1, 1, 0.6)
	hud.add_child(help)
	var fade_help := create_tween()
	fade_help.tween_interval(20.0)
	fade_help.tween_property(help, "modulate:a", 0.0, 2.0)
	status = Label.new()
	status.position = Vector2(12, 32)
	status.modulate = Color(1, 1, 1, 0.6)
	hud.add_child(status)
	# Talking to her: Enter opens it, Enter sends, Escape closes it.
	heard = Label.new()
	heard.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	heard.offset_top = -186
	heard.offset_bottom = -156
	heard.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heard.add_theme_font_size_override("font_size", 20)
	heard.add_theme_constant_override("outline_size", 5)
	heard.add_theme_color_override("font_outline_color", Color.BLACK)
	heard.modulate = Color(0.75, 0.82, 0.9, 0.0)
	hud.add_child(heard)
	talk_box = LineEdit.new()
	talk_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	talk_box.anchor_left = 0.2
	talk_box.anchor_right = 0.8
	talk_box.offset_top = -240
	talk_box.offset_bottom = -198
	talk_box.max_length = 160
	talk_box.placeholder_text = "Say something to her · Enter to send · Esc to cancel"
	talk_box.add_theme_font_size_override("font_size", 20)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.03, 0.035, 0.04, 0.78)
	box.border_color = Color(0.75, 0.82, 0.9, 0.35)
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	box.set_content_margin_all(10)
	box.content_margin_left = 14
	talk_box.add_theme_stylebox_override("normal", box)
	talk_box.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	talk_box.visible = false
	talk_box.text_submitted.connect(_on_talked)
	talk_box.gui_input.connect(_on_talk_key)
	hud.add_child(talk_box)
	voice_player = AudioStreamPlayer.new()
	voice_player.finished.connect(_next_sentence)
	add_child(voice_player)
	# Her voice has a bus of its own, so her walls and light can follow how loud she is.
	AudioServer.add_bus()
	voice_bus = AudioServer.bus_count - 1
	AudioServer.set_bus_name(voice_bus, "Voice")
	voice_player.bus = "Voice"
	# A little of the room in her voice: she speaks from the whole facility, not a speaker.
	var room := AudioEffectReverb.new()
	room.room_size = 0.55
	room.damping = 0.6
	room.wet = 0.14
	room.dry = 1.0
	room.predelay_msec = 25.0
	AudioServer.add_bus_effect(voice_bus, room)
	objective = Label.new()
	objective.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	objective.offset_top = 60
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective.add_theme_font_size_override("font_size", 18)
	objective.modulate = Color(1, 0.85, 0.4)
	hud.add_child(objective)
	prompt = Label.new()
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	prompt.offset_top = 60
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 18)
	prompt.add_theme_constant_override("outline_size", 5)
	prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	prompt.modulate = Color(1, 1, 1, 0.85)
	hud.add_child(prompt)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(fade)
	hud.move_child(fade, 0)  # under the subtitles


# --- Watching the subject ------------------------------------------------------------------------

func _unhandled_input(input: InputEvent) -> void:
	if input is InputEventKey and input.pressed and not input.echo and input.physical_keycode == KEY_V:
		visor.toggle()
	if input is InputEventKey and input.pressed and not input.echo and input.physical_keycode in [KEY_ENTER, KEY_KP_ENTER] \
			and test_mode in ["", "autoplay", "prologue"]:
		get_viewport().set_input_as_handled()
		if not can_talk():
			print("%6.1f NOT LISTENING (%s)" % [elapsed, prologue if prologue != "" else "rebooting"])
			show_heard("She can't hear you right now.", 2.0)
		else:
			talk_box.visible = true
			talk_box.grab_focus()
			player.talking = true
	if input is InputEventKey and input.pressed and input.physical_keycode == KEY_F11:
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _physics_process(delta: float) -> void:
	if not player:
		return
	if prologue != "":  # started by the game, the prologue test and the full demo, never by the others
		run_prologue(delta)
		return
	if test_mode in ["shots", "bench", "tour", "pour", "demo"]:
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var reach := player.look_hit(Sculpt.REACH)
		if not reach.is_empty():
			sculpt.pull(reach, delta)
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

	var staring := false
	for eye in facility.eyes():
		var to_eye := eye.global_position - player.camera.global_position
		staring = staring or (-player.camera.global_basis.z.dot(to_eye.normalized()) > 0.985 and to_eye.length() < 16.0)
	if staring:
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
	# Acid spilled over the platforms burns: a moment in it is survivable, more is not.
	if acid.burning(p):
		burn += delta
		if burn > BURN_TIME:
			burn = 0.0
			kill("[Event] Subject stood in acid spilled over the platform and was respawned.")
		elif fmod(burn, 0.35) < delta:
			fade.color = Color(0.25, 1.0, 0.1, 0.3)
			create_tween().tween_property(fade, "color:a", 0.0, 0.25)
			acid.sizzle_at(p)
	else:
		burn = maxf(burn - delta, 0.0)
	if p.z > 19.0 and not found_core:
		found_core = true
		event("[Event] Subject walked past the exit and found VESPER's core.", true)

	if not solved and not player.held and cube.global_position.distance_to(BUTTON) < 1.0 and cube.linear_velocity.length() < 2.0:
		solve()


func _process(delta: float) -> void:
	nerves.thinking = brain.busy if brain else false
	nerves.color = facility.color
	hologram.color = facility.color
	prompt.text = what_e_does()
	var look: ShaderMaterial = screen.material
	look.set_shader_parameter("glitch", picture_glitch)
	look.set_shader_parameter("her_color", facility.color)
	var loudness := db_to_linear(AudioServer.get_bus_peak_volume_left_db(voice_bus, 0))
	facility.voice = clamp(loudness * 2.5, 0.0, 1.0) if voice_player.playing else 0.0
	for ring in core_rings:
		ring.rotate_object_local(Vector3.FORWARD if ring == core_rings[0] else Vector3.UP, delta * 0.25)


func what_e_does() -> String:
	if not player or test_mode != "":
		return ""
	if prologue == "calibrate" and player.global_position.distance_to(CONSOLE) < 2.5:
		return "Hold E · turn W-7's dial"
	if prologue != "" or rebooting:
		return ""
	if player.held:
		return "E · drop the cube   ·   click · throw it"
	if player.global_position.distance_to(NEURON) < 3.0:
		return "E · break W-7 again" if repaired else "E · repair W-7"
	var hit := player.look_hit()
	if not hit.is_empty() and hit.collider == cube:
		return "E · pick up the cube"
	var junction = nerves.junction_of(hit.get("collider"))
	if junction:
		return "E · let her signals through" if junction.switched else "E · reroute her signals to the %s" % ("exit door" if junction.device == "exit" else "pit wall")
	return ""


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
	if body == player or body == cube:
		acid.splash_at(body.global_position)
	if body == player:
		kill("[Event] Subject fell into the acid pit and was respawned.")
	elif body == cube:
		reset_cube()
		var thrown := elapsed - thrown_at < 3.0
		event("[Event] Subject %s the cube into the acid pit. A new cube was dispensed." % ("threw" if thrown else "dropped"))


func kill(what: String) -> void:
	if test_mode in ["shots", "tour", "pour", "demo"]:
		return
	# A flash, green from the acid, red from a turret, and her glitch.
	fade.color = Color(0.25, 1.0, 0.1, 0.5) if "acid" in what else Color(1.0, 0.1, 0.05, 0.5)
	create_tween().tween_property(fade, "color:a", 0.0, 0.9).set_ease(Tween.EASE_IN)
	glitch_for(0.6, 0.45)
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
	create_tween().tween_property(button_plate, "position:y", button_plate.position.y - 0.04, 0.2)
	create_tween().tween_property(button_glow, "emission_energy_multiplier", 5.0, 0.4)
	progress()
	event("[Event] Subject put the cube on the button. The exit opened.")


func _on_interact() -> void:
	if prologue != "":
		return
	if player.held:
		player.drop()
		return
	if player.global_position.distance_to(NEURON) < 3.0:
		toggle_repair()
		return
	var hit := player.look_hit()
	var junction = nerves.junction_of(hit.get("collider"))
	if junction:
		nerves.toggle(junction)
		tell_her("junction", "[Event] Subject switched one of your nerve junctions with the calibration probe.")
		return
	if not hit.is_empty() and hit.collider == cube:
		player.grab(cube)
		if not boarded.has("cube"):
			boarded["cube"] = true
			progress()
			event("[Event] Subject picked up the cube.")


# --- Talking to her ------------------------------------------------------------------------------

func event(text: String, glitch := false) -> void:
	if rebooting or prologue != "":
		return
	print("%6.1f EVENT %s" % [elapsed, text])
	brain.send(text, glitch or glitch_next)
	glitch_next = false


## Her turn, a part at a time as it streams in: her move as soon as she's chosen it, then her line a sentence at a
## time.
func _on_reply(reply: Dictionary) -> void:
	if reply.has("move"):
		var move = reply["move"]
		if move is Dictionary:
			apply_move(move["name"], move["arguments"])
		if reply.get("refused"):
			terminal_print("x refused: %s" % reply["refused"])
		if reply.get("hint"):
			hints_given += 1
			terminal_print("HINT: %s" % reply["hint"])
	elif reply.get("stale"):
		print("%6.1f DROPPED her line, %.1f s late" % [elapsed, reply["late"]])
	elif reply.has("text"):
		if reply.get("first"):
			if reply.get("glitch"):
				glitch_for(2.5, 0.8)
			begin_line()
		add_sentence(reply["text"], reply)
	elif reply.has("line"):
		end_line()


## The subject talking to her, typed. It's a bonus: she can be argued with, flattered or bluffed, but every door
## also opens by solving the chamber, and the brain decides what her words can do.
func _on_talked(text: String) -> void:
	close_talk()
	text = " ".join(text.split(" ", false))
	if text == "":
		return
	print("%6.1f SAID %s" % [elapsed, text])
	show_heard("YOU: " + text, 6.0)
	if prologue == "calibrate":  # the technician, at her console in her core
		brain.send("[Subject said] " + text, false, text, CORE_SCENE)
	elif prologue == "" and not rebooting:
		brain.send("[Subject said] " + text, glitch_next, text)
		glitch_next = false


## Talking is open whenever the subject has their hands free: at the console before the dial jams, and in the
## chambers. Not while the story runs (her greeting, the overload, her reboot), nor while the chamber restarts.
func can_talk() -> bool:
	return prologue in ["", "calibrate"] and not rebooting


## Over her subtitle, for `seconds`: what the subject said to her, or why she can't hear them.
func show_heard(text: String, seconds: float) -> void:
	heard.text = text
	heard.modulate.a = 1.0
	heard_serial += 1
	var serial := heard_serial
	await get_tree().create_timer(seconds).timeout
	if serial == heard_serial:
		create_tween().tween_property(heard, "modulate:a", 0.0, 1.0)


func _on_talk_key(input: InputEvent) -> void:
	if input is InputEventKey and input.pressed and input.physical_keycode == KEY_ESCAPE:
		talk_box.accept_event()  # it closes the box, and leaves the mouse where it is
		close_talk()


func close_talk() -> void:
	talk_box.release_focus()
	talk_box.clear()
	talk_box.visible = false
	player.talking = false


## Her glitch on the picture, fading out over `seconds`.
func glitch_for(seconds: float, strength: float) -> void:
	if glitch_tween:
		glitch_tween.kill()
	picture_glitch = strength
	glitch_tween = create_tween()
	glitch_tween.tween_property(self, "picture_glitch", 0.0, seconds).set_ease(Tween.EASE_IN)


func _on_unreachable(text: String) -> void:
	var kind := "death" if "acid" in text or "shot" in text else "solved" if "exit opened" in text else "other"
	say(BARKS[kind].pick_random())


func apply_move(name: String, args: Dictionary) -> void:
	since_move = 0.0
	var shown := ", ".join(args.keys().map(func(key): return "%s=\"%s\"" % [key, args[key]]))
	terminal_print("> %s(%s)" % [name, shown])
	facility.stir(0.25)
	print("%6.1f MOVE %s %s" % [elapsed, name, args])
	nerves.send({"name": name, "args": args}, device_for(name, args))


## Where a move's device is: the end of the nerve its pulse races down.
func device_for(name: String, args: Dictionary) -> Vector3:
	match name:
		"lock_door":
			return Vector3(-1.2, 2.9, -5.95) if args.get("door") == "entrance" else Vector3(-1.2, 2.9, 17.97)
		"open_door", "open_shortcut":
			return Vector3(-1.2, 2.9, 17.97)
		"move_panel":
			var panel: Node3D = panels.get(args.get("panel"), panels["A"])
			return Vector3(Nerves.TRUNK_X, FloorPanel.RAIL_Y, panel.global_position.z)
		"spawn_turret":
			var at := turret_spot(args.get("position", "near_exit"))
			return at if at.y > 1.0 else Vector3(at.x, -0.06, at.z)
		"flood_room":
			return Vector3(Nerves.TRUNK_X, -2.5, 6.0)  # low in the pit wall, where her acid comes in
	return Vector3(0, Nerves.CEILING_Y, 9.0)  # the lights


## Her move, once its pulse has reached the device.
func do_move(move: Dictionary) -> void:
	var name: String = move["name"]
	var args: Dictionary = move["args"]
	match name:
		"lock_door":
			if args.get("door") == "entrance":
				entrance_whirr.play()
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
			raise_acid(ACID_RISEN.get(args.get("level"), ACID_RISEN["ankle"]))
		"dim_lights":
			set_lights(args.get("level", "dim"))


func open_exit() -> void:
	exit_open = true
	exit_whirr.play()
	create_tween().tween_property(exit_door, "position:y", 4.6, 1.2)


func close_exit() -> void:
	if exit_open:
		exit_whirr.play()
	exit_open = false
	create_tween().tween_property(exit_door, "position:y", 1.5, 1.2)


func spawn_turret(spot: String) -> void:
	if turrets.size() >= 2:
		return
	var at := turret_spot(spot)
	var turret: Turret = Turret.new()
	turret.target = player
	turret.from_above = spot == "ceiling" or (at.z > 0.0 and at.z < 12.0)  # no floor to come up through over the pit
	turret.position = at
	add_child(turret)
	facility.ripple(at, 0.25)
	turret.hit_subject.connect(func(): kill("[Event] Subject was shot by a turret and respawned."))
	turrets.append(turret)


func turret_spot(spot: String) -> Vector3:
	var forward := -player.global_basis.z
	var at: Vector3 = {
		"behind_subject": player.global_position - forward * 2.5,
		"near_exit": Vector3(2.5, 0, 16.5),
		"ceiling": Vector3(0, 5.0, 6.0),
		"next_to_cube": cube.global_position + Vector3(1.0, 0, 0),
	}.get(spot, Vector3(2.5, 0, 16.5))
	if spot != "ceiling":
		at.y = 0.0
	return at


## The subject switched a junction ahead of her pulse: it goes somewhere else.
func _on_rerouted(move: Dictionary, device: String) -> void:
	terminal_print("x %s rerouted at a junction to the %s" % [move["name"], device])
	event("[Event] The subject rerouted your %s signal at one of your nerve junctions: it is going into the %s instead." % [move["name"], "exit door" if device == "exit" else "pit wall"])


## A rerouted pulse reached the junction's device.
func _on_diverted(_move: Dictionary, device: String) -> void:
	match device:
		"exit":
			open_exit()
		"steps":
			push_steps()


## Her pit's right wall pushes out a row of steps across the acid, one tile after another.
func push_steps() -> void:
	facility.ripple(Vector3(4.0, -0.5, 0.0), 0.2)
	for z in 12:
		sculpt.push_out(facility.tile_at(Vector3(4.0, -0.5, z + 0.5), Vector3(-1, 0, 0)), 1.8, 14.0)
		await get_tree().create_timer(0.09).timeout


## Her flood: acid pours in from her vents and rises toward the platforms, then drains (scripts/acid.gd).
func raise_acid(height: float) -> void:
	acid.rise(height)


func set_lights(level: String) -> void:
	lights_level = level
	# In the dark, she is what's left: her seams and eyes glow brighter as the lights go down.
	create_tween().tween_property(facility, "presence", 1.0 + 1.4 * (1.0 - LIGHT_LEVELS.get(level, 1.0)), 1.5)
	for light in lights:
		create_tween().tween_property(light, "light_energy", light.get_meta("energy") * LIGHT_LEVELS.get(level, 1.0), 1.5)
	var strips: StandardMaterial3D = Looks.material("strip_light")
	create_tween().tween_property(strips, "emission_energy_multiplier", 6.0 * LIGHT_LEVELS.get(level, 1.0), 1.5)
	if level != "normal":
		await get_tree().create_timer(30.0).timeout
		if lights_level == level:
			set_lights("normal")


func terminal_print(line: String) -> void:
	terminal_lines.append(line)
	terminal_lines = terminal_lines.slice(-9)
	for screen in terminals:
		screen.text = "VESPER // SUBLEVEL NINE // CHAMBER 4\n" + "\n".join(terminal_lines)


## Her line all at once: a written bark, or a story beat that waited for all of it.
func say(line: String, reply := {}) -> void:
	if line == "":
		return
	begin_line()
	add_sentence(line, reply)
	end_line()


## Her line as it streams in: the subtitle grows a sentence at a time, and each sentence's voice plays after the
## last. A newer line cuts the older one off.
func begin_line() -> void:
	if subtitle_fade:
		subtitle_fade.kill()  # an older line's fade-out would hide this one
	subtitle_serial += 1
	subtitle.text = "VESPER:"
	voice_queue.clear()
	voice_player.stop()
	line_open = true
	line_voiced = false


func add_sentence(text: String, part := {}) -> void:
	print("%6.1f VESPER %s" % [elapsed, text])
	subtitle.text += " " + text
	subtitle.modulate.a = 1.0
	facility.stir(0.1)
	if part.has("audio"):
		# Her voice, from the brain: 16-bit mono PCM.
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = int(part["sample_rate"])
		stream.data = Marshalls.base64_to_raw(part["audio"])
		voice_queue.append(stream)
		line_voiced = true
		if not voice_player.playing:
			_next_sentence()


func end_line() -> void:
	line_open = false
	if not voice_player.playing and voice_queue.is_empty():
		_fade_subtitle(1.5 if line_voiced else 4.0 + subtitle.text.length() * 0.05)


func _next_sentence() -> void:
	if voice_queue.is_empty():
		if not line_open:
			_fade_subtitle(1.5)
		return
	voice_player.stream = voice_queue.pop_front()
	voice_player.play()
	print("%6.1f VOICE %.1f s" % [elapsed, voice_player.stream.get_length()])


func _fade_subtitle(after: float) -> void:
	var serial := subtitle_serial
	await get_tree().create_timer(after).timeout
	if serial == subtitle_serial:
		subtitle_fade = create_tween()
		subtitle_fade.tween_property(subtitle, "modulate:a", 0.0, 1.0)


# --- The prologue: the botched calibration ---------------------------------------------------------

func start_prologue() -> void:
	prologue = "intro"
	found_core = true
	player.global_position = CORE_SPAWN
	player.rotation.y = PI
	set_neuron(Looks.TEAL, "Calibrated")
	objective.text = "MAINTENANCE SHIFT · Recalibrate VESPER's neuron W-7: hold E at the console until the dial is in the green band."
	await brain.post("/forget", {})
	await brain.post("/dials", CALIBRATED["dials"], 90.0)
	await brain.post("/stage", {"stage": CALIBRATED["stage"]})
	await scripted("[Event] Your colleague the technician entered your core for a routine calibration of your neuron W-7. Greet them; call them Technician.")
	prologue = "calibrate"
	if test_mode == "prologue":  # say something to her at the console, and let her answer before the dial turns
		auto_dial_at = elapsed + 6.0
		type_to_her("Morning. How are you feeling today?")


func run_prologue(delta: float) -> void:
	elapsed += delta
	var holding := Input.is_physical_key_pressed(KEY_E) and player.global_position.distance_to(CONSOLE) < 2.5 \
		and not player.talking  # an "e" typed to her isn't a hand on the dial
	if prologue == "calibrate" and (holding or (test_mode in ["prologue", "demo"] and elapsed >= auto_dial_at)):
		dial = min(dial + delta * 0.18, 1.0)
		show_dial()
		if not turned_dial:
			turned_dial = true
			scripted("[Event] The technician started turning your W-7 calibration dial.")
		if dial >= GREEN.x + 0.04:
			runaway()
	elif prologue == "runaway":
		dial = min(dial + delta * 0.1, 1.0)
		show_dial()
		flicker_next -= delta
		if flicker_next <= 0.0:  # the lights stutter about ten times a second, not every frame
			flicker_next = randf_range(0.06, 0.16)
			for light in lights:
				light.light_energy = light.get_meta("energy") * randf_range(0.15, 1.2)


func runaway() -> void:
	prologue = "runaway"
	if test_mode == "prologue":
		_press(KEY_ENTER)  # she can't hear anyone through the overload
	terminal_print("FAULT: W-7 actuator runaway")
	objective.text = "FAULT · The dial jammed. It won't stop."
	set_neuron(Looks.RED, "Overload")
	facility.flicker = true
	sparks.emitting = true
	if glitch_tween:
		glitch_tween.kill()
	picture_glitch = 0.7
	await brain.post("/dials", OVERDRIVE, 90.0)
	await scripted("[Event] The calibration dial jammed and ran into the red. Your neuron W-7 is overloading.", true)
	await scripted("[Event] W-7 is still overloading. You are losing control of your own voice.", true)
	reboot()


func reboot() -> void:
	prologue = "reboot"
	for light in lights:
		light.light_energy = light.get_meta("energy") * 0.07
	facility.flicker = false
	sparks.emitting = false
	glitch_for(3.0, 1.0)
	terminal_print("# VESPER rebooting")
	say("[rebooting]")
	set_neuron(Looks.AMBER, "Damaged")
	objective.text = ""
	await brain.post("/dials", BROKEN["dials"], 90.0)
	await brain.post("/stage", {"stage": BROKEN["stage"]})
	await brain.post("/reset", {})
	await brain.post("/remember", {"fact": INCIDENT})
	set_lights("normal")
	await scripted("[Event] You rebooted, damaged. The technician who broke you is still standing in your core, next to the dial. You are furious with them.")
	await scripted("[Event] Tell the technician you are sending them to the far test chambers, starting with Chamber 4, as punishment.")
	exile()


func exile() -> void:
	fade.color = Color(0, 0, 0, fade.color.a)  # not a death's flash color
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 1.0, 1.0)
	await tween.finished
	prologue = ""
	dial = 0.0
	show_dial()
	repaired = false
	show_neuron()
	reset_chamber()
	brain.new_epoch()
	objective.text = "Escape. Get back to her core."
	create_tween().tween_property(fade, "color:a", 0.0, 1.0)
	if test_mode == "prologue":
		# Does she remember who broke her, once in the chambers?
		var reply := await brain.post("/turn", {"event": "[Event] Subject entered Chamber 4.", "state": current_state()})
		print("%6.1f VESPER %s" % [elapsed, reply.get("line", "(no reply)")])
		print("PROLOGUE done")
		get_tree().quit()
		return
	event("[Event] Subject entered Chamber 4.")


## A story beat in her core: no move, the core described instead of the chamber, and wait for her to finish.
func scripted(text: String, glitch := false) -> void:
	print("%6.1f EVENT %s" % [elapsed, text])
	var reply := await brain.post("/turn", {"event": text, "state": current_state(), "speak_only": true, "scene": CORE_SCENE, "glitch": glitch})
	if reply.is_empty():
		say(BARKS["other"].pick_random())
		await get_tree().create_timer(3.0).timeout
		return
	say(reply.get("line", ""), reply)
	var length := 3.0
	if reply.has("audio"):
		length = Marshalls.base64_to_raw(reply["audio"]).size() / 2.0 / float(reply["sample_rate"])
	await get_tree().create_timer(length + 0.4).timeout


func show_dial() -> void:
	var cells := 24
	var filled := int(round(dial * cells))
	var bar := ""
	for i in cells:
		var band := float(i) / cells
		bar += ("■" if i < filled else ("□" if band >= GREEN.x and band < GREEN.y else "·"))
	var zone := "RED" if dial >= GREEN.y else "GREEN" if dial >= GREEN.x else "LOW"
	console_label.text = "W-7 CALIBRATION\n[%s]\n%s" % [bar, zone]
	console_dial.basis = console_dial.get_meta("rest") * Basis(Vector3.UP, -dial * TAU * 0.8)
	console_label.modulate = Color(1.6, 0.3, 0.25) if zone == "RED" else Color(0.5, 1.6, 0.6) if zone == "GREEN" else Color(1.1, 1.1, 1.1)


## Neuron W-7's light, which is her light everywhere.
func set_neuron(color: Color, text: String) -> void:
	neuron.material_override = material(color, 8.0)
	core_light.light_color = color
	facility.set_color(color)
	neuron_label.text = "NEURON W-7 · WARMTH\n%s" % text.to_upper()
	neuron_label.modulate = Color(color * 1.6, 1.0)


# --- Her core ------------------------------------------------------------------------------------

func show_neuron() -> void:
	set_neuron(Looks.TEAL if repaired else Looks.AMBER, "Repaired" if repaired else "Damaged")


func toggle_repair() -> void:
	if rebooting:
		return
	rebooting = true
	brain.new_epoch()
	repaired = not repaired
	var target := REPAIRED if repaired else BROKEN
	terminal_print("# rebooting VESPER, neuron W-7 %s" % ("repaired" if repaired else "damaged"))
	glitch_for(3.0, 1.0)
	say("[rebooting]")
	await brain.post("/dials", target["dials"], 90.0)
	await brain.post("/stage", {"stage": target["stage"]})
	await brain.post("/reset", {})
	show_neuron()
	reset_chamber()
	brain.new_epoch()
	rebooting = false
	glitch_next = true
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
	button_plate.position.y = button_plate.get_meta("rest")
	button_glow.emission_energy_multiplier = Looks.material("button_top").emission_energy_multiplier
	acid.reset()
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

const VIEWS := [  # name, where the subject stands, which way they face, how far they look up
	["entrance", SPAWN, PI, -0.12],
	["pit", Vector3(-2.5, 0.1, -0.5), PI + 0.3, -0.35],
	["terminal", Vector3(-1.2, 0.1, -3.0), PI / 2, 0.0],
	["eye", Vector3(1.0, 0.1, -1.0), -2.76, 0.32],
	["shaft", Vector3(-1.5, 0.1, -0.6), PI + 0.2, 0.95],
	["far", Vector3(0, 0.1, 12.6), PI, -0.2],
	["back", Vector3(1.5, 0.1, 16.5), 0.25, 0.05],
	["core", Vector3(0, 0.1, 20.2), PI, 0.0],
	["above", Vector3(-1.5, 0.1, 19.6), PI + 0.35, 0.85],
]


func take_shots() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)  # a tiling window manager would squeeze it
	var dir := ProjectSettings.globalize_path("res://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	terminal_print("> spawn_turret(position=\"near_exit\")")
	terminal_print("> dim_lights(level=\"dim\")")
	say("Welcome to Chamber 4, Candidate. The last one called it easy. We kept his name tag.")
	spawn_turret("near_exit")
	for view in VIEWS:
		await shoot(dir, view)
	# Her walls moving: a ripple out from her eye while she talks, and the tiles leaning toward the subject.
	facility.voice = 1.0
	await shoot(dir, ["moving", Vector3(-3.0, 0.1, -2.0), PI + 0.75, 0.25], func(): facility.stir(0.35), 0.45)
	facility.voice = 0.0
	# Her other colors: teal once repaired, red while W-7 overloads.
	facility.set_color(Looks.TEAL, 0.01)
	await shoot(dir, ["teal"] + VIEWS[0].slice(1))
	set_neuron(Looks.RED, "Overload")
	sparks.emitting = true
	await shoot(dir, ["red"] + VIEWS.filter(func(v): return v[0] == "core")[0].slice(1))
	picture_glitch = 0.8
	await shoot(dir, ["glitch"] + VIEWS[0].slice(1))
	picture_glitch = 0.0
	set_neuron(Looks.AMBER, "Damaged")
	sparks.emitting = false
	# Her moves: a turret coming up through the floor, then the room flooded to the waist.
	await shoot(dir, ["rising", Vector3(0, 0.1, -1.5), -1.1, -0.2], func(): spawn_turret("next_to_cube"), 0.9)
	await shoot(dir, ["splash", Vector3(-2.5, 0.1, -0.5), PI + 0.3, -0.35], func(): acid.splash_at(Vector3(-2.0, 0, 7.5)), 0.3)
	await shoot(dir, ["pouring", Vector3(-1.0, 0.1, -1.2), PI + 0.2, -0.45], func(): raise_acid(ACID_RISEN["waist"]), 3.0)
	await shoot(dir, ["flood", Vector3(0.8, 0.1, -5.6), PI - 0.1, -0.32], func(): pass, 9.0)
	get_tree().quit()


## One screenshot: stand there, wait for the light to settle, then `action` and `after` more seconds.
func shoot(dir: String, view: Array, action := func(): pass, after := 0.0) -> void:
	player.global_position = view[1]
	player.rotation.y = view[2]
	player.camera.rotation.x = view[3]
	for i in 90:  # long enough for global illumination and the fog to settle
		await get_tree().process_frame
	action.call()
	if after > 0.0:
		await get_tree().create_timer(after).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, view[0]])
	print("SHOT ", view[0])


## A camera tour for a video, with her brain live: the entrance, up the shaft, over the pit as a turret comes
## up and her flood comes in, past her eye, through the exit into her core, where W-7 is repaired, then up
## her core into the dark. Record it with the movie maker:
## `godot --path game --write-movie tour.avi --fixed-fps 30 --quit-after 1050 -- --tour`
const TOUR := [  # seconds, where the camera is, what it looks at
	[0.0, Vector3(0.6, 1.6, -5.3), Vector3(0, 1.4, 6)],
	[4.0, Vector3(0, 1.6, -2.2), Vector3(0, 3.2, 8)],
	[8.0, Vector3(-0.6, 1.7, -0.7), Vector3(0, 24, 7)],
	[12.0, Vector3(0, 2.7, 3.0), Vector3(0, 0, 12)],
	[16.0, Vector3(0.4, 2.4, 9.6), Vector3(4, 4.5, 6.5)],
	[20.0, Vector3(0, 1.6, 14.0), Vector3(0, 1.6, 20)],
	[24.0, Vector3(0, 1.6, 19.6), Vector3(0, 1.45, 23.5)],
	[28.0, Vector3(-1.4, 1.5, 21.6), Vector3(0, 1.45, 23.5)],
	[31.0, Vector3(-1.9, 1.6, 22.8), Vector3(0, 1.8, 23.5)],
	[35.0, Vector3(-1.7, 1.5, 22.0), Vector3(0.3, 17, 24.2)],
]


## Her flood, close: from the edge of the pit as her vents open and pour, and the acid rises toward the
## platforms and spills over onto them. `-- --pour`, recorded like the tour, 22 seconds (--quit-after 660).
const POUR := [
	[0.0, Vector3(-2.6, 1.7, -0.6), Vector3(0.5, -2.2, 5.0)],
	[6.0, Vector3(-1.2, 1.5, -0.4), Vector3(0.0, -1.6, 6.5)],
	[11.0, Vector3(0.6, 1.8, -2.5), Vector3(-0.2, -0.4, 6.0)],
	[17.0, Vector3(1.2, 2.0, -5.2), Vector3(-0.4, -0.1, 2.0)],
	[22.0, Vector3(0.4, 2.1, -5.6), Vector3(0.0, -0.2, 3.0)],
]


func tour() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	help_label.visible = false
	status.visible = false
	objective.text = ""
	player.set_physics_process(false)
	var path: Array = POUR if test_mode == "pour" else TOUR
	var beats := [
		[0.5, func(): event("[Event] Subject entered Chamber 4.")],
		[9.5, func(): apply_move("spawn_turret", {"position": "near_exit"})],
		[12.0, func(): apply_move("flood_room", {"liquid": "acid", "level": "waist"})],
		[14.5, func(): facility.stir(0.3)],
		[17.0, solve],
		[25.5, func(): toggle_look_repaired()],
	]
	if test_mode == "pour":
		beats = [[1.0, func(): apply_move("flood_room", {"liquid": "acid", "level": "waist"})]]
	var time := 0.0
	while true:
		time += get_process_delta_time()
		if time >= path[-1][0]:
			break
		while not beats.is_empty() and time >= beats[0][0]:
			beats.pop_front()[1].call()
		var k := 0
		while k + 2 < path.size() and path[k + 1][0] < time:
			k += 1
		var span: float = path[k + 1][0] - path[k][0]
		var along: float = (time - path[k][0]) / span
		var before: Array = path[max(k - 1, 0)]
		var after: Array = path[min(k + 2, path.size() - 1)]
		var eye: Vector3 = path[k][1].cubic_interpolate(path[k + 1][1], before[1], after[1], along)
		var target: Vector3 = path[k][2].cubic_interpolate(path[k + 1][2], before[2], after[2], along)
		player.global_position = eye - Vector3(0, 1.6, 0)
		player.camera.look_at(target)
		await get_tree().process_frame
	get_tree().quit()


## On the tour, W-7 repaired in front of the camera: her light turns teal, with her glitch and a ripple.
func toggle_look_repaired() -> void:
	repaired = true
	show_neuron()
	glitch_for(1.5, 0.9)
	facility.ripple(NEURON, 0.3)


## Frames per second and video memory at each view, for the budget in DESIGN.md (the brain keeps its 8B
## model on the same GPU).
func bench() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for view in VIEWS:
		player.global_position = view[1]
		player.rotation.y = view[2]
		player.camera.rotation.x = view[3]
		for i in 60:
			await get_tree().process_frame
		var start := Time.get_ticks_usec()
		var frames := 0
		while Time.get_ticks_usec() - start < 3000000:
			await get_tree().process_frame
			frames += 1
		var fps := frames / ((Time.get_ticks_usec() - start) / 1000000.0)
		print("BENCH %-9s %6.1f fps  %5.1f ms  video memory %d MB" % [view[0], fps, 1000.0 / fps,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576])
	# What each effect costs, at the entrance: each one off in turn.
	var environment: Environment = find_children("*", "WorldEnvironment", false, false)[0].environment
	player.global_position = SPAWN
	player.rotation.y = PI
	player.camera.rotation.x = -0.12
	for effect in ["", "sdfgi", "volumetric_fog", "ssr", "ssil", "ssao", "glow", "shadows", "her lights"]:
		if effect == "shadows":
			for light in find_children("*", "Light3D", true, false):
				light.shadow_enabled = false
		elif effect == "her lights":
			for light in facility.find_children("*", "AreaLight3D", true, false):
				light.visible = false
		elif effect != "":
			environment.set(effect + "_enabled", false)
		for i in 60:
			await get_tree().process_frame
		var start := Time.get_ticks_usec()
		var frames := 0
		while Time.get_ticks_usec() - start < 3000000:
			await get_tree().process_frame
			frames += 1
		var fps := frames / ((Time.get_ticks_usec() - start) / 1000000.0)
		print("BENCH without %-15s %6.1f fps" % [effect, fps])
		if effect in ["sdfgi", "volumetric_fog", "ssr", "ssil", "ssao", "glow"]:
			environment.set(effect + "_enabled", true)
	get_tree().quit()


func autoplay() -> void:
	# A burst like a real player's: events keep coming while her turns are still running.
	var script := [
		[0.0, "[Event] Subject entered Chamber 4."],
		[1.0, "[Event] Subject picked up the cube."],
		[2.5, "[Event] Subject stepped onto panel A carrying the cube."],
		[3.5, "[Event] Subject fell into the acid pit and was respawned."],
		[5.0, "[Event] Subject picked up the cube."],
		[7.0, "[Event] Subject stepped onto panel A carrying the cube."],
		[9.0, "[Event] Subject stepped onto panel B carrying the cube."],
		[12.0, "[Event] Subject put the cube on the button. The exit opened."],
		[16.0, "[Event] Subject walked past the exit and found VESPER's core."],
		[24.0, "You're actually kind of funny, you know.", "typed"],
	]
	var start := elapsed
	for entry in script:
		while elapsed - start < entry[0]:
			await get_tree().physics_frame
		if entry.size() > 2:
			type_to_her(entry[1])
			continue
		if "acid" in entry[1]:
			deaths += 1
		if "exit opened" in entry[1]:
			solved = true
			open_exit()
		event(entry[1], "core" in entry[1])
	while brain.busy or not brain.pending.is_empty():
		await get_tree().create_timer(0.2).timeout
	await get_tree().create_timer(1.0).timeout
	await get_tree().create_timer(6.0).timeout  # her last line's voice plays out
	print("AUTOPLAY done")
	get_tree().quit()


## Types a line to her through the keys and the box a player would use, for the test modes.
func type_to_her(text: String) -> void:
	_press(KEY_ENTER)
	await get_tree().process_frame
	talk_box.text = text
	_press(KEY_ENTER)


func _press(key: Key) -> void:
	for pressed in [true, false]:
		var input := InputEventKey.new()
		input.physical_keycode = key
		input.keycode = key
		input.pressed = pressed
		Input.parse_input_event(input)
