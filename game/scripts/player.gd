extends CharacterBody3D
## The subject, in first person: WASD to move, the mouse to look, Space to jump, E to pick up or drop
## the cube, a click to throw it, Escape to free the mouse. The subject never speaks.

signal interact
signal threw

const SPEED := 5.0
const JUMP := 5.2
const SENSITIVITY := 0.0025

var camera: Camera3D
var held: RigidBody3D = null
var slow := 1.0  # water at waist height halves the speed


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	camera = Camera3D.new()
	camera.position.y = 1.6
	camera.current = true
	add_child(camera)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * SENSITIVITY)
		camera.rotate_x(-event.relative.y * SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, -1.45, 1.45)
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_LEFT and held:
			drop(-camera.global_basis.z * 7.0)
			threw.emit()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.physical_keycode == KEY_E:
			interact.emit()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	var input := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var direction := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	velocity.x = direction.x * SPEED * slow
	velocity.z = direction.z * SPEED * slow
	if Input.is_physical_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = JUMP
	move_and_slide()
	if held:
		held.global_position = camera.global_position - camera.global_basis.z * 1.4 - Vector3(0, 0.3, 0)
		held.global_rotation = Vector3(0, rotation.y, 0)


func look_hit(reach := 3.0) -> Dictionary:
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * reach)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)


func grab(cube: RigidBody3D) -> void:
	held = cube
	cube.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	cube.freeze = true
	add_collision_exception_with(cube)


func drop(push := Vector3.ZERO) -> void:
	if not held:
		return
	var cube := held
	held = null
	cube.freeze = false
	cube.linear_velocity = velocity + push
	await get_tree().create_timer(0.3).timeout  # let it clear the subject before they can collide again
	if is_instance_valid(cube):
		remove_collision_exception_with(cube)
