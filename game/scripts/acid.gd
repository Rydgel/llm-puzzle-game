extends Node3D
## The acid in the pit: deep, thick, glowing, and hers to raise (DESIGN.md, Art direction). Her flood opens
## vents in the pit's walls and pours acid in through them until it nears the platforms: it heaves and foams
## where the streams land and churns while it moves, then the vents close, and it drains when her move runs
## out. Whatever touches it is reported by `touched`; main.gd decides what that means.

signal touched(body: Node3D)

const Looks := preload("res://scripts/looks.gd")
const Air := preload("res://scripts/air.gd")
const STREAM := preload("res://shaders/acid_stream.gdshader")
const REST := -3.0  # its surface; the pit goes 3 m deeper
const BOTTOM := -6.0
const CENTER := Vector3(0, 0, 6)  # the middle of the pit
const SIZE := Vector2(8, 12)
const FILL_TIME := 5.0
const STAY_TIME := 20.0  # her moves never last
const DRAIN_TIME := 4.0

var level := REST
var agitation := 0.0  # 0 at rest, 1 while it fills or drains
var _head := 0.0  # how far down her streams the acid has reached, 0 to 1
var _tail := 0.0  # how far down they have stopped pouring
var _stir := 0.0
var _surface: MeshInstance3D
var _mist: FogVolume
var _glow: OmniLight3D
var _area: Area3D
var _fumes: GPUParticles3D
var _bubbles: GPUParticles3D
var _splash: GPUParticles3D
var _splash_light: OmniLight3D
var _sizzle: AudioStreamPlayer3D
var _rush: AudioStreamPlayer3D
var _facility: Node3D
var _streams: Array[Dictionary] = []  # each: its mouth, the velocity it pours at, its spray, its sound
var _stream_look: ShaderMaterial
var _tween: Tween


func _ready() -> void:
	_surface = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = SIZE
	plane.subdivide_width = 32
	plane.subdivide_depth = 48
	_surface.mesh = plane
	_surface.material_override = Looks.material("acid")
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_surface)
	_mist = FogVolume.new()
	_mist.size = Vector3(SIZE.x, 2.6, SIZE.y)
	var fog := FogMaterial.new()
	fog.density = 0.12
	fog.albedo = Color(0.45, 0.65, 0.4)
	fog.emission = Color(0.01, 0.06, 0.005)
	fog.height_falloff = 1.4
	fog.edge_fade = 0.5
	_mist.material = fog
	add_child(_mist)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(0.4, 1.0, 0.2)
	_glow.light_energy = 0.35
	_glow.omni_range = 9.0
	add_child(_glow)
	_area = Area3D.new()  # touching it: from 20 cm over its surface down
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE.x, 4, SIZE.y)
	shape.shape = box
	_area.add_child(shape)
	add_child(_area)
	_area.body_entered.connect(touched.emit)
	_fumes = Air.fumes(Vector3(SIZE.x - 0.4, 0.1, SIZE.y - 0.4), Vector3.ZERO, 140)
	add_child(_fumes)
	_bubbles = Air.bubbles(SIZE - Vector2(0.4, 0.4), 90)
	add_child(_bubbles)
	_splash = Air.splash()
	add_child(_splash)
	_splash_light = OmniLight3D.new()
	_splash_light.light_color = Color(0.5, 1.0, 0.3)
	_splash_light.omni_range = 5.0
	_splash_light.light_energy = 0.0
	add_child(_splash_light)
	_sizzle = _sound("sizzle", 8.0)
	_rush = _sound("flood", 14.0)
	_rush.position = CENTER + Vector3(0, -1, 0)
	_stream_look = ShaderMaterial.new()
	_stream_look.shader = STREAM
	_stream_look.set_shader_parameter("churn", (Looks.material("acid") as ShaderMaterial).get_shader_parameter("churn"))
	set_level(REST)


## Her vents onto the acid, in the facility's pit walls: one stream each, falling in an arc into the acid.
func pour_from(facility: Node3D) -> void:
	_facility = facility
	for vent: Transform3D in facility.vents():
		var mouth := vent.origin + vent.basis.z * 0.24
		var velocity := vent.basis.z * 1.3 + Vector3(0, 0.4, 0)
		var stream := MeshInstance3D.new()
		stream.mesh = _arc(mouth, velocity, vent.basis.x)
		stream.material_override = _stream_look
		stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(stream)
		var spray := Air.splash(true)
		add_child(spray)
		var pour := _sound("flood", 6.0)
		pour.position = mouth
		pour.pitch_scale = randf_range(0.75, 0.9)
		_streams.append({"mouth": mouth, "velocity": velocity, "spray": spray, "pour": pour})


## Her flood: the vents open, acid pours in until it reaches `height`, the vents close, and after a while it
## drains away again.
func rise(height: float) -> void:
	if _tween:
		_tween.kill()
	if _facility:
		_facility.open_vents(true)
	_tween = create_tween()
	_tween.tween_interval(1.0)  # the vents slide open
	_tween.tween_callback(_start_pouring)
	_tween.tween_property(self, "_head", 1.0, 0.6)
	_tween.parallel().tween_property(self, "agitation", 1.0, 1.0)
	_tween.parallel().tween_method(set_level, level, height, FILL_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "_tail", 1.0, 0.6)
	_tween.tween_callback(_close_vents)
	_tween.tween_property(self, "agitation", 0.15, 2.0)
	_tween.tween_interval(STAY_TIME)
	_tween.tween_callback(_start_draining)
	_tween.tween_property(self, "agitation", 0.6, 0.8)
	_tween.parallel().tween_method(set_level, height, REST, DRAIN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "agitation", 0.0, 2.0)


## Back to rest at once: the chamber restarting.
func reset() -> void:
	if _tween:
		_tween.kill()
	_head = 0.0
	_tail = 0.0
	agitation = 0.0
	_close_vents()
	set_level(REST)


## Puts its surface at `y`, with everything that goes with it: its mist, glow, fumes and bubbles, and the
## area that counts as touching it.
func set_level(y: float) -> void:
	level = y
	_surface.position = Vector3(CENTER.x, y, CENTER.z)
	_mist.position = Vector3(CENTER.x, y + 1.1, CENTER.z)
	_glow.position = Vector3(CENTER.x, y + 0.8, CENTER.z)
	_fumes.position = Vector3(CENTER.x, y + 0.1, CENTER.z)
	_bubbles.position = Vector3(CENTER.x, y + 0.02, CENTER.z)
	_area.position = Vector3(CENTER.x, y - 1.8, CENTER.z)


## A splash of glowing acid, a flash and a sizzle, where something fell in.
func splash_at(at: Vector3) -> void:
	_splash.position = Vector3(at.x, level + 0.05, at.z)
	_splash.restart()
	_splash.emitting = true
	_sizzle.position = _splash.position
	_sizzle.play()
	_splash_light.position = _splash.position + Vector3(0, 0.5, 0)
	_splash_light.light_energy = 4.0
	create_tween().tween_property(_splash_light, "light_energy", 0.0, 0.6).set_ease(Tween.EASE_IN)


func _start_pouring() -> void:
	_head = 0.0
	_tail = 0.0
	_rush.pitch_scale = 0.55
	_rush.play()
	for stream in _streams:
		stream["pour"].play()


func _start_draining() -> void:
	_rush.pitch_scale = 0.45
	_rush.play()


func _close_vents() -> void:
	if _facility:
		_facility.open_vents(false)


func _process(delta: float) -> void:
	_stir += delta * (1.0 + 3.0 * agitation)
	var strength := clampf(_head - _tail, 0.0, 1.0)
	var pours := PackedVector4Array()
	for stream in _streams:
		var landing := _landing(stream)
		var spray: GPUParticles3D = stream["spray"]
		spray.position = landing
		spray.emitting = strength > 0.3
		pours.append(Vector4(landing.x, landing.z, strength, 0.0))
	while pours.size() < 4:
		pours.append(Vector4.ZERO)
	var look: ShaderMaterial = Looks.material("acid")
	look.set_shader_parameter("pours", pours)
	look.set_shader_parameter("agitation", agitation)
	look.set_shader_parameter("stir", _stir)
	_stream_look.set_shader_parameter("surface", level)
	_stream_look.set_shader_parameter("head", _head)
	_stream_look.set_shader_parameter("tail", _tail)
	_bubbles.amount_ratio = 0.35 + 0.65 * agitation
	_fumes.amount_ratio = 0.5 + 0.5 * agitation


## Where a stream lands at the acid's level: along its arc, or at its mouth once the acid covers it.
func _landing(stream: Dictionary) -> Vector3:
	var mouth: Vector3 = stream["mouth"]
	var velocity: Vector3 = stream["velocity"]
	if mouth.y <= level:
		return Vector3(mouth.x, level, mouth.z)
	var t := (velocity.y + sqrt(velocity.y * velocity.y + 19.6 * (mouth.y - level))) / 9.8
	return mouth + velocity * t + Vector3(0, -4.9 * t * t, 0)


## A tube along the arc a stream falls in, from its mouth to the bottom of the pit; its shader cuts it off at
## the acid's surface. Flattened along the wall, like a sheet pouring over a lip.
func _arc(mouth: Vector3, velocity: Vector3, along_wall: Vector3) -> ArrayMesh:
	const RINGS := 20
	const SIDES := 10
	var fall := (velocity.y + sqrt(velocity.y * velocity.y + 19.6 * (mouth.y - BOTTOM))) / 9.8
	var tube := SurfaceTool.new()
	tube.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in RINGS + 1:
		var t := fall * i / RINGS
		var center := mouth + velocity * t + Vector3(0, -4.9 * t * t, 0)
		var forward := (velocity + Vector3(0, -9.8 * t, 0)).normalized()
		var across := forward.cross(along_wall).normalized()
		var side := across.cross(forward).normalized()
		var radius := lerpf(0.11, 0.18, float(i) / RINGS)
		for k in SIDES + 1:
			var angle := TAU * k / SIDES
			var out := side * cos(angle) * radius * 1.6 + across * sin(angle) * radius * 0.8
			tube.set_normal(out.normalized())
			tube.set_uv(Vector2(float(k) / SIDES, float(i) / RINGS))
			tube.add_vertex(center + out)
	for i in RINGS:
		for k in SIDES:
			var a := i * (SIDES + 1) + k
			var b := a + SIDES + 1
			for index in [a, b, a + 1, a + 1, b, b + 1]:
				tube.add_index(index)
	return tube.commit()


func _sound(name: String, reach: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = load("res://sounds/%s.wav" % name)
	player.unit_size = reach
	add_child(player)
	return player
