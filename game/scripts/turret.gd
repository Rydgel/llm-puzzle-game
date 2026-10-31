extends Node3D
## One of VESPER's turrets. It needs the subject in sight for 2.5 seconds to hit them, and shows its
## beam while it aims, so stepping out of its line is always an answer.

signal hit_subject

const Looks := preload("res://scripts/looks.gd")
const AIM_TIME := 2.5
const RANGE := 18.0
const EYE := 0.9  # the height of its eye

var target: Node3D
var exposure := 0.0
var beam: MeshInstance3D
var body: Node3D


func _ready() -> void:
	body = Looks.moving(Looks.model("turret"))
	add_child(body)
	beam = MeshInstance3D.new()
	var line := BoxMesh.new()
	line.size = Vector3(0.025, 0.025, 1.0)
	beam.mesh = line
	beam.material_override = _material(Color(1, 0.1, 0.05), 4.0)
	beam.visible = false
	add_child(beam)


func _material(color: Color, glow: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


func _physics_process(delta: float) -> void:
	if not target:
		return
	var eye := global_position + Vector3(0, EYE, 0)
	var head := target.global_position + Vector3(0, 1.3, 0)
	var facing := Vector3(head.x - eye.x, 0, head.z - eye.z)
	if facing.length() > 0.1:
		var aim := Basis.looking_at(facing.normalized(), Vector3.UP, true)
		body.basis = body.basis.slerp(aim, 1.0 - exp(-delta * 4.0))
	var query := PhysicsRayQueryParameters3D.create(eye, head)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var seen: bool = eye.distance_to(head) < RANGE and not hit.is_empty() and hit.collider == target
	if seen:
		exposure += delta
		beam.visible = true
		beam.global_position = (eye + head) / 2
		beam.look_at(head, Vector3.UP if abs((head - eye).normalized().y) < 0.99 else Vector3.RIGHT)
		beam.scale = Vector3(1, 1, eye.distance_to(head))
	else:
		exposure = max(exposure - delta, 0.0)
		beam.visible = false
	if exposure >= AIM_TIME:
		exposure = 0.0
		hit_subject.emit()
