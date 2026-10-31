extends Node3D
## VESPER's body: the facility (DESIGN.md, Art direction). Her walls are tiles on actuators, on a 1 m grid,
## her light in the seams. They breathe while she talks, ripple out from her eyes when she acts, and lean
## toward the subject. Her eyes sit in the walls where a tile would be, and follow the subject. Her light is
## one color everywhere: amber while she is broken, red when W-7 overloads, teal once she is repaired.
##
## Build it with wall() and searchlight(), then finish(). It only shows; the level's collision is main.gd's.

const Looks := preload("res://scripts/looks.gd")

const SEAM_DEPTH := 0.17  # her light, behind the tiles' backs: 35 cm behind their faces
const EYE_REACH := 0.35  # how far an eye can turn: the z of its gaze, at the edge of its cone
const WALL_LIGHT := 0.18  # energy of the light her seams spill into the room, per wall
const SERVO := preload("res://sounds/servo.wav")  # from art/sounds.py
const CLACK := preload("res://sounds/clack.wav")

signal recolored  # her light has finished changing color

var subject: Node3D  # the subject: her walls lean toward them, her eyes follow them
var voice := 0.0  # how loud she is right now, 0 to 1
var flicker := false  # W-7 overloading: her light stutters
var presence := 1.0  # above 1 when the room's lights are down and her light is what's left

var color := Looks.AMBER
var _tiles: Array[Transform3D] = []
var _seams := SurfaceTool.new()  # her light behind the tiles, one quad per cell, in one mesh
var _eyes: Array[Node3D] = []  # each eye's barrel, which turns
var _wall_lights: Array[AreaLight3D] = []
var _hatch_lights: Array[OmniLight3D] = []
var _tile_mesh: Mesh
var _tile_offset: Transform3D  # from a tile's spot on the wall to its mesh
var _ripple := Vector4(0, -100, 0, 99)
var _ripple_strength := 0.0
var _glow := 0.0
var _flick := 1.0  # her light's stutter while W-7 overloads
var _flick_target := 1.0
var _flick_next := 0.0
var _color_tween: Tween
var _clack: AudioStreamPlayer3D  # her tiles shifting, where a ripple starts


func _init() -> void:
	_seams.begin(Mesh.PRIMITIVE_TRIANGLES)
	_clack = AudioStreamPlayer3D.new()
	_clack.stream = CLACK
	_clack.unit_size = 5.0
	add_child(_clack)
	var source := Looks.model("tile")
	var tile: MeshInstance3D = source.find_children("*", "MeshInstance3D")[0]
	_tile_mesh = tile.mesh
	_tile_offset = tile.transform
	source.free()


## A wall of tiles along the line from `a` to `b`, from `bottom` to `top`. The line is on the tiles'
## backs; their faces are 18 cm in front, to the right of someone walking from a to b. `holes` are cells
## left empty, as Rect2i(col, row, cols, rows) counted from a and from the bottom; `eyes` are cells that
## hold one of her eyes, and `hatches` cells whose tile slides aside now and then, onto her machinery,
## both as Vector2i(col, row).
func wall(a: Vector3, b: Vector3, bottom: float, top: float, holes: Array = [], eyes: Array = [], hatches: Array = [], lit := true, seam_depth := SEAM_DEPTH) -> void:
	a.y = bottom
	b.y = bottom
	var run := b - a
	var cols := int(round(run.length()))
	var rows := int(round(top - bottom))
	var x := run.normalized()
	var face := Basis(x, Vector3.UP, x.cross(Vector3.UP))
	for col in cols:
		for row in rows:
			var cell := Vector2i(col, row)
			if holes.any(func(hole: Rect2i) -> bool: return hole.has_point(cell)):
				continue
			var spot := Transform3D(face, a + x * (col + 0.5) + Vector3.UP * (row + 0.5))
			if cell in eyes:
				_add_eye(spot)
			elif cell in hatches:
				_add_hatch(spot)
				continue
			else:
				_tiles.append(spot)
			_seam(spot.origin - face.z * seam_depth, face)
	var middle := a + run / 2 + Vector3.UP * (top - bottom) / 2
	if lit:
		# Her seams light the room a little: an area light the size of the wall, facing out of it.
		var light := AreaLight3D.new()
		light.area_size = Vector2(cols, rows)
		light.light_color = color
		light.light_energy = WALL_LIGHT
		light.area_range = 5.0
		light.light_specular = 0.3
		light.light_volumetric_fog_energy = 0.4
		light.transform = Transform3D(face.rotated(face.y, PI), middle + face.z * 0.25)
		add_child(light)
		_wall_lights.append(light)


## One cell of her light, facing out of the wall. Godot's front faces wind clockwise.
func _seam(center: Vector3, face: Basis) -> void:
	var corners := [center + (-face.x - face.y) / 2, center + (face.x - face.y) / 2, center + (face.x + face.y) / 2, center + (-face.x + face.y) / 2]
	_seams.set_normal(face.z)
	for k in [0, 2, 1, 0, 3, 2]:
		_seams.add_vertex(corners[k])


func _add_eye(spot: Transform3D) -> void:
	var eye := Looks.moving(Looks.model("eye"))
	eye.transform = spot
	add_child(eye)
	var barrel: Node3D = eye.find_child("barrel")
	barrel.set_meta("rest", barrel.transform)
	_eyes.append(barrel)


## A tile that slides out and aside every few seconds, onto her machinery and a light in her color.
func _add_hatch(spot: Transform3D) -> void:
	var machinery := Looks.model("hatch")
	machinery.transform = spot
	add_child(machinery)
	var light := OmniLight3D.new()
	light.omni_range = 1.8
	light.light_energy = 1.5
	light.position = spot * Vector3(0, 0, -0.15)
	add_child(light)
	_hatch_lights.append(light)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = _tile_mesh
	multimesh.instance_count = 1
	multimesh.set_instance_transform(0, _tile_offset)
	multimesh.set_instance_custom_data(0, Color(spot.origin.x, spot.origin.y, spot.origin.z, randf()))
	var tile := MultiMeshInstance3D.new()
	tile.multimesh = multimesh
	tile.material_override = Looks.material("wall_tile")
	tile.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	tile.transform = spot
	add_child(tile)
	var whirr := AudioStreamPlayer3D.new()
	whirr.stream = SERVO
	whirr.unit_size = 3.0
	whirr.volume_db = -6.0
	whirr.pitch_scale = randf_range(0.85, 1.15)
	whirr.position = spot.origin
	add_child(whirr)
	var out := spot.origin + spot.basis.z * 0.22
	var aside := out + spot.basis.x * 0.72
	var slide := create_tween().set_loops().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	slide.tween_interval(randf_range(3.0, 10.0))
	slide.tween_callback(whirr.play)
	slide.tween_property(tile, "position", out, 0.5)
	slide.tween_property(tile, "position", aside, 0.9)
	slide.tween_interval(randf_range(4.0, 9.0))
	slide.tween_callback(whirr.play)
	slide.tween_property(tile, "position", out, 0.9)
	slide.tween_property(tile, "position", spot.origin, 0.5)


## Her searchlight: a cone of her light from one eye, on the subject wherever they go.
func searchlight(eye: int) -> void:
	var light := SpotLight3D.new()
	light.light_color = color
	light.light_energy = 6.0
	light.spot_range = 26.0
	light.spot_angle = 9.0
	light.spot_attenuation = 0.6
	light.shadow_enabled = true
	light.light_volumetric_fog_energy = 2.5
	light.position = Vector3(0, 0, 0.5)
	light.rotation.y = PI  # a spot shines down -Z; the barrel looks down +Z
	light.set_meta("searchlight", true)
	_eyes[eye].add_child(light)


## Her tiles go into one MultiMesh, drawn in one call.
func finish() -> void:
	var seams := MeshInstance3D.new()
	seams.mesh = _seams.commit()
	seams.material_override = Looks.material("seam_light")
	seams.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	seams.gi_mode = GeometryInstance3D.GI_MODE_DISABLED  # global illumination would keep her old color
	add_child(seams)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = _tile_mesh
	multimesh.instance_count = _tiles.size()
	for i in _tiles.size():
		multimesh.set_instance_transform(i, _tiles[i] * _tile_offset)
		var at := _tiles[i].origin
		multimesh.set_instance_custom_data(i, Color(at.x, at.y, at.z, randf()))
	var tiles := MultiMeshInstance3D.new()
	tiles.multimesh = multimesh
	tiles.material_override = Looks.material("wall_tile")
	add_child(tiles)
	print("FACILITY %d tiles, %d eyes" % [_tiles.size(), _eyes.size()])


func eyes() -> Array[Node3D]:
	return _eyes


## Her light changes color over `seconds`.
func set_color(to: Color, seconds := 1.5) -> void:
	if _color_tween:
		_color_tween.kill()
	_color_tween = create_tween()
	_color_tween.tween_property(self, "color", to, seconds)
	_color_tween.tween_callback(recolored.emit)


## A ripple through her walls, out from `at`.
func ripple(at: Vector3, strength := 0.15) -> void:
	_ripple = Vector4(at.x, at.y, at.z, 0.0)
	_ripple_strength = strength
	_clack.position = at
	_clack.volume_db = linear_to_db(clamp(strength * 4.0, 0.2, 1.0))
	_clack.play()


## A ripple out from the eye nearest the subject: she has turned her attention to them.
func stir(strength := 0.15) -> void:
	if _eyes.is_empty() or not subject:
		return
	var nearest: Node3D = _eyes[0]
	for eye in _eyes:
		if eye.global_position.distance_to(subject.global_position) < nearest.global_position.distance_to(subject.global_position):
			nearest = eye
	ripple(nearest.global_position, strength)


func _process(delta: float) -> void:
	_glow = lerp(_glow, voice, 1.0 - exp(-delta * 14.0))
	var glow := (1.0 + 1.6 * _glow) * presence
	if flicker:
		# A stutter about ten times a second, eased, not a strobe.
		_flick_next -= delta
		if _flick_next <= 0.0:
			_flick_next = randf_range(0.06, 0.16)
			_flick_target = randf_range(0.25, 1.9)
		_flick = lerp(_flick, _flick_target, 1.0 - exp(-delta * 25.0))
		glow *= _flick
	Looks.her_light(color, glow)
	for light in _wall_lights:
		light.light_color = color
		light.light_energy = WALL_LIGHT * glow
	for light in _hatch_lights:
		light.light_color = color
		light.light_energy = 1.5 * glow
	_ripple.w += delta
	var tiles: ShaderMaterial = Looks.material("wall_tile")
	tiles.set_shader_parameter("breathe", _glow)
	tiles.set_shader_parameter("ripple", _ripple)
	tiles.set_shader_parameter("ripple_strength", _ripple_strength)
	if subject:
		tiles.set_shader_parameter("subject", subject.global_position + Vector3(0, 1.0, 0))
		_watch(delta)


## Each eye turns toward the subject's head, as far as its housing lets it.
func _watch(delta: float) -> void:
	var head := subject.global_position + Vector3(0, 1.5, 0)
	for barrel in _eyes:
		var rest: Transform3D = barrel.get_meta("rest")
		var housing: Node3D = barrel.get_parent()
		var gaze := (housing.global_transform.affine_inverse() * head - rest.origin).normalized()
		if gaze.z < EYE_REACH:
			var sideways := Vector2(gaze.x, gaze.y).normalized() * sqrt(1.0 - EYE_REACH * EYE_REACH)
			gaze = Vector3(sideways.x, sideways.y, EYE_REACH)
		var aim := Basis.looking_at(gaze, Vector3.UP, true)
		barrel.basis = barrel.basis.slerp(aim, 1.0 - exp(-delta * 5.0))
		for child in barrel.get_children():
			if child is SpotLight3D:
				child.light_color = color
