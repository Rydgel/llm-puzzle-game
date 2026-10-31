extends RefCounted
## The acid as a liquid: a heightfield over the chamber's floor and pit, simulated with "virtual pipes"
## (Mei, Decaudin and Hu, 2007). Each cell holds a depth over its ground; between neighbours, pipes carry a
## flow driven by the difference in surface height. It spills over a ledge by itself: when the pit fills
## past the platforms, acid runs out over their edges and spreads. A film thinner than FILM holds where it
## is, the way a real liquid stops spreading, so a small spill covers only part of a platform.

const G := 9.8
const FILM := 0.04  # thinner than this, acid stays put
const DAMP := 0.996  # flow lost each step, so it settles instead of sloshing forever

var nx: int
var nz: int
var cell: float
var origin: Vector2  # the world x, z of the grid's corner
var ground := PackedFloat32Array()
var depth := PackedFloat32Array()
var _left := PackedFloat32Array()  # outflow toward -x
var _right := PackedFloat32Array()  # toward +x
var _back := PackedFloat32Array()  # toward -z
var _front := PackedFloat32Array()  # toward +z
var speed := PackedFloat32Array()  # how fast it moves through each cell, for foam


func _init(cells_x: int, cells_z: int, size: float, corner: Vector2) -> void:
	nx = cells_x
	nz = cells_z
	cell = size
	origin = corner
	for array in [ground, depth, _left, _right, _back, _front, speed]:
		array.resize(nx * nz)


func index(x: float, z: float) -> int:
	var i := clampi(int((x - origin.x) / cell), 0, nx - 1)
	var j := clampi(int((z - origin.y) / cell), 0, nz - 1)
	return j * nx + i


func center(k: int) -> Vector2:
	return origin + Vector2((k % nx + 0.5) * cell, (k / nx + 0.5) * cell)


func volume() -> float:
	var total := 0.0
	for d in depth:
		total += d
	return total * cell * cell


## Adds `amount` cubic meters around (x, z), over a 3 x 3 patch of cells.
func pour(x: float, z: float, amount: float) -> void:
	var k := index(x, z)
	var i := k % nx
	var j := k / nx
	var cells := []
	for dj in [-1, 0, 1]:
		for di in [-1, 0, 1]:
			if i + di >= 0 and i + di < nx and j + dj >= 0 and j + dj < nz:
				cells.append((j + dj) * nx + i + di)
	for c in cells:
		depth[c] += amount / (cells.size() * cell * cell)


## Takes `amount` cubic meters out of the cells where `drains` is true, evenly.
func drain(drains: PackedByteArray, amount: float) -> void:
	var wet := 0
	for k in depth.size():
		if drains[k] and depth[k] > 0.0:
			wet += 1
	if wet == 0:
		return
	var each := amount / (wet * cell * cell)
	for k in depth.size():
		if drains[k]:
			depth[k] = maxf(depth[k] - each, 0.0)


## One step of `dt` seconds. `sticky` keeps thin films in place (off while it drains, so spills run back).
func step(dt: float, sticky := true) -> void:
	var area := cell * cell
	var gain := dt * G * cell
	for j in nz:
		for i in nx:
			var k := j * nx + i
			var d := depth[k]
			if d <= 0.0 or (sticky and d < FILM):
				_left[k] = 0.0
				_right[k] = 0.0
				_back[k] = 0.0
				_front[k] = 0.0
				continue
			var h := ground[k] + d
			var l := maxf(0.0, _left[k] * DAMP + gain * (h - ground[k - 1] - depth[k - 1])) if i > 0 else 0.0
			var r := maxf(0.0, _right[k] * DAMP + gain * (h - ground[k + 1] - depth[k + 1])) if i < nx - 1 else 0.0
			var b := maxf(0.0, _back[k] * DAMP + gain * (h - ground[k - nx] - depth[k - nx])) if j > 0 else 0.0
			var f := maxf(0.0, _front[k] * DAMP + gain * (h - ground[k + nx] - depth[k + nx])) if j < nz - 1 else 0.0
			var out := (l + r + b + f) * dt
			if out > d * area:  # never take out more than there is
				var scale := d * area / out
				l *= scale
				r *= scale
				b *= scale
				f *= scale
			_left[k] = l
			_right[k] = r
			_back[k] = b
			_front[k] = f
	for j in nz:
		for i in nx:
			var k := j * nx + i
			var into := 0.0
			if i > 0:
				into += _right[k - 1]
			if i < nx - 1:
				into += _left[k + 1]
			if j > 0:
				into += _front[k - nx]
			if j < nz - 1:
				into += _back[k + nx]
			var out := _left[k] + _right[k] + _back[k] + _front[k]
			depth[k] = maxf(depth[k] + dt * (into - out) / area, 0.0)
			speed[k] = (into + out) / maxf(depth[k] * cell, 0.05)


## The surface height at (x, z), between cell centers.
func surface_at(x: float, z: float) -> float:
	var k := index(x, z)
	return ground[k] + depth[k]


func depth_at(x: float, z: float) -> float:
	return depth[index(x, z)]
