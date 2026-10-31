extends Node3D
## Reshaping her body: the subject pulls her wall tiles out into beams they can stand on (hold the right mouse
## button on a tile). Each tile slides out of the wall on a pillar of itself, her light glowing at its root,
## and she takes it back: after a while it sinks into the wall again. Her rerouted signals can push out whole
## rows at once (scripts/nerves.gd, the "steps" device).
##
## A beam is the tile itself, stretched: hidden in her wall's MultiMesh while it is out, drawn on its own with
## the same look, and solid while it is out.

signal pulled  # the subject pulled a tile out

const Looks := preload("res://scripts/looks.gd")
const Facility := preload("res://scripts/facility.gd")
const REACH := 14.0  # how far away a tile can be pulled from
const LONGEST := 3.4  # how far a beam can come out of the wall
const GROW := 2.2  # meters per second, while pulled
const SINK := 0.9  # meters per second, as she takes it back
const HOLD := 7.0  # seconds she leaves a pulled beam out
const MOST := 14  # beams out at once; pulling another takes back the oldest

var facility: Facility
var beams := {}  # tile index -> Beam


class Beam:
	var tile: int
	var spot: Transform3D
	var length := 0.0
	var target := 0.0
	var hold := 0.0
	var look: MultiMeshInstance3D
	var body: AnimatableBody3D
	var shape: BoxShape3D


## While the subject holds the button on a tile: it grows toward them.
func pull(hit: Dictionary, delta: float) -> void:
	var i := facility.tile_at(hit.position, hit.normal)
	for out in beams.values():  # the end of a beam already coming out: keep pulling it
		if out.body == hit.collider:
			i = out.tile
	if i < 0:
		return
	var beam: Beam = beams.get(i)
	if not beam:
		beam = _beam(i)
		pulled.emit()
	beam.target = minf(beam.target + GROW * delta, LONGEST)
	beam.hold = HOLD


## Pushes a tile out to `length` on its own, held for `seconds`: her rerouted signals do this.
func push_out(i: int, length: float, seconds: float) -> void:
	if i < 0:
		return
	var beam: Beam = beams.get(i)
	if not beam:
		beam = _beam(i)
	beam.target = length
	beam.hold = seconds


func _beam(i: int) -> Beam:
	if beams.size() >= MOST:
		var oldest: Beam = beams.values()[0]
		oldest.hold = 0.0
	var beam := Beam.new()
	beam.tile = i
	beam.spot = facility.tile_spot(i)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = facility.tile_mesh()
	multimesh.instance_count = 1
	multimesh.set_instance_custom_data(0, Color(beam.spot.origin.x, beam.spot.origin.y, beam.spot.origin.z, randf()))
	beam.look = MultiMeshInstance3D.new()
	beam.look.multimesh = multimesh
	beam.look.material_override = Looks.material("wall_beam")
	beam.look.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	add_child(beam.look)
	beam.body = AnimatableBody3D.new()
	var collision := CollisionShape3D.new()
	beam.shape = BoxShape3D.new()
	collision.shape = beam.shape
	beam.body.add_child(collision)
	add_child(beam.body)
	facility.set_tile_shown(i, false)
	beams[i] = beam
	_place(beam)
	return beam


func _place(beam: Beam) -> void:
	var depth := 0.18 + beam.length
	var stretch := Transform3D(Basis.from_scale(Vector3(1, 1, depth / 0.18)), Vector3.ZERO)
	beam.look.multimesh.set_instance_transform(0, beam.spot * stretch * facility.tile_offset())
	beam.shape.size = Vector3(0.975, 0.975, depth)
	beam.body.global_transform = Transform3D(beam.spot.basis, beam.spot.origin + beam.spot.basis.z * depth / 2)


func _physics_process(delta: float) -> void:
	for i in beams.keys():
		var beam: Beam = beams[i]
		beam.hold -= delta
		if beam.hold <= 0.0:
			beam.target = 0.0
		var speed := GROW if beam.target > beam.length else SINK
		beam.length = move_toward(beam.length, beam.target, speed * delta)
		_place(beam)
		if beam.length <= 0.0 and beam.target <= 0.0:
			facility.set_tile_shown(i, true)
			beam.look.queue_free()
			beam.body.queue_free()
			beams.erase(i)
