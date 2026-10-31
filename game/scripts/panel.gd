extends AnimatableBody3D
## A floor panel shuttling over the acid pit between two points. Panels A and B meet in the middle.
## VESPER's move_panel nudges one up, down or sideways for a few seconds, then it settles back.

const SIZE := Vector3(2.4, 0.4, 2.4)
const PERIOD := 9.0
const NUDGES := {"up": Vector3(0, 0.8, 0), "down": Vector3(0, -0.8, 0), "left": Vector3(-1.2, 0, 0), "right": Vector3(1.2, 0, 0)}
const NUDGE_TIME := 6.0

var letter := "A"
var from_z := 0.0
var to_z := 0.0
var time := 0.0
var nudge := Vector3.ZERO
var nudge_left := 0.0
var offset := Vector3.ZERO


func setup(name_: String, start_z: float, end_z: float, material: Material) -> void:
	letter = name_
	from_z = start_z
	to_z = end_z
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = SIZE
	mesh.mesh = box
	mesh.material_override = material
	add_child(mesh)
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
	label.position.y = SIZE.y / 2 + 0.01
	label.modulate = Color(0.1, 0.1, 0.1)
	add_child(label)
	position = Vector3(0, -SIZE.y / 2, from_z)


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


func carries(body: Node3D) -> bool:
	var local := body.global_position - global_position
	return abs(local.x) < SIZE.x / 2 + 0.2 and abs(local.z) < SIZE.z / 2 + 0.2 and local.y > 0.0 and local.y < 0.6
