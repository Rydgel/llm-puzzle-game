extends RefCounted
## How things look. Her pieces are modelled in art/models.py (models/*.glb) and dressed here, in materials
## made from the free textures in textures/ (fetched by art/fetch_assets.py, see art/ASSETS.md). Models
## name their surfaces by role, and every surface with one role shares one material, so her light changes
## everywhere at once. Without the textures, materials fall back to flat colors.

const AMBER := Color(1.0, 0.42, 0.06)  # broken
const RED := Color(1.0, 0.06, 0.03)  # W-7 overloading
const TEAL := Color(0.1, 0.85, 0.7)  # repaired
const SEAM_ENERGY := 3.0
const IRIS_ENERGY := 6.0
const WALL_TILE := preload("res://shaders/wall_tile.gdshader")
const ACID := preload("res://shaders/acid.gdshader")

static var _materials := {}
static var _scenes := {}


static func texture(set_name: String, map: String) -> Texture2D:
	var path := "res://textures/%s/%s.jpg" % [set_name, map]
	return load(path) if ResourceLoader.exists(path) else null


## A material from one of the texture sets, mapped in the object's own space so it moves with the object.
static func textured(set_name: String, color: Color, roughness: float, metallic := 0.0, scale := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = texture(set_name, "color")
	m.roughness = roughness
	m.roughness_texture = texture(set_name, "roughness")
	m.metallic = metallic
	var normal := texture(set_name, "normal")
	if normal:
		m.normal_enabled = true
		m.normal_texture = normal
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func glowing(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.BLACK
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


static func plain(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


static func material(role: String) -> Material:
	if _materials.has(role):
		return _materials[role]
	var m: Material
	match role:
		"tile":
			m = textured("tile_plastic", Color(0.8, 0.77, 0.72), 0.5, 0.0, 1.2)
		"brass":
			m = textured("brushed_metal", Color(0.9, 0.66, 0.36), 0.55, 1.0, 1.5)
		"steel":
			m = textured("brushed_metal", Color(0.32, 0.32, 0.34), 0.7, 1.0, 1.5)
		"concrete":
			m = textured("concrete_floor", Color(0.5, 0.5, 0.52), 0.38, 0.0, 0.3)  # polished
		"terrazzo":
			m = textured("terrazzo", Color(0.75, 0.74, 0.72), 0.3, 0.0, 0.4)
		"lens":
			m = plain(Color(0.01, 0.01, 0.012), 0.04)
			m.clearcoat_enabled = true
		"iris":
			m = glowing(AMBER, IRIS_ENERGY)
		"seam_light":
			m = glowing(AMBER, SEAM_ENERGY)
		"strip_light":
			m = glowing(Color(0.86, 0.93, 1.0), 6.0)
		"hazard":
			m = plain(Color.WHITE, 0.6)
			m.albedo_texture = stripes()
			m.uv1_triplanar = true
			m.uv1_scale = Vector3.ONE * 2.0
		"glass":
			m = plain(Color(0.75, 0.88, 1.0, 0.12), 0.03)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.metallic_specular = 1.0
		"screen":
			m = glowing(Color(0.03, 0.12, 0.06), 0.6)
			m.roughness = 0.12
		"button_top":
			m = plain(Color(0.75, 0.08, 0.05), 0.35)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.1, 0.05)
			m.emission_energy_multiplier = 0.3
		"rubber":
			m = plain(Color(0.03, 0.03, 0.03), 0.85)
		"wall_tile":
			m = ShaderMaterial.new()
			m.shader = WALL_TILE
			m.set_shader_parameter("grain", texture("tile_plastic", "color"))
			m.set_shader_parameter("grain_normal", texture("tile_plastic", "normal"))
			m.set_shader_parameter("grain_roughness", texture("tile_plastic", "roughness"))
		"acid":
			m = ShaderMaterial.new()
			m.shader = ACID
			m.set_shader_parameter("churn", noise(false))
			m.set_shader_parameter("ripples", noise(true))
		_:
			push_warning("no material for role " + role)
			m = plain(Color.MAGENTA, 0.5)
	_materials[role] = m
	return m


## Her light, in every seam, eye and panel band: `glow` above 1 while she talks.
static func her_light(color: Color, glow := 1.0) -> void:
	for role in ["iris", "seam_light"]:
		var m: StandardMaterial3D = material(role)
		m.emission = color
		m.emission_energy_multiplier = (IRIS_ENERGY if role == "iris" else SEAM_ENERGY) * glow
	var tiles: ShaderMaterial = material("wall_tile")
	tiles.set_shader_parameter("her_color", color)
	tiles.set_shader_parameter("her_energy", SEAM_ENERGY * glow)


## One of her pieces, with its surfaces dressed by role.
static func model(name: String) -> Node3D:
	if not _scenes.has(name):
		_scenes[name] = load("res://models/%s.glb" % name)
	var node: Node3D = _scenes[name].instantiate()
	dress(node)
	return node


## Marks a piece that moves, so global illumination leaves it out instead of keeping a ghost of it.
static func moving(node: Node3D) -> Node3D:
	for child in node.find_children("*", "GeometryInstance3D"):
		child.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	return node


static func dress(node: Node) -> void:
	if node is MeshInstance3D:
		for i in node.mesh.get_surface_count():
			var original: Material = node.mesh.surface_get_material(i)
			if original:
				node.set_surface_override_material(i, material(original.resource_name))
	for child in node.get_children():
		dress(child)


## Yellow and black hazard stripes, tiling.
static func stripes() -> ImageTexture:
	var image := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			image.set_pixel(x, y, Color(0.9, 0.6, 0.04) if ((x + y) / 16) % 2 == 0 else Color(0.03, 0.03, 0.03))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


static func noise(as_normal: bool) -> NoiseTexture2D:
	var n := NoiseTexture2D.new()
	n.width = 512
	n.height = 512
	n.seamless = true
	n.as_normal_map = as_normal
	n.bump_strength = 4.0
	n.generate_mipmaps = true
	var fast := FastNoiseLite.new()
	fast.frequency = 0.012
	fast.fractal_octaves = 4
	n.noise = fast
	return n
