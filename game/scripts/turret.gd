extends Node3D
## One of VESPER's turrets. It needs the subject in sight for 2.5 seconds to hit them, and shows its
## beam while it aims, so stepping out of its line is always an answer. It comes up through a hatch of her
## light in the floor, or down from above, and only aims once it has arrived.

signal hit_subject

const Looks := preload("res://scripts/looks.gd")
const AIM_TIME := 2.5
const RANGE := 18.0
const EYE := 0.9  # the height of its eye
const SERVO := preload("res://sounds/servo.wav")

var target: Node3D
var exposure := 0.0
var beam: MeshInstance3D
var body: Node3D
var from_above := false  # set before adding it: a turret hung from the ceiling comes down instead
var arrived := false
var hatch: Node3D


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
	_arrive()


func _arrive() -> void:
	body.position.y = 1.6 if from_above else -1.4
	hatch = Node3D.new()
	if not from_above:
		var hole := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.5
		disc.bottom_radius = 0.5
		disc.height = 0.01
		hole.mesh = disc
		hole.material_override = Looks.material("lens")
		var rim := MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = 0.5
		ring.outer_radius = 0.57
		rim.mesh = ring
		rim.material_override = Looks.material("seam_light")
		rim.scale.y = 0.3
		hatch.add_child(hole)
		hatch.add_child(rim)
		hatch.position.y = 0.006
	hatch.scale = Vector3(0.01, 1, 0.01)
	add_child(hatch)
	var whirr := AudioStreamPlayer3D.new()
	whirr.stream = SERVO
	whirr.pitch_scale = 0.7
	whirr.unit_size = 5.0
	add_child(whirr)
	whirr.play()
	var rise := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	rise.tween_property(hatch, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK)
	rise.tween_property(body, "position:y", 0.0, 1.2)
	rise.tween_property(hatch, "scale", Vector3(0.01, 1, 0.01), 0.25).set_ease(Tween.EASE_IN)
	rise.tween_callback(_arrived)


func _arrived() -> void:
	arrived = true
	hatch.queue_free()


func _material(color: Color, glow: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


func _physics_process(delta: float) -> void:
	if not target or not arrived:
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
