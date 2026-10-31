extends MeshInstance3D
## The technician's visor (V): the world turns to a diagnostic X-ray and her nervous system shows through her
## walls, her pulses racing along it (scripts/nerves.gd). A child of the camera; its shader covers the screen.

const Nerves := preload("res://scripts/nerves.gd")
const SWITCH := 0.45  # seconds to switch on or off

var nerves: Nerves
var on := false
var amount := 0.0


func _ready() -> void:
	var quad := QuadMesh.new()
	mesh = quad
	var look := ShaderMaterial.new()
	look.shader = preload("res://shaders/visor.gdshader")
	look.render_priority = 5  # after the rest of the room, before her nerves
	material_override = look
	extra_cull_margin = 16384.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	position = Vector3(0, 0, -0.5)


func toggle() -> void:
	on = not on


func _process(delta: float) -> void:
	amount = move_toward(amount, 1.0 if on else 0.0, delta / SWITCH)
	visible = amount > 0.0
	(material_override as ShaderMaterial).set_shader_parameter("amount", amount)
	if nerves:
		nerves.visor = amount
