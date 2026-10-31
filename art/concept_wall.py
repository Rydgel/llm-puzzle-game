"""Concept render for the art direction: the facility is VESPER's body.

A wall of square tiles on actuators, pushed out in rings around her eye as if she has just moved; one tile
slid aside on its rail, opening on the machinery behind; her amber light leaking through every seam; ceiling
light strips; polished concrete; a thin haze. Path-traced in Cycles on the GPU (OptiX on RTX), denoised.

    blender -b -P art/concept_wall.py      # writes art/renders/concept_*.png
"""

import math
import os

import bpy

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "renders")
AMBER = (1.0, 0.42, 0.06, 1)
EYE = (0.0, 2.6)  # x, z of her eye on the wall
PITCH = 1.0  # tiles are 0.975 m on a 1 m grid: 2.5 cm seams


def material(name, color, roughness=0.5, metallic=0.0, glow=None, strength=0.0, grain=0.0):
    """Principled material; grain adds a little noise to roughness so surfaces don't look like plastic."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if grain:
        noise = nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 40.0
        ramp = nodes.new("ShaderNodeMapRange")
        ramp.inputs["To Min"].default_value = roughness - grain
        ramp.inputs["To Max"].default_value = roughness + grain
        links.new(noise.outputs["Fac"], ramp.inputs["Value"])
        links.new(ramp.outputs["Result"], bsdf.inputs["Roughness"])
    if glow:
        bsdf.inputs["Emission Color"].default_value = glow
        bsdf.inputs["Emission Strength"].default_value = strength
    return m


def block(name, size, location, mat, bevel=0.02, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 4
        bpy.ops.object.shade_smooth()
    obj.data.materials.append(mat)
    return obj


def cylinder(name, radius, depth, location, mat, rotation=(math.pi / 2, 0, 0), vertices=64):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, location=location, rotation=rotation, vertices=vertices)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return obj


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    tile_mats = [material(f"tile{i}", (0.70 + d, 0.67 + d, 0.62 + d, 1), roughness=0.42, grain=0.08)
                 for i, d in enumerate((0.0, 0.025, -0.02, 0.012))]
    backing = material("backing", (0.02, 0.02, 0.02, 1), roughness=0.6, glow=AMBER, strength=2.5)
    steel = material("steel", (0.25, 0.25, 0.27, 1), roughness=0.28, metallic=1.0, grain=0.06)
    brass = material("brass", (0.78, 0.55, 0.28, 1), roughness=0.22, metallic=1.0, grain=0.05)
    rubber = material("cable", (0.03, 0.03, 0.03, 1), roughness=0.7)
    concrete = material("concrete", (0.16, 0.16, 0.17, 1), roughness=0.18, grain=0.12)
    lens = material("lens", (0.0, 0.0, 0.0, 1), roughness=0.02)
    iris = material("iris", (0.2, 0.08, 0.0, 1), glow=AMBER, strength=40.0)
    strip = material("strip", (1, 1, 1, 1), glow=(0.9, 0.95, 1.0, 1), strength=18.0)
    warning = material("warning", (0.9, 0.55, 0.05, 1), glow=AMBER, strength=8.0)

    # Her light, recessed 40 cm behind the tiles: it only shows through the seams.
    block("backing", (12.0, 0.05, 7.0), (0, 0.55, 3.0), backing, bevel=0)

    for col in range(-5, 6):
        for row in range(6):
            x, z = col * PITCH, 0.5 + row * PITCH
            if (x, z) == (2.0, 1.5):
                # Slid aside on its rail: her machinery behind.
                block("open_tile", (0.975, 0.18, 0.975), (x + 0.62, -0.22, z), tile_mats[0])
                block("hole_back", (0.975, 0.05, 0.975), (x, 0.42, z), steel, bevel=0)
                for k in range(4):
                    cylinder(f"piston{k}", 0.045, 0.55, (x - 0.33 + k * 0.22, 0.12, z - 0.2 + 0.12 * (k % 2)), brass, vertices=32)
                    cylinder(f"cable{k}", 0.02, 0.9, (x - 0.3 + k * 0.2, 0.3, z + 0.1), rubber, rotation=(0, 0, 0), vertices=16)
                bpy.ops.object.light_add(type="POINT", location=(x, 0.0, z - 0.3))
                bpy.context.active_object.data.color = (1.0, 0.15, 0.05)
                bpy.context.active_object.data.energy = 15
                continue
            if (x, z) == (EYE[0], EYE[1] - 0.1) or (x, abs(z - EYE[1]) < 0.01) == (EYE[0], True):
                continue
            # A ripple out from her eye: the tiles in the second ring are pushed out, as if she just moved.
            ring = math.hypot(x - EYE[0], z - EYE[1])
            push = -0.18 * math.exp(-((ring - 2.0) ** 2) / 0.6)
            block(f"tile_{col}_{row}", (0.975, 0.18, 0.975), (x, push, z), tile_mats[(col * 7 + row * 3) % 4])

    # Her eye, set where a tile would be.
    ex, ez = EYE
    block("eye_housing", (0.975, 0.3, 0.975), (ex, -0.05, ez), steel)
    cylinder("eye_barrel", 0.36, 0.55, (ex, -0.35, ez), brass)
    cylinder("eye_lens", 0.27, 0.58, (ex, -0.37, ez), lens)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.21, minor_radius=0.022, location=(ex, -0.665, ez),
                                     rotation=(math.pi / 2, 0, 0), major_segments=96, minor_segments=24)
    bpy.context.active_object.data.materials.append(iris)
    bpy.ops.object.light_add(type="SPOT", location=(ex, -0.75, ez), rotation=(math.pi / 2 + 0.25, 0, 0))
    spot = bpy.context.active_object
    spot.data.color = (1.0, 0.5, 0.15)
    spot.data.energy = 120
    spot.data.spot_size = 0.9

    # Floor: polished concrete with a hazard strip along the wall; ceiling light strips.
    block("floor", (14.0, 12.0, 0.1), (0, -6.0, -0.05), concrete, bevel=0)
    block("hazard", (11.0, 0.08, 0.02), (0, -0.45, 0.005), warning, bevel=0)
    for k in range(4):
        block(f"strip{k}", (10.0, 0.08, 0.04), (0, -1.5 - k * 2.2, 6.2), strip, bevel=0)

    world = bpy.data.worlds.new("world")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.004, 0.004, 0.005, 1)
    haze = world.node_tree.nodes.new("ShaderNodeVolumePrincipled")
    haze.inputs["Density"].default_value = 0.012
    world.node_tree.links.new(haze.outputs["Volume"], world.node_tree.nodes["World Output"].inputs["Volume"])
    bpy.context.scene.world = world

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 256
    scene.cycles.use_denoising = True
    scene.cycles.volume_step_rate = 2.0
    scene.render.resolution_x, scene.render.resolution_y = 1600, 900
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    use_gpu(scene)
    return scene


def use_gpu(scene):
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for kind in ("OPTIX", "CUDA"):
        try:
            prefs.compute_device_type = kind
        except TypeError:
            continue
        prefs.get_devices()
        gpus = [d for d in prefs.devices if d.type == kind]
        if gpus:
            for d in prefs.devices:
                d.use = d.type == kind
            scene.cycles.device = "GPU"
            print("DEVICE", kind, [d.name for d in gpus])
            return
    print("DEVICE CPU")


def shoot(scene, name, location, target, lens=32, focus=None):
    bpy.ops.object.empty_add(location=target)
    aim = bpy.context.active_object
    bpy.ops.object.camera_add(location=location)
    cam = bpy.context.active_object
    track = cam.constraints.new("TRACK_TO")
    track.target = aim
    track.track_axis = "TRACK_NEGATIVE_Z"
    track.up_axis = "UP_Y"
    cam.data.lens = lens
    if focus:
        cam.data.dof.use_dof = True
        cam.data.dof.focus_object = aim
        cam.data.dof.aperture_fstop = focus
    scene.camera = cam
    scene.render.filepath = os.path.join(OUT, f"concept_{name}.png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", scene.render.filepath)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    scene = build()
    shoot(scene, "wall", (0.6, -7.0, 1.65), (0.0, 0.0, 2.4), lens=30)
    shoot(scene, "angle", (-3.4, -2.6, 1.6), (0.6, -0.3, 2.4), lens=26, focus=2.8)
