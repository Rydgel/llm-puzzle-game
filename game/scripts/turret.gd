extends Node3D
## One of VESPER's turrets. It needs the subject in sight for 2.5 seconds to hit them, and shows its
## beam while it aims, so stepping out of its line is always an answer.

signal hit_subject

const AIM_TIME := 2.5
const RANGE := 18.0

var target: Node3D
var exposure := 0.0
var beam: MeshInstance3D


func _ready() -> void:
	var body := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.18
	cylinder.bottom_radius = 0.28
	cylinder.height = 1.0
	body.mesh = cylinder
	body.position.y = 0.5
	body.material_override = _material(Color(0.85, 0.85, 0.88), 0.0)
	add_child(body)
	var eye := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	eye.mesh = sphere
	eye.position.y = 0.8
	eye.material_override = _material(Color(1, 0.1, 0.05), 3.0)
	add_child(eye)
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
	var eye := global_position + Vector3(0, 0.8, 0)
	var head := target.global_position + Vector3(0, 1.3, 0)
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
