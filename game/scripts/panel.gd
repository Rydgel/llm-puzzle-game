extends AnimatableBody3D
## A floor panel shuttling over the acid pit between two points. Panels A and B meet in the middle.
## VESPER's move_panel nudges one up, down or sideways for a few seconds, then it settles back. She holds it
## out over the acid on a telescoping arm, from a rail of her light in the wall; the arm tilts and stretches
## as the panel moves.

const SIZE := Vector3(2.4, 0.4, 2.4)
const PERIOD := 9.0
const NUDGES := {"up": Vector3(0, 0.8, 0), "down": Vector3(0, -0.8, 0), "left": Vector3(-1.2, 0, 0), "right": Vector3(1.2, 0, 0)}
const NUDGE_TIME := 6.0
const Looks := preload("res://scripts/looks.gd")
const RAIL_Y := -0.35  # the height of the rail in the wall

var letter := "A"
var from_z := 0.0
var to_z := 0.0
var time := 0.0
var nudge := Vector3.ZERO
var nudge_left := 0.0
var offset := Vector3.ZERO
var wall_x := -4.0  # which wall holds it
var sleeve: MeshInstance3D
var rod: MeshInstance3D
var root: MeshInstance3D


func setup(name_: String, start_z: float, end_z: float, look: Node3D, wall := -4.0) -> void:
	letter = name_
	from_z = start_z
	to_z = end_z
	wall_x = wall
	add_child(look)
	sleeve = _arm_part(Vector3(0.2, 0.2, 1.0), "steel")
	rod = _arm_part(Vector3(0.11, 0.11, 1.0), "brass")
	root = _arm_part(Vector3(0.3, 0.3, 0.3), "steel")
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = SIZE
	shape.shape = box_shape
	add_child(shape)
	var label := Label3D.new()
	label.text = letter
	label.font_size = 160
	label.pixel_size = 0.005
	label.rotation_degrees = Vector3(-90, 180, 0)  # lying flat, readable from the entrance side
	label.position.y = SIZE.y / 2 + 0.008
	label.modulate = Color(0.08, 0.08, 0.09)
	label.shaded = true
	add_child(label)
	position = Vector3(0, -SIZE.y / 2, from_z)


func _arm_part(size: Vector3, role: String) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	part.mesh = box
	part.material_override = Looks.material(role)
	part.top_level = true  # placed in the world each frame, between the wall and the panel
	part.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	add_child(part)
	return part


## The arm from its rail in the wall to the panel's side: a sleeve, and a rod sliding out of it.
func _place_arm() -> void:
	var side := signf(wall_x)
	var from := Vector3(wall_x - side * 0.05, RAIL_Y, global_position.z)
	var to := global_position + Vector3(side * SIZE.x / 2, 0.0, 0.0)
	var along := (to - from).normalized()
	var aim := Basis.looking_at(along, Vector3.UP)
	root.global_transform = Transform3D(Basis(), from)
	var sleeve_length := minf(1.3, from.distance_to(to))
	sleeve.global_transform = Transform3D(Basis(aim.x, aim.y, aim.z * sleeve_length), from + along * sleeve_length / 2)
	var rod_from := from + along * (sleeve_length - 0.1)
	rod.global_transform = Transform3D(Basis(aim.x, aim.y, aim.z * rod_from.distance_to(to)), (rod_from + to) / 2)


func push(direction: String) -> void:
	nudge = NUDGES.get(direction, Vector3.ZERO)
	nudge_left = NUDGE_TIME


func reset() -> void:
	time = 0.0
	nudge_left = 0.0
	offset = Vector3.ZERO


func _physics_process(delta: float) -> void:
	time += delta
	var along := 0.5 - 0.5 * cos(TAU * time / PERIOD)  # eases at both ends, to make boarding easier
	nudge_left = max(nudge_left - delta, 0.0)
	offset = offset.lerp(nudge if nudge_left > 0.0 else Vector3.ZERO, min(1.0, delta * 4.0))
	position = Vector3(0, -SIZE.y / 2, lerp(from_z, to_z, along)) + offset
	_place_arm()


func carries(body: Node3D) -> bool:
	var local := body.global_position - global_position
	return abs(local.x) < SIZE.x / 2 + 0.2 and abs(local.z) < SIZE.z / 2 + 0.2 and local.y > 0.0 and local.y < 0.6
