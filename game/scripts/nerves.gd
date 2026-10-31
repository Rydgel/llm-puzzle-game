extends Node3D
## Her nervous system. Nerves run from her core, under the floor and behind her tiles, to every device she
## commands. When she makes a move, it doesn't happen at once: a pulse of her light leaves her core and races
## along her nerves to the device, and the move happens when it arrives. Her pulses light her seams as they
## pass; the technician's visor (scripts/visor.gd) shows the whole network through her walls.
##
## Two junctions on her trunk nerve can be switched by the subject (E on the socket). A pulse that passes a
## switched junction is rerouted: whatever she commanded, it lands on the junction's other device instead.
## Junction 1, by the exit, sends it into the exit door; junction 2, at the entrance end of the pit, into the
## actuators of the pit's right wall, which push out a row of steps.

signal arrived(move: Dictionary)  # a pulse reached the device it was sent to
signal rerouted(move: Dictionary, device: String)  # a pulse was sent somewhere else by a junction
signal diverted(move: Dictionary, device: String)  # a rerouted pulse reached the junction's device

const SPEED := 7.0  # meters per second along her nerves
const CORE := Vector3(0, -0.06, 23.5)  # under her neuron
const GATE := Vector3(0, -0.06, 18.0)  # under the exit
const TRUNK_X := -4.28  # behind the left wall's tiles
const TRUNK_Y := 1.0
const TRUNK_TOP := 17.6  # the trunk runs along the left wall from here...
const TRUNK_END := -5.6  # ...to here
const CEILING_Y := 6.05  # inside the ceiling

var color := Color(1.0, 0.42, 0.06)
var visor := 0.0  # 0 to 1: how much the visor shows her nerves through everything
var thinking := false  # her brain is choosing a move: her core gathers light
var junctions: Array[Junction] = []
var _pulses: Array[Pulse] = []
var _nerve_look := StandardMaterial3D.new()
var _glow_look := StandardMaterial3D.new()
var _core_glow: MeshInstance3D
var _labels: Array[Label3D] = []


class Junction:
	var point: Vector3  # on the trunk
	var device: String  # where it sends a pulse when switched
	var route: PackedVector3Array  # from the junction to that device
	var switched := false
	var ring: MeshInstance3D
	var body: StaticBody3D
	var label: Label3D


class Pulse:
	var path: PackedVector3Array
	var lengths: PackedFloat32Array  # distance along the path at each point
	var travelled := 0.0
	var move: Dictionary
	var device := ""  # set once a junction reroutes it
	var passed := {}  # junctions already passed
	var head: Node3D


func _ready() -> void:
	for look in [_nerve_look, _glow_look]:
		look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		look.render_priority = 10  # over the visor's view of the world
		look.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add_junction(Vector3(TRUNK_X, TRUNK_Y, 17.0), "exit", PackedVector3Array([
		Vector3(TRUNK_X, TRUNK_Y, 17.0), Vector3(-4.0, TRUNK_Y, 17.97), Vector3(-1.2, TRUNK_Y, 17.97), Vector3(-1.2, 2.9, 17.97)]))
	_add_junction(Vector3(TRUNK_X, TRUNK_Y, -0.6), "steps", PackedVector3Array([
		Vector3(TRUNK_X, TRUNK_Y, -0.6), Vector3(TRUNK_X, CEILING_Y, -0.6), Vector3(4.28, CEILING_Y, -0.6),
		Vector3(4.28, -0.5, 0.3)]))
	_draw_network()
	_core_glow = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.35
	ball.height = 0.7
	_core_glow.mesh = ball
	_core_glow.material_override = _glow_look
	_core_glow.position = CORE
	add_child(_core_glow)


## Sends one of her moves down her nerves to `target`, the device's position. `move` comes back in arrived().
func send(move: Dictionary, target: Vector3) -> void:
	var pulse := Pulse.new()
	pulse.move = move
	_set_path(pulse, route(target))
	pulse.head = _pulse_head()
	add_child(pulse.head)
	_pulses.append(pulse)


## The path from her core to `target`: under the floor to the exit, up into the trunk along the left wall,
## past the junctions, then off to the device across the floor, along the left wall, or over the ceiling.
func route(target: Vector3) -> PackedVector3Array:
	var path := PackedVector3Array([CORE, GATE, Vector3(-3.9, -0.06, 18.0), Vector3(TRUNK_X, TRUNK_Y, TRUNK_TOP)])
	var along := clampf(target.z, TRUNK_END, TRUNK_TOP)
	for junction in junctions:
		if junction.point.z <= TRUNK_TOP and junction.point.z > along:
			path.append(junction.point)
	path.append(Vector3(TRUNK_X, TRUNK_Y, along))
	if target.x <= -3.5:  # on the left wall: straight up or down to it
		path.append(Vector3(TRUNK_X, target.y, along))
	elif target.y > 4.0 or target.x >= 3.5 or (target.z > 0.0 and target.z < 12.0):  # over the ceiling
		path.append(Vector3(TRUNK_X, CEILING_Y, along))
		path.append(Vector3(minf(target.x, 4.28), CEILING_Y, along))
		if target.x >= 3.5:
			path.append(Vector3(4.28, target.y, along))
	else:  # across the floor
		path.append(Vector3(-4.1, -0.06, along))
		path.append(Vector3(target.x, -0.06, along))
	path.append(target)
	return path


## The subject switched a junction: its pulses go to its other device, or back on their way.
func toggle(junction: Junction) -> void:
	junction.switched = not junction.switched


## The junction whose socket `body` is, if any.
func junction_of(body: Object) -> Junction:
	for junction in junctions:
		if junction.body == body:
			return junction
	return null


func _set_path(pulse: Pulse, path: PackedVector3Array) -> void:
	pulse.path = path
	pulse.lengths = PackedFloat32Array([0.0])
	for k in range(1, path.size()):
		pulse.lengths.append(pulse.lengths[k - 1] + path[k - 1].distance_to(path[k]))
	pulse.travelled = 0.0


func _at(pulse: Pulse, distance: float) -> Vector3:
	for k in range(1, pulse.path.size()):
		if distance <= pulse.lengths[k]:
			var span := pulse.lengths[k] - pulse.lengths[k - 1]
			return pulse.path[k - 1].lerp(pulse.path[k], (distance - pulse.lengths[k - 1]) / maxf(span, 0.001))
	return pulse.path[-1]


func _process(delta: float) -> void:
	var hot := Color(color * 10.0, 1.0)
	_nerve_look.albedo_color = Color(color * (0.5 + 0.4 * visor), 0.3 + 0.45 * visor)
	_nerve_look.no_depth_test = visor > 0.01
	_glow_look.albedo_color = Color(color * 3.0, (0.25 + 0.35 * sin(Time.get_ticks_msec() / 90.0)) * visor if thinking else 0.15 * visor)
	_glow_look.no_depth_test = true
	_core_glow.scale = Vector3.ONE * (1.4 if thinking else 1.0)
	for label in _labels:
		label.modulate.a = visor
	for junction in junctions:
		var ring_look: StandardMaterial3D = junction.ring.material_override
		ring_look.albedo_color = Color(0.6, 1.8, 2.0) if junction.switched else hot
		junction.label.text = "JUNCTION · " + ("REROUTING TO " + junction.device.to_upper() if junction.switched else "THROUGH")
	for pulse: Pulse in _pulses.duplicate():
		pulse.travelled += SPEED * delta
		# Passing a switched junction sends the pulse off to the junction's device.
		for junction in junctions:
			if pulse.device == "" and junction.switched and not pulse.passed.has(junction):
				var k: int = pulse.path.find(junction.point)
				if k >= 0 and pulse.travelled >= pulse.lengths[k]:
					pulse.passed[junction] = true
					pulse.device = junction.device
					_set_path(pulse, junction.route)
					rerouted.emit(pulse.move, junction.device)
		var at := _at(pulse, pulse.travelled)
		pulse.head.global_position = at
		var trail := pulse.head.get_meta("trail") as Array
		for k in trail.size():
			trail[k].global_position = _at(pulse, maxf(pulse.travelled - 0.16 * (k + 1), 0.0))
		var head_look: StandardMaterial3D = pulse.head.get_child(0).material_override
		head_look.albedo_color = hot
		head_look.no_depth_test = visor > 0.01
		if pulse.travelled >= pulse.lengths[-1]:
			_pulses.erase(pulse)
			pulse.head.queue_free()
			if pulse.device == "":
				arrived.emit(pulse.move)
			else:
				diverted.emit(pulse.move, pulse.device)


func _pulse_head() -> Node3D:
	var head := Node3D.new()
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.render_priority = 11
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.13
	sphere.height = 0.26
	ball.mesh = sphere
	ball.material_override = look
	head.add_child(ball)
	var trail := []
	for k in 10:
		var spark := MeshInstance3D.new()
		var small := SphereMesh.new()
		small.radius = 0.1 * (1.0 - k / 11.0)
		small.height = small.radius * 2
		spark.mesh = small
		spark.material_override = look
		spark.top_level = true
		head.add_child(spark)
		trail.append(spark)
	head.set_meta("trail", trail)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 4.0
	light.omni_range = 2.2
	head.add_child(light)
	return head


func _add_junction(point: Vector3, device: String, divert: PackedVector3Array) -> void:
	var junction := Junction.new()
	junction.point = point
	junction.device = device
	junction.route = divert
	# Its socket, on the face of the wall in front of the trunk: brass, a ring of her light, within reach.
	var socket := Node3D.new()
	socket.position = Vector3(-4.0, point.y, point.z)
	socket.rotation.z = -PI / 2  # facing out of the left wall, +x
	add_child(socket)
	var brass := MeshInstance3D.new()
	var plate := CylinderMesh.new()
	plate.top_radius = 0.17
	plate.bottom_radius = 0.2
	plate.height = 0.08
	brass.mesh = plate
	brass.material_override = preload("res://scripts/looks.gd").material("brass")
	brass.position.y = 0.04
	socket.add_child(brass)
	junction.ring = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.09
	ring.outer_radius = 0.13
	junction.ring.mesh = ring
	var ring_look := StandardMaterial3D.new()
	ring_look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	junction.ring.material_override = ring_look
	junction.ring.position.y = 0.09
	socket.add_child(junction.ring)
	junction.body = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var ball := SphereShape3D.new()
	ball.radius = 0.25
	shape.shape = ball
	junction.body.add_child(shape)
	junction.body.position.y = 0.1
	socket.add_child(junction.body)
	junction.label = Label3D.new()
	junction.label.position = Vector3(-3.97, point.y + 0.35, point.z)
	junction.label.rotation_degrees.y = 90
	junction.label.font_size = 28
	junction.label.pixel_size = 0.0018
	junction.label.no_depth_test = true
	junction.label.modulate = Color(0.6, 1.8, 2.0, 0)
	add_child(junction.label)
	_labels.append(junction.label)
	junctions.append(junction)


## Her nerves as glowing tubes: the trunk, its branches to her devices, and the bundles that climb the
## shaft and her core. Behind her tiles they only show through the seams; the visor shows them all.
func _draw_network() -> void:
	var lines: Array[PackedVector3Array] = [
		route(Vector3(-1.2, 2.9, 17.97)),  # the exit
		route(Vector3(-1.2, 2.9, -5.95)),  # the entrance
		route(Vector3(TRUNK_X, -2.5, 6.0)),  # low in the pit wall, for her acid
		route(Vector3(0, CEILING_Y, 9.0)),  # the ceiling lights
		route(Vector3(2.5, -0.06, 16.5)),  # the turret socket by the exit
		PackedVector3Array([Vector3(TRUNK_X, TRUNK_Y, 6.0), Vector3(TRUNK_X, -0.35, 6.0)]),  # the panels' rail
		PackedVector3Array([Vector3(TRUNK_X, -0.35, 0.3), Vector3(TRUNK_X, -0.35, 11.7)]),
		PackedVector3Array([Vector3(TRUNK_X, TRUNK_Y, 6.0), Vector3(TRUNK_X, 36.0, 6.0)]),  # up the shaft
		PackedVector3Array([Vector3(TRUNK_X, CEILING_Y, 2.0), Vector3(4.28, CEILING_Y, 2.0), Vector3(4.28, 36.0, 2.0)]),
		PackedVector3Array([CORE, Vector3(0, -0.06, 26.28), Vector3(0, 20.0, 26.28)]),  # up her core
		PackedVector3Array([CORE, Vector3(-4.28, -0.06, 23.5), Vector3(-4.28, 20.0, 23.5)]),
		PackedVector3Array([CORE, Vector3(4.28, -0.06, 23.5), Vector3(4.28, 20.0, 23.5)]),
	]
	for junction in junctions:
		lines.append(junction.route)
	var tubes := SurfaceTool.new()
	tubes.begin(Mesh.PRIMITIVE_TRIANGLES)
	for line in lines:
		for k in range(1, line.size()):
			_tube(tubes, line[k - 1], line[k], 0.03)
	var network := MeshInstance3D.new()
	network.mesh = tubes.commit()
	network.material_override = _nerve_look
	network.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	network.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(network)


func _tube(tubes: SurfaceTool, a: Vector3, b: Vector3, radius: float) -> void:
	if a.distance_to(b) < 0.001:
		return
	var along := (b - a).normalized()
	var side := along.cross(Vector3.UP if absf(along.y) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(along)
	var sides := 6
	for k in sides:
		var t0 := TAU * k / sides
		var t1 := TAU * (k + 1) / sides
		var o0 := (side * cos(t0) + up * sin(t0)) * radius
		var o1 := (side * cos(t1) + up * sin(t1)) * radius
		for v in [a + o0, b + o0, b + o1, a + o0, b + o1, a + o1]:
			tubes.add_vertex(v)
