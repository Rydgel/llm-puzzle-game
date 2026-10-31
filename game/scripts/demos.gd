extends Node
## Scripted demos of the three ways into her body, for videos, with her brain live:
##
##     godot --path game --write-movie nerves.avi --fixed-fps 30 -- --demo nerves
##
## - nerves: the visor on; she sends a turret, its pulse racing from her core past the exit, then the subject
##   switches the junction by the exit, and her next pulse, a flood, opens the exit door instead.
## - shape: tiles pulled out of her wall into a relief, then her pit wall pushing out a row of steps, walked.
## - light: her bridge of light over the acid, hardening under the subject as her eye follows them across.
## - full: everything in one take, about two and a half minutes: the prologue, Chamber 4 and her body, her
##   nerves, her tiles, her light, her flood spilling over the platforms, and her core repaired. Recorded at
##   1080p with an override.cfg that sets the window to 1920x1080 (the movie is the window's size at start).

const Looks := preload("res://scripts/looks.gd")
const NEURON := Vector3(0, 1.4, 23.5)  # her neuron W-7, as in main.gd

var game: Node3D  # main.gd
var time := 0.0


func run(which: String) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	game.help_label.visible = false
	game.status.visible = false
	game.objective.text = ""
	game.player.set_physics_process(false)
	match which:
		"nerves":
			await nerves()
		"shape":
			await shape()
		"light":
			await light()
		"full":
			await full()
		_:
			push_error("no demo " + which)
	game.get_tree().quit()


## Moves the camera through `keys` ([seconds, where it is, what it looks at]) while `beats` ([seconds,
## callable]) happen on time.
func film(keys: Array, beats: Array, camera: Camera3D = null) -> void:
	time = 0.0
	while time < keys[-1][0]:
		time += get_process_delta_time()
		while not beats.is_empty() and time >= beats[0][0]:
			beats.pop_front()[1].call()
		time = minf(time, keys[-1][0])
		var k := 0
		while k + 2 < keys.size() and keys[k + 1][0] < time:
			k += 1
		var along: float = (time - keys[k][0]) / (keys[k + 1][0] - keys[k][0])
		var before: Array = keys[max(k - 1, 0)]
		var after: Array = keys[min(k + 2, keys.size() - 1)]
		var eye: Vector3 = keys[k][1].cubic_interpolate(keys[k + 1][1], before[1], after[1], along)
		var target: Vector3 = keys[k][2].cubic_interpolate(keys[k + 1][2], before[2], after[2], along)
		if camera:
			camera.global_position = eye
			camera.look_at(target)
		else:
			game.player.global_position = eye - Vector3(0, 1.6, 0)
			game.player.camera.look_at(target)
		await get_tree().process_frame


func nerves() -> void:
	var junction = game.nerves.junctions[0]
	await film([
		[0.0, Vector3(-0.8, 1.6, 12.6), Vector3(-2.5, 1.2, 18.0)],
		[4.0, Vector3(-1.2, 1.7, 13.4), Vector3(-2.2, 0.8, 17.6)],
		[8.0, Vector3(-1.6, 1.6, 14.4), Vector3(-3.6, 1.0, 17.0)],
		[11.0, Vector3(-1.3, 1.6, 14.0), Vector3(-2.4, 1.6, 17.8)],
		[16.0, Vector3(-0.6, 1.6, 13.2), Vector3(-0.6, 2.0, 18.0)],
		[19.0, Vector3(0.0, 1.6, 12.8), Vector3(0.0, 1.6, 20.0)],
	], [
		[0.3, func(): game.event("[Event] Subject entered Chamber 4.")],
		[1.0, func(): game.visor.toggle()],
		[2.2, func(): game.apply_move("spawn_turret", {"position": "near_exit"})],
		[8.2, func(): game.nerves.toggle(junction)],
		[9.5, func(): game.apply_move("flood_room", {"level": "ankle"})],
		[16.5, func(): game.visor.toggle()],
	])


func shape() -> void:
	var facility = game.facility
	var relief := []  # a block of tiles on the right wall by the entrance, pulled out to different lengths
	for row in 4:
		for z in 4:
			relief.append([facility.tile_at(Vector3(4.0, row + 0.5, -5.5 + z), Vector3(-1, 0, 0)), 0.3 + 1.1 * abs(sin(row * 1.7 + z * 2.3))])
	var pull_relief := func():
		for spec in relief:
			game.sculpt.push_out(spec[0], spec[1], 30.0)
			await get_tree().create_timer(0.07).timeout
	await film([
		[0.0, Vector3(-1.5, 1.6, -0.5), Vector3(4.0, 1.8, -4.0)],
		[4.5, Vector3(-1.0, 1.7, -1.2), Vector3(4.0, 1.6, -3.5)],
		[7.0, Vector3(0.5, 1.8, -1.2), Vector3(4.0, -0.4, 4.0)],
		[10.0, Vector3(3.1, 1.6, 0.4), Vector3(3.1, 0.4, 6.0)],
		[16.0, Vector3(3.1, 1.6, 10.8), Vector3(3.1, 0.6, 16.0)],
		[18.0, Vector3(2.8, 1.8, 12.6), Vector3(-2.0, 1.4, 4.0)],
	], [
		[0.3, func(): game.event("[Event] Subject entered Chamber 4.")],
		[0.8, pull_relief],
		[6.0, func(): game.push_steps()],
		[7.5, func(): game.tell_her("pulled", "[Event] Subject pulled your wall tiles out to make a way across the acid.")],
	])


func light() -> void:
	# A camera of its own, behind and above the subject, so her eye's cone and the bridge show.
	var camera := Camera3D.new()
	camera.fov = 70.0
	game.add_child(camera)
	camera.make_current()
	var walk := func():
		var start := time
		while time - start < 13.0:
			var z := lerpf(-1.2, 12.6, (time - start) / 13.0)
			game.player.global_position = Vector3(-2.6, 0.02, z)
			await get_tree().process_frame
	await film([
		[0.0, Vector3(0.6, 3.4, -5.0), Vector3(-2.6, 0.0, 3.0)],
		[3.0, Vector3(0.4, 3.2, -4.0), Vector3(-2.6, 0.2, 2.0)],
		[9.0, Vector3(0.2, 3.0, 2.5), Vector3(-2.6, 0.3, 7.5)],
		[15.0, Vector3(0.0, 3.0, 8.5), Vector3(-2.6, 0.3, 12.5)],
		[18.0, Vector3(1.2, 3.6, 10.5), Vector3(-2.6, 0.0, 6.0)],
	], [
		[0.3, func(): game.event("[Event] Subject entered Chamber 4.")],
		[2.5, walk],
	], camera)


## Everything in one take.
func full() -> void:
	var camera: Camera3D = game.player.camera
	var junction = game.nerves.junctions[0]  # by the exit

	# 1. The prologue, from a slow drift around her neuron, until she sends the technician away.
	game.start_prologue()
	var drift := 0.0
	while game.prologue != "":
		drift += get_process_delta_time()
		var angle := -0.35 + drift * 0.012
		var eye := Vector3(sin(angle) * 3.3, 1.65 + 0.12 * sin(drift * 0.2), NEURON.z - cos(angle) * 3.3)
		game.player.global_position = eye - Vector3(0, 1.6, 0)
		camera.look_at(Vector3(0.7, 1.25, NEURON.z))
		await get_tree().process_frame

	# 2. Chamber 4: her walls, her eyes, the shaft over the pit.
	await film([
		[0.0, Vector3(0, 1.6, -4.5), Vector3(0, 1.8, 6.0)],
		[4.0, Vector3(-1.0, 1.6, -2.6), Vector3(-4.0, 4.0, 2.5)],
		[8.0, Vector3(-0.8, 1.7, -0.9), Vector3(0.0, 22.0, 6.0)],
		[12.0, Vector3(0.5, 1.6, -0.6), Vector3(4.0, 4.5, 6.5)],
		[16.0, Vector3(0.0, 2.4, 3.0), Vector3(0.0, 0.0, 12.0)],
		[20.0, Vector3(-0.8, 1.6, 12.8), Vector3(-2.5, 1.2, 18.0)],
	], [
		[2.5, func(): game.facility.stir(0.3)],
		[12.5, func(): game.facility.stir(0.25)],
	])

	# 3. Her nerves: the visor, a pulse from her core, the junction by the exit switched, her move rerouted.
	await film([
		[0.0, Vector3(-0.8, 1.6, 12.8), Vector3(-2.5, 1.2, 18.0)],
		[4.0, Vector3(-1.2, 1.7, 13.4), Vector3(-2.2, 0.8, 17.6)],
		[8.0, Vector3(-1.6, 1.6, 14.4), Vector3(-3.6, 1.0, 17.0)],
		[11.0, Vector3(-1.3, 1.6, 14.0), Vector3(-2.4, 1.6, 17.8)],
		[15.0, Vector3(-0.6, 1.6, 13.2), Vector3(-0.6, 2.0, 18.0)],
	], [
		[0.5, func(): game.visor.toggle()],
		[1.5, func(): game.apply_move("spawn_turret", {"position": "near_exit"})],
		[7.0, func(): game.nerves.toggle(junction)],
		[8.0, func(): game.apply_move("dim_lights", {"level": "dim"})],
		[13.5, func(): game.nerves.toggle(junction)],
		[14.0, func(): game.visor.toggle()],
	])

	# 4. Her body reshaped: the pit wall pushes out steps, walked back to the entrance; tiles pulled into a relief.
	await film([
		[0.0, Vector3(-0.6, 1.6, 13.2), Vector3(4.0, -0.3, 8.0)],
		[3.0, Vector3(2.0, 1.8, 12.8), Vector3(3.1, 0.2, 6.0)],
		[5.0, Vector3(3.1, 1.6, 11.8), Vector3(3.1, 0.6, 6.0)],
		[11.0, Vector3(3.1, 1.6, 0.8), Vector3(3.1, 0.6, -4.0)],
		[13.0, Vector3(-1.0, 1.6, -1.0), Vector3(4.0, 1.8, -4.0)],
		[17.0, Vector3(-1.2, 1.7, -1.4), Vector3(4.0, 1.6, -3.5)],
	], [
		[0.5, func(): game.push_steps()],
		[6.0, func(): game.tell_her("pulled", "[Event] Subject is walking over the acid on your wall tiles, pulled out into steps.")],
		[11.5, pull_relief],
	])

	# 5. Her light: a bridge over the acid, hardening under the subject as her eye follows them across.
	var follow := Camera3D.new()
	follow.fov = 70.0
	game.add_child(follow)
	follow.make_current()
	var walk := func():
		var start := time
		while time - start < 12.5:
			game.player.global_position = Vector3(-2.6, 0.02, lerpf(-1.2, 12.6, (time - start) / 12.5))
			await get_tree().process_frame
	await film([
		[0.0, Vector3(0.4, 3.2, -4.0), Vector3(-2.6, 0.2, 2.0)],
		[8.0, Vector3(0.2, 3.0, 3.5), Vector3(-2.6, 0.3, 8.5)],
		[14.0, Vector3(0.0, 3.0, 8.5), Vector3(-2.6, 0.3, 12.5)],
	], [
		[0.3, walk],
		[3.0, func(): game.tell_her("hard light", "[Event] Subject is walking over the acid on your bridge of light. It is solid only where your eye looks.")],
	], follow)
	camera.make_current()
	follow.queue_free()

	# 6. Her flood: the vents open and pour, and the acid spills over the platforms; the subject on the far one.
	await film([
		[0.0, Vector3(1.5, 1.7, 13.0), Vector3(0.0, -1.5, 6.0)],
		[8.0, Vector3(1.5, 1.9, 13.2), Vector3(-2.0, -1.0, 4.0)],
		[16.0, Vector3(2.5, 3.6, 13.5), Vector3(0.0, 0.0, 0.0)],
		[26.0, Vector3(2.0, 3.8, 13.0), Vector3(-1.0, 0.0, -3.0)],
	], [
		[0.5, func(): game.apply_move("flood_room", {"liquid": "acid", "level": "waist"})],
	])

	# 7. Her core: through the exit, W-7 repaired, her light turning teal, then up her core into the dark.
	await film([
		[0.0, Vector3(0.5, 1.6, 14.5), Vector3(0.0, 1.6, 20.0)],
		[5.0, Vector3(0.0, 1.6, 19.6), Vector3(0.0, 1.45, NEURON.z)],
		[9.0, Vector3(-1.4, 1.5, 21.6), Vector3(0.0, 1.45, NEURON.z)],
		[12.0, Vector3(-1.9, 1.6, 22.8), Vector3(0.0, 1.8, NEURON.z)],
		[17.0, Vector3(-1.7, 1.5, 22.0), Vector3(0.3, 17.0, 24.2)],
	], [
		[0.2, func(): game.open_exit()],
		[8.0, func(): game.toggle_look_repaired()],
		[15.5, func(): game.create_tween().tween_property(game.fade, "color:a", 1.0, 1.5)],
	])


## Tiles of the right wall by the entrance, pulled out to different lengths, one after another.
func pull_relief() -> void:
	for row in 4:
		for z in 4:
			var i: int = game.facility.tile_at(Vector3(4.0, row + 0.5, -5.5 + z), Vector3(-1, 0, 0))
			game.sculpt.push_out(i, 0.3 + 1.1 * absf(sin(row * 1.7 + z * 2.3)), 30.0)
			await get_tree().create_timer(0.07).timeout
