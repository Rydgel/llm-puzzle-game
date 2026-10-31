extends Node3D
## The acid: deep, thick, glowing, and hers to raise (DESIGN.md, Art direction). It is a liquid
## (scripts/spill.gd): her flood opens vents in the pit's walls and pours acid in through them; it heaves and
## foams where the streams land, rises, and if she pours enough it spills over the pit's edges and creeps
## across the platforms until it thins out. Then the vents close, and when her move runs out it drains,
## spills running back into the pit. Deep acid is reported by `touched`; shallow acid by burning().

signal touched(body: Node3D)

const Looks := preload("res://scripts/looks.gd")
const Air := preload("res://scripts/air.gd")
const Spill := preload("res://scripts/spill.gd")
const STREAM := preload("res://shaders/acid_stream.gdshader")
const REST := -3.0  # the pit's surface at rest; the pit goes 3 m deeper
const PIT_FLOOR := -6.0
const PIT := Rect2(-4, 0, 8, 12)  # the pit, in x and z
const FLOOR := Rect2(-4, -6, 8, 24)  # all the liquid can reach: the pit and both platforms, z -6 to 18
const CELL := 0.5
const SPILL := 0.6  # cubic meters over the brim when she floods past it: enough to creep partway across
const POUR_RATE := 36.0  # cubic meters a second, all vents together
const STAY_TIME := 20.0  # her moves never last
const DRAIN_TIME := 4.0
const STEP := 1.0 / 60.0

var level := REST  # the pit's surface
var agitation := 0.0  # 0 at rest, 1 while it fills or drains
var sim: Spill
var _state := "rest"  # rest, pour, stay, drain
var _target := 0.0  # the volume she is pouring up to
var _rest_volume := 0.0
var _drains := PackedByteArray()  # the cells it drains from: the pit
var _clock := 0.0
var _head := 0.0  # how far down her streams the acid has reached, 0 to 1
var _tail := 0.0  # how far down they have stopped pouring
var _stir := 0.0
var _map: Image  # the surface, for the shader: height (r) and how fast it flows (g)
var _map_texture: ImageTexture
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
	sim = Spill.new(int(FLOOR.size.x / CELL), int(FLOOR.size.y / CELL), CELL, FLOOR.position)
	_drains.resize(sim.nx * sim.nz)
	for k in sim.nx * sim.nz:
		var pit := PIT.has_point(sim.center(k))
		sim.ground[k] = PIT_FLOOR if pit else 0.0
		_drains[k] = 1 if pit else 0
	_settle()
	_rest_volume = sim.volume()
	_map = Image.create(sim.nx, sim.nz, false, Image.FORMAT_RGF)
	_map_texture = ImageTexture.create_from_image(_map)
	_surface = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = FLOOR.size
	plane.subdivide_width = int(FLOOR.size.x / CELL) * 2 - 1
	plane.subdivide_depth = int(FLOOR.size.y / CELL) * 2 - 1
	_surface.mesh = plane
	_surface.position = Vector3(FLOOR.get_center().x, 0, FLOOR.get_center().y)
	var look: ShaderMaterial = Looks.material("acid")
	look.set_shader_parameter("surface_map", _map_texture)
	look.set_shader_parameter("map_origin", FLOOR.position)
	look.set_shader_parameter("map_size", FLOOR.size)
	_surface.material_override = look
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_surface)
	_mist = FogVolume.new()
	_mist.size = Vector3(PIT.size.x, 2.6, PIT.size.y)
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
	_area = Area3D.new()  # deep acid: the pit, below where panels ride
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(PIT.size.x, 4, PIT.size.y)
	shape.shape = box
	_area.add_child(shape)
	add_child(_area)
	_area.body_entered.connect(touched.emit)
	_fumes = Air.fumes(Vector3(PIT.size.x - 0.4, 0.1, PIT.size.y - 0.4), Vector3.ZERO, 140)
	add_child(_fumes)
	_bubbles = Air.bubbles(PIT.size - Vector2(0.4, 0.4), 90)
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
	_rush.position = Vector3(PIT.get_center().x, -1, PIT.get_center().y)
	_stream_look = ShaderMaterial.new()
	_stream_look.shader = STREAM
	_stream_look.set_shader_parameter("churn", look.get_shader_parameter("churn"))
	_show()


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


## Her flood: the vents open and pour until the pit's surface reaches `height`. Above 0, the pit's brim, it
## overflows: the pit fills and SPILL more runs out over the platforms. The vents close, and after STAY_TIME
## it drains back to rest.
func rise(height: float) -> void:
	if _tween:
		_tween.kill()
	_target = _rest_volume + (minf(height, 0.0) - REST) * PIT.get_area() + (SPILL if height > 0.0 else 0.0)
	if _facility:
		_facility.open_vents(true)
	_state = "opening"
	_clock = 1.0  # the vents slide open
	_tween = create_tween()
	_tween.tween_property(self, "agitation", 1.0, 1.5)


## Back to rest at once: the chamber restarting.
func reset() -> void:
	if _tween:
		_tween.kill()
	_state = "rest"
	_head = 0.0
	_tail = 0.0
	agitation = 0.0
	_close_vents()
	_settle()
	_show()


## Acid spilled over a platform, over the feet at `at`: it burns (main.gd decides how long is too long). Over
## the pit, only deep acid counts, through `touched`: panels, steps and bridges above it stay safe.
func burning(at: Vector3) -> bool:
	var k := sim.index(at.x, at.z)
	return sim.ground[k] == 0.0 and sim.depth[k] > 0.01 and sim.depth[k] > at.y - 0.02


## The hiss of acid on skin, at `at`.
func sizzle_at(at: Vector3) -> void:
	_sizzle.position = at
	_sizzle.play()


## A splash of glowing acid, a flash and a sizzle, where something fell in.
func splash_at(at: Vector3) -> void:
	_splash.position = Vector3(at.x, sim.surface_at(at.x, at.z) + 0.05, at.z)
	_splash.restart()
	_splash.emitting = true
	_sizzle.position = _splash.position
	_sizzle.play()
	_splash_light.position = _splash.position + Vector3(0, 0.5, 0)
	_splash_light.light_energy = 4.0
	create_tween().tween_property(_splash_light, "light_energy", 0.0, 0.6).set_ease(Tween.EASE_IN)


func _physics_process(_delta: float) -> void:
	if _state == "rest":
		return
	_clock -= STEP
	match _state:
		"opening":
			if _clock <= 0.0:
				_state = "pour"
				_start_pouring()
		"pour":
			var left := _target - sim.volume()
			var taper := clampf(left / 40.0, 0.12, 1.0)  # gentler near the top, or it slops over in waves
			var amount := minf(POUR_RATE * taper * STEP, left)
			for stream in _streams:
				var landing := _landing(stream)
				sim.pour(landing.x, landing.z, amount / _streams.size())
			if left <= 0.01:
				_state = "stay"
				_clock = STAY_TIME
				_stop_pouring()
		"stay":
			if _clock <= 0.0:
				_state = "drain"
				_start_draining()
		"drain":
			var extra := sim.volume() - _rest_volume
			sim.drain(_drains, minf(extra, (_target - _rest_volume) / DRAIN_TIME * STEP))
			if extra <= 0.05:
				_state = "rest"
				_settle()
				create_tween().tween_property(self, "agitation", 0.0, 2.0)
	sim.step(STEP, _state != "drain")
	_show()


## Exactly at rest: the pit full to REST, the platforms dry.
func _settle() -> void:
	sim.depth.fill(0.0)
	for k in sim.nx * sim.nz:
		if sim.ground[k] < REST:
			sim.depth[k] = REST - sim.ground[k]
	sim.step(STEP)  # clears the flows


## Puts the simulated surface where the eye and the rules can see it: the surface map for the shader, the
## pit's level for everything that hangs over it, and the area of deep acid.
func _show() -> void:
	for k in sim.nx * sim.nz:
		var d := sim.depth[k]
		var height := sim.ground[k] + d
		if d < 0.005:
			# Dry: where wet neighbours sit below this cell's ground, carry their surface on under it, so
			# the surface meets the pit's walls flat; otherwise just under the ground, so a spill ends here.
			height = sim.ground[k] - 0.01
			var below := -INF
			for n in _neighbours(k):
				if sim.depth[n] >= 0.005:
					below = maxf(below, sim.ground[n] + sim.depth[n])
			if below > -INF and below < sim.ground[k]:
				height = below
		_map.set_pixel(k % sim.nx, k / sim.nx, Color(height, clampf(sim.speed[k] * 0.4, 0.0, 1.0), 0))
	_map_texture.update(_map)
	level = sim.surface_at(PIT.get_center().x, PIT.get_center().y)
	_mist.position = Vector3(PIT.get_center().x, level + 1.1, PIT.get_center().y)
	_glow.position = Vector3(PIT.get_center().x, level + 0.8, PIT.get_center().y)
	_fumes.position = Vector3(PIT.get_center().x, level + 0.1, PIT.get_center().y)
	_bubbles.position = Vector3(PIT.get_center().x, level + 0.02, PIT.get_center().y)
	# Deep acid kills at once, but never up where the panels ride: standing in shallow acid only burns.
	_area.position = Vector3(PIT.get_center().x, minf(level + 0.2, -0.45) - 2.0, PIT.get_center().y)


func _neighbours(k: int) -> Array[int]:
	var around: Array[int] = []
	var i := k % sim.nx
	var j := k / sim.nx
	if i > 0:
		around.append(k - 1)
	if i < sim.nx - 1:
		around.append(k + 1)
	if j > 0:
		around.append(k - sim.nx)
	if j < sim.nz - 1:
		around.append(k + sim.nx)
	return around


func _start_pouring() -> void:
	_head = 0.0
	_tail = 0.0
	create_tween().tween_property(self, "_head", 1.0, 0.6)
	_rush.pitch_scale = 0.55
	_rush.play()
	for stream in _streams:
		stream["pour"].play()


func _stop_pouring() -> void:
	var stop := create_tween()
	stop.tween_property(self, "_tail", 1.0, 0.6)
	stop.tween_callback(_close_vents)
	stop.tween_property(self, "agitation", 0.2, 2.0)


func _start_draining() -> void:
	_rush.pitch_scale = 0.45
	_rush.play()
	create_tween().tween_property(self, "agitation", 0.6, 0.8)


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


## Where a stream lands at the pit's level: along its arc, or at its mouth once the acid covers it.
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
	var fall := (velocity.y + sqrt(velocity.y * velocity.y + 19.6 * (mouth.y - PIT_FLOOR))) / 9.8
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
