extends Node3D
## Her projections turn solid. Over the acid, along the left side of the pit, she projects a bridge in light:
## a hologram, flickering, nothing to stand on. Where the cone of her searchlight eye falls on it, it hardens
## into solid light; where she looks away, it melts back. Her eye follows the subject, so the bridge is solid
## under them only while she watches them, and only where nothing stands between her eye and the bridge.

signal stepped_on  # the subject stood on her hard light for the first time

const CONE := 15.0  # degrees from the eye's line of sight that harden
const HARDEN := 5.0  # how fast a cell hardens, per second
const MELT := 1.4  # how fast it melts back

var projector: SpotLight3D  # her searchlight, on one of her eyes
var subject: CharacterBody3D
var color := Color(1.0, 0.42, 0.06)
var cells: Array[Cell] = []
var _stood := false


class Cell:
	var body: StaticBody3D
	var collision: CollisionShape3D
	var look: ShaderMaterial
	var solid := 0.0


## A bridge of cells, `width` across, from `from` to `to` along z, its top at the floor.
func build(x: float, from: float, to: float, width: float) -> void:
	var count := int(round(absf(to - from)))
	for k in count:
		var cell := Cell.new()
		cell.body = StaticBody3D.new()
		cell.body.position = Vector3(x, -0.05, from + (k + 0.5) * signf(to - from))
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(width, 0.1, 0.98)
		mesh.mesh = box
		cell.look = ShaderMaterial.new()
		cell.look.shader = preload("res://shaders/hologram.gdshader")
		cell.look.set_shader_parameter("half_size", Vector2(width / 2, 0.49))
		mesh.material_override = cell.look
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		cell.body.add_child(mesh)
		cell.collision = CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box.size
		cell.collision.shape = shape
		cell.collision.disabled = true
		cell.body.add_child(cell.collision)
		add_child(cell.body)
		cells.append(cell)


func _physics_process(delta: float) -> void:
	if not projector:
		return
	var origin := projector.global_position
	var forward := -projector.global_basis.z
	var space := get_world_3d().direct_space_state
	var mine: Array[RID] = []
	for cell in cells:
		mine.append(cell.body.get_rid())
	if subject:
		mine.append(subject.get_rid())
	for cell in cells:
		var spot := cell.body.global_position + Vector3(0, 0.05, 0)
		var to_cell := spot - origin
		var lit := rad_to_deg(forward.angle_to(to_cell)) < CONE and to_cell.length() < projector.spot_range
		if lit:
			# Only where nothing stands between her eye and the bridge: a panel's shadow is a hole.
			var ray := PhysicsRayQueryParameters3D.create(origin, spot)
			ray.exclude = mine
			lit = space.intersect_ray(ray).is_empty()
		cell.solid = move_toward(cell.solid, 1.0 if lit else 0.0, delta * (HARDEN if lit else MELT))
		cell.collision.set_deferred("disabled", cell.solid < 0.6)
		cell.look.set_shader_parameter("solid", cell.solid)
		cell.look.set_shader_parameter("color", color)
		if not _stood and subject and cell.solid >= 0.6 and subject.is_on_floor() \
				and Vector2(subject.global_position.x, subject.global_position.z).distance_to(Vector2(spot.x, spot.z)) < 0.7:
			_stood = true
			stepped_on.emit()
