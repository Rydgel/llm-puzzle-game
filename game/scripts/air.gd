extends RefCounted
## What hangs in the air: dust drifting through her light, fumes curling off the acid, sparks from neuron W-7
## when it overloads. All GPU particles, a few hundred at most.


## A soft round spot, for particles.
static func soft_dot() -> GradientTexture2D:
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var dot := GradientTexture2D.new()
	dot.gradient = fade
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(0.5, 0.0)
	dot.width = 64
	dot.height = 64
	return dot


## Fades a particle in and out over its life.
static func fade_in_out(peak := 1.0) -> GradientTexture1D:
	var alpha := Gradient.new()
	alpha.set_color(0, Color(1, 1, 1, 0))
	alpha.set_color(1, Color(1, 1, 1, 0))
	alpha.add_point(0.2, Color(1, 1, 1, peak))
	alpha.add_point(0.8, Color(1, 1, 1, peak))
	var ramp := GradientTexture1D.new()
	ramp.gradient = alpha
	return ramp


## Dust motes drifting in a box: lit, so they show in her light and the beams, and vanish in the dark.
static func dust(size: Vector3, at: Vector3, amount: int) -> GPUParticles3D:
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = size / 2
	motion.direction = Vector3(0, 1, 0)
	motion.spread = 180.0
	motion.initial_velocity_min = 0.02
	motion.initial_velocity_max = 0.08
	motion.gravity = Vector3(0, -0.01, 0)
	motion.turbulence_enabled = true
	motion.turbulence_noise_strength = 0.4
	motion.turbulence_noise_speed_random = 0.3
	motion.scale_min = 0.5
	motion.scale_max = 1.2
	motion.color_ramp = fade_in_out(0.55)
	var look := StandardMaterial3D.new()
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.albedo_texture = soft_dot()
	look.albedo_color = Color(0.9, 0.9, 0.85)
	look.vertex_color_use_as_albedo = true
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.035)
	quad.material = look
	return _particles(motion, quad, amount, 18.0, at, size)


## Fumes rising off the acid: soft green wisps that glow a little, swell and fade.
static func fumes(size: Vector3, at: Vector3, amount: int) -> GPUParticles3D:
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = size / 2
	motion.direction = Vector3(0, 1, 0)
	motion.spread = 15.0
	motion.initial_velocity_min = 0.15
	motion.initial_velocity_max = 0.4
	motion.gravity = Vector3.ZERO
	motion.turbulence_enabled = true
	motion.turbulence_noise_strength = 0.6
	motion.scale_min = 0.6
	motion.scale_max = 1.4
	var swell := Curve.new()
	swell.add_point(Vector2(0, 0.3))
	swell.add_point(Vector2(1, 1.0))
	var swell_texture := CurveTexture.new()
	swell_texture.curve = swell
	motion.scale_curve = swell_texture
	motion.color_ramp = fade_in_out(0.22)
	var look := StandardMaterial3D.new()
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.albedo_texture = soft_dot()
	look.albedo_color = Color(0.5, 1.4, 0.3)
	look.vertex_color_use_as_albedo = true
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.proximity_fade_enabled = true
	look.proximity_fade_distance = 0.5
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.7)
	quad.material = look
	return _particles(motion, quad, amount, 5.0, at, size + Vector3(0, 4, 0))


## Sparks from W-7 overloading: white-hot, falling, burning out. Off until `emitting` is set.
static func sparks(at: Vector3) -> GPUParticles3D:
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 0.35
	motion.direction = Vector3(0, 1, 0)
	motion.spread = 70.0
	motion.initial_velocity_min = 1.5
	motion.initial_velocity_max = 4.5
	motion.gravity = Vector3(0, -9.8, 0)
	motion.particle_flag_align_y = true
	motion.scale_min = 0.6
	motion.scale_max = 1.0
	var burn := Gradient.new()
	burn.set_color(0, Color(8.0, 6.0, 4.0, 1))
	burn.set_color(1, Color(1.0, 0.15, 0.05, 0))
	burn.add_point(0.4, Color(6.0, 2.2, 0.6, 1))
	var burn_texture := GradientTexture1D.new()
	burn_texture.gradient = burn
	burn_texture.use_hdr = true  # white-hot, past 1, so they glow
	motion.color_ramp = burn_texture
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.vertex_color_use_as_albedo = true
	var streak := BoxMesh.new()
	streak.size = Vector3(0.018, 0.12, 0.018)
	streak.material = look
	var spray := _particles(motion, streak, 90, 0.9, at, Vector3(8, 6, 8))
	spray.emitting = false
	return spray


## Bubbles swelling and popping on the acid's surface: small glossy domes, glowing a little.
static func bubbles(size: Vector2, amount: int) -> GPUParticles3D:
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = Vector3(size.x / 2, 0.0, size.y / 2)
	motion.direction = Vector3(0, 1, 0)
	motion.spread = 0.0
	motion.initial_velocity_min = 0.0
	motion.initial_velocity_max = 0.03
	motion.gravity = Vector3.ZERO
	motion.scale_min = 0.4
	motion.scale_max = 1.6
	var swell := Curve.new()
	swell.add_point(Vector2(0, 0))
	swell.add_point(Vector2(0.85, 1.0))
	swell.add_point(Vector2(1, 0))
	var swell_texture := CurveTexture.new()
	swell_texture.curve = swell
	motion.scale_curve = swell_texture
	var look := StandardMaterial3D.new()
	look.albedo_color = Color(0.08, 0.2, 0.03)
	look.roughness = 0.05
	look.emission_enabled = true
	look.emission = Color(0.35, 1.0, 0.12)
	look.emission_energy_multiplier = 1.2
	var dome := SphereMesh.new()
	dome.radius = 0.05
	dome.height = 0.06
	dome.radial_segments = 12
	dome.rings = 6
	dome.material = look
	var popping := _particles(motion, dome, amount, 1.2, Vector3.ZERO, Vector3(size.x, 1, size.y))
	return popping


## A splash where something falls into the acid: glowing green droplets thrown up, falling back. Fire it with
## restart() where the splash is. A `steady` one splashes all the time it's emitting: where a stream lands.
static func splash(steady := false) -> GPUParticles3D:
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 0.3
	motion.direction = Vector3(0, 1, 0)
	motion.spread = 30.0
	motion.initial_velocity_min = 2.5
	motion.initial_velocity_max = 5.5
	motion.gravity = Vector3(0, -9.8, 0)
	motion.scale_min = 0.5
	motion.scale_max = 1.3
	var glow := Gradient.new()
	glow.set_color(0, Color(4.0, 9.0, 3.0, 1))  # near white: it has to show against the acid's own glow
	glow.set_color(1, Color(0.4, 2.0, 0.2, 0))
	var glow_texture := GradientTexture1D.new()
	glow_texture.gradient = glow
	glow_texture.use_hdr = true  # past 1, so the droplets glow
	motion.color_ramp = glow_texture
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.albedo_texture = soft_dot()
	look.vertex_color_use_as_albedo = true
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var drop := QuadMesh.new()
	drop.size = Vector2(0.16, 0.16)
	drop.material = look
	var burst := _particles(motion, drop, 30 if steady else 64, 0.7 if steady else 1.0, Vector3.ZERO, Vector3(4, 5, 4))
	burst.one_shot = not steady
	burst.explosiveness = 0.0 if steady else 0.9
	burst.preprocess = 0.0
	burst.emitting = false
	if steady:
		motion.initial_velocity_min = 1.0
		motion.initial_velocity_max = 2.8
	return burst


static func _particles(motion: ParticleProcessMaterial, mesh: Mesh, amount: int, life: float, at: Vector3, reach: Vector3) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.process_material = motion
	particles.draw_pass_1 = mesh
	particles.amount = amount
	particles.lifetime = life
	particles.preprocess = life  # already in the air when the level opens
	particles.position = at
	particles.visibility_aabb = AABB(-reach / 2 - Vector3.ONE, reach + Vector3.ONE * 2)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles
