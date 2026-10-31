"""VESPER's pieces, modelled in code: writes game/models/*.glb and a preview of each to art/renders/.

Surfaces are named by role (tile, brass, steel, lens, iris, seam_light, strip_light, hazard, glass, screen,
button_top, rubber). Godot replaces them by name with its textured materials (game/scripts/looks.gd), so the
colors here only matter for the previews. Everything that glows in her color uses "iris" or "seam_light".

Axes: Blender is Z up; the glTF export turns Blender -Y into Godot +Z. Wall pieces have their origin on their
back face and stick out toward -Y here, +Z in Godot.

    blender -b -P art/models.py                 # every model
    blender -b -P art/models.py -- eye cube     # some of them
"""

import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS = os.path.join(HERE, "..", "game", "models")
RENDERS = os.path.join(HERE, "renders")

COLORS = {
    "tile": ((0.72, 0.69, 0.64, 1), 0.45, 0.0, 0.0),
    "brass": ((0.78, 0.55, 0.28, 1), 0.25, 1.0, 0.0),
    "steel": ((0.22, 0.22, 0.24, 1), 0.3, 1.0, 0.0),
    "lens": ((0.0, 0.0, 0.0, 1), 0.02, 0.0, 0.0),
    "iris": ((1.0, 0.42, 0.06, 1), 0.4, 0.0, 30.0),
    "seam_light": ((1.0, 0.42, 0.06, 1), 0.4, 0.0, 12.0),
    "strip_light": ((0.9, 0.95, 1.0, 1), 0.4, 0.0, 15.0),
    "hazard": ((0.95, 0.6, 0.05, 1), 0.5, 0.0, 0.0),
    "glass": ((0.8, 0.9, 1.0, 1), 0.02, 0.0, 0.0),
    "screen": ((0.02, 0.05, 0.03, 1), 0.15, 0.0, 0.0),
    "button_top": ((0.85, 0.12, 0.08, 1), 0.35, 0.0, 0.0),
    "rubber": ((0.03, 0.03, 0.03, 1), 0.8, 0.0, 0.0),
}


def mat(name):
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    color, roughness, metallic, glow = COLORS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if glow:
        bsdf.inputs["Emission Color"].default_value = color
        bsdf.inputs["Emission Strength"].default_value = glow
    if name == "glass":
        bsdf.inputs["Transmission Weight"].default_value = 1.0
    return m


def finish(obj, material, bevel=0.0, segments=3, smooth=True):
    if bevel:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = "ANGLE"
    obj.data.materials.append(mat(material))
    if smooth:
        bpy.ops.object.shade_smooth()
        if bevel:
            obj.modifiers.new("Normals", "WEIGHTED_NORMAL")
    return obj


def box(name, size, at, material, bevel=0.0, rotation=(0, 0, 0), parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=at, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(scale=True)
    obj.parent = parent
    return finish(obj, material, bevel, smooth=bool(bevel))


def cyl(name, radius, depth, at, material, rotation=(math.pi / 2, 0, 0), vertices=48, parent=None):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, location=at, rotation=rotation, vertices=vertices)
    obj = bpy.context.active_object
    obj.name = name
    obj.parent = parent
    return finish(obj, material)


def ring(name, major, minor, at, material, rotation=(math.pi / 2, 0, 0), parent=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, location=at, rotation=rotation,
                                     major_segments=72, minor_segments=16)
    obj = bpy.context.active_object
    obj.name = name
    obj.parent = parent
    return finish(obj, material)


def sphere(name, radius, at, material, scale=(1, 1, 1), parent=None):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=at, segments=48, ring_count=24)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    obj.parent = parent
    return finish(obj, material)


def empty(name, at, parent=None):
    bpy.ops.object.empty_add(location=at)
    obj = bpy.context.active_object
    obj.name = name
    obj.parent = parent
    return obj


# --- The pieces ---------------------------------------------------------------------------------

def tile():
    """One of her wall tiles: 0.975 m square, 18 cm deep, origin on the back face. Godot sets hundreds of
    them by their mesh alone, so the origin is baked into the vertices."""
    obj = box("tile", (0.975, 0.18, 0.975), (0, -0.09, 0), "tile", bevel=0.02)
    bpy.ops.object.transform_apply(location=True)


def eye():
    """Her eye, in place of a tile. Godot aims the "barrel" node at the subject."""
    box("housing", (0.975, 0.3, 0.975), (0, -0.15, 0), "steel", bevel=0.02)
    pivot = empty("barrel", (0, -0.3, 0))
    cyl("barrel_body", 0.34, 0.42, (0, -0.21, 0), "brass", parent=pivot)
    cyl("lens", 0.26, 0.46, (0, -0.24, 0), "lens", parent=pivot)
    ring("iris", 0.2, 0.022, (0, -0.47, 0), "iris", parent=pivot)
    ring("bezel", 0.35, 0.03, (0, -0.42, 0), "brass", parent=pivot)


def floor_panel():
    """The panels that shuttle over the pit: 2.4 x 2.4 x 0.4, origin at the center, a band of her light."""
    box("body", (2.4, 2.4, 0.4), (0, 0, 0), "steel", bevel=0.03)
    box("top", (2.25, 2.25, 0.03), (0, 0, 0.19), "tile", bevel=0.008)
    box("band", (2.42, 2.42, 0.05), (0, 0, -0.05), "seam_light")
    for k, (x, y) in enumerate([(1.15, 0), (-1.15, 0), (0, 1.15), (0, -1.15)]):
        size = (0.06, 2.2, 0.012) if x else (2.2, 0.06, 0.012)
        box(f"hazard{k}", size, (x * 0.96, y * 0.96, 0.2), "hazard")


def cube():
    """Her evaluation cube: a steel frame, tile faces, a ring of her light on every face."""
    box("frame", (0.6, 0.6, 0.6), (0, 0, 0), "steel", bevel=0.04)
    faces = [((0, 0, 0.3), (0, 0, 0)), ((0, 0, -0.3), (math.pi, 0, 0)), ((0.3, 0, 0), (0, math.pi / 2, 0)),
             ((-0.3, 0, 0), (0, -math.pi / 2, 0)), ((0, 0.3, 0), (-math.pi / 2, 0, 0)), ((0, -0.3, 0), (math.pi / 2, 0, 0))]
    for k, (at, rot) in enumerate(faces):
        box(f"face{k}", (0.44, 0.44, 0.02), at, "tile", bevel=0.008, rotation=rot)
        ring(f"ring{k}", 0.13, 0.012, tuple(c * 1.07 for c in at), "iris", rotation=rot)


def button():
    """The floor button: a steel base, a hazard ring, the plate. Origin on the floor."""
    cyl("base", 0.85, 0.08, (0, 0, 0.04), "steel", rotation=(0, 0, 0), vertices=64)
    ring("hazard", 0.74, 0.03, (0, 0, 0.085), "hazard", rotation=(0, 0, 0))
    cyl("plate", 0.6, 0.06, (0, 0, 0.11), "button_top", rotation=(0, 0, 0), vertices=64)


def door():
    """A sliding door of six tiles on a steel back, with a slit of her light. Origin at the center."""
    box("back", (2.0, 0.24, 3.0), (0, 0, 0), "steel", bevel=0.02)
    for col in range(2):
        for row in range(3):
            if row == 1:
                continue
            box(f"panel{col}{row}", (0.95, 0.08, 0.95), (-0.49 + col * 0.98, -0.14, -0.98 + row * 0.98), "tile", bevel=0.015)
    box("slit", (1.9, 0.06, 0.14), (0, -0.11, 0), "seam_light")
    box("slit_frame", (1.96, 0.04, 0.9), (0, -0.13, 0), "steel")


def turret():
    """A corporate turret: a smooth body on three legs, one eye. Origin on the floor; the eye at 0.85 m."""
    sphere("body", 0.34, (0, 0, 0.85), "tile", scale=(1, 0.85, 1.45))
    box("collar", (0.5, 0.42, 0.06), (0, 0, 0.55), "steel", bevel=0.02)
    cyl("lens", 0.11, 0.1, (0, -0.28, 0.9), "lens", vertices=32)
    ring("iris", 0.085, 0.012, (0, -0.33, 0.9), "iris")
    for k in range(3):
        angle = k * 2 * math.pi / 3
        x, y = 0.32 * math.cos(angle), 0.32 * math.sin(angle)
        cyl(f"leg{k}", 0.03, 0.62, (x * 0.6, y * 0.6, 0.28), "steel",
            rotation=(-math.atan2(y, 0.62) * 0.9, math.atan2(x, 0.62) * 0.9, 0), vertices=16)
    for side in (-1, 1):
        box(f"wing{side}", (0.06, 0.3, 0.5), (side * 0.34, 0, 0.88), "steel", bevel=0.02)


def terminal():
    """Her wall terminal: a steel bezel and a dark screen, set in a hole of 4 x 3 tiles, her light in the
    seam around it. Origin on the back face; Godot writes on it."""
    box("bezel", (3.9, 0.1, 2.9), (0, -0.05, 0), "steel", bevel=0.02)
    box("screen", (3.7, 0.02, 2.7), (0, -0.105, 0), "screen")
    box("lip", (3.9, 0.18, 0.06), (0, -0.09, -1.48), "steel", bevel=0.01)


def core():
    """Her core: neuron W-7 in a glass sphere, held in brass rings on a pedestal, fed by cables that come
    down from 20 m up, out of the dark. Origin on the floor."""
    cyl("pedestal", 0.45, 0.9, (0, 0, 0.45), "steel", rotation=(0, 0, 0), vertices=64)
    cyl("cap", 0.55, 0.06, (0, 0, 0.92), "brass", rotation=(0, 0, 0), vertices=64)
    sphere("neuron", 0.27, (0, 0, 1.45), "iris")
    sphere("glass", 0.48, (0, 0, 1.45), "glass")
    ring("ring_a", 0.62, 0.025, (0, 0, 1.45), "brass", rotation=(math.radians(70), 0, 0))
    ring("ring_b", 0.66, 0.025, (0, 0, 1.45), "brass", rotation=(0, math.radians(70), math.radians(35)))
    for k, (angle, reach, thickness) in enumerate([(40, 2.3, 0.045), (165, 2.2, 0.035), (215, 2.1, 0.05), (265, 1.9, 0.04), (320, 2.2, 0.035)]):
        a = math.radians(angle)
        out = lambda r, z: (r * math.cos(a), r * math.sin(a), z)
        cable(f"cable{k}", [out(reach * 0.8, 20.0), out(reach, 7.0), out(reach * 0.55, 0.12), out(0.47, 0.35)], thickness)


def cable(name, points, thickness):
    """A cable through `points`, sagging between them."""
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = thickness
    curve.bevel_resolution = 3
    curve.resolution_u = 16
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for point, at in zip(spline.bezier_points, points):
        point.co = at
        point.handle_left_type = point.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj.data.materials.append(mat("rubber"))
    bpy.ops.object.shade_smooth()
    obj.select_set(False)
    return obj


def console():
    """The calibration console: a steel stand, a desk sloping toward the technician with a screen and
    neuron W-7's dial, which Godot turns. Origin on the floor; faces -Y."""
    box("plinth", (0.72, 0.56, 0.06), (0, 0.02, 0.03), "steel", bevel=0.01)
    box("stand", (0.56, 0.42, 0.9), (0, 0.04, 0.5), "steel", bevel=0.02)
    tilt = math.radians(30)
    center = (0, -0.04, 1.0)
    across, up_desk, normal = (1, 0, 0), (0, math.cos(tilt), math.sin(tilt)), (0, -math.sin(tilt), math.cos(tilt))
    on = lambda u, v, h: tuple(c + across[i] * u + up_desk[i] * v + normal[i] * h for i, c in enumerate(center))
    box("desk", (0.84, 0.6, 0.07), center, "steel", bevel=0.015, rotation=(tilt, 0, 0))
    box("screen", (0.42, 0.34, 0.01), on(-0.15, 0.04, 0.036), "screen", rotation=(tilt, 0, 0))
    ring("scale", 0.12, 0.008, on(0.24, 0.04, 0.037), "iris", rotation=(tilt, 0, 0))
    dial = cyl("dial", 0.085, 0.05, on(0.24, 0.04, 0.06), "brass", rotation=(tilt, 0, 0), vertices=48)
    pointer = box("pointer", (0.012, 0.06, 0.012), (0, 0.045, 0.03), "iris")
    pointer.parent = dial  # Blender takes its location as relative to the dial: it turns with it
    for k in range(3):
        cyl(f"key{k}", 0.022, 0.02, on(0.12 + k * 0.08, -0.2, 0.04), "button_top" if k == 0 else "rubber",
            rotation=(tilt, 0, 0), vertices=24)


def hatch():
    """Her machinery behind a wall tile, for a tile that slides aside: a steel recess, pistons, cables, and
    status lights in her color. Origin on the wall line, like a tile's; it goes back toward +Y."""
    box("back", (0.95, 0.04, 0.95), (0, 0.47, 0), "steel")
    for k, (size, at) in enumerate([((0.02, 0.47, 0.95), (0.48, 0.235, 0)), ((0.02, 0.47, 0.95), (-0.48, 0.235, 0)),
                                    ((0.95, 0.47, 0.02), (0, 0.235, 0.48)), ((0.95, 0.47, 0.02), (0, 0.235, -0.48))]):
        box(f"side{k}", size, at, "steel")
    for k, x in enumerate((-0.28, -0.05, 0.2)):
        cyl(f"piston{k}", 0.035, 0.86, (x, 0.3, 0), "brass", rotation=(0, 0, 0), vertices=24)
        cyl(f"sleeve{k}", 0.05, 0.3, (x, 0.3, -0.2 + 0.18 * k), "steel", rotation=(0, 0, 0), vertices=24)
    for k in range(3):
        x = -0.35 + k * 0.18
        cable(f"cable{k}", [(x, 0.4, 0.46), (x + 0.12, 0.22, 0.05), (x + 0.05, 0.38, -0.46)], 0.018)
    for k in range(4):
        sphere(f"status{k}", 0.012, (0.36, 0.44, 0.3 - k * 0.07), "iris")


def dispenser():
    """The cube dispenser: a glass tube hanging from the ceiling, held in brass rings, a ring of her light
    at its mouth. Origin at the ceiling; the mouth is 3.6 m below it, above the subject's head."""
    cyl("cap", 0.62, 0.4, (0, 0, -0.2), "steel", rotation=(0, 0, 0), vertices=64)
    cyl("tube", 0.48, 3.0, (0, 0, -1.9), "glass", rotation=(0, 0, 0), vertices=64)
    for k, z in enumerate((-0.6, -1.6, -2.6)):
        ring(f"band{k}", 0.5, 0.035, (0, 0, z), "brass", rotation=(0, 0, 0))
    cyl("mouth", 0.56, 0.12, (0, 0, -3.5), "steel", rotation=(0, 0, 0), vertices=64)
    ring("mouth_light", 0.5, 0.02, (0, 0, -3.57), "iris", rotation=(0, 0, 0))


def ceiling_light():
    """A ceiling light strip: a steel housing and a cool white diffuser underneath. Origin at the center."""
    box("housing", (6.0, 0.28, 0.12), (0, 0, 0), "steel", bevel=0.01)
    box("diffuser", (5.9, 0.18, 0.02), (0, 0, -0.065), "strip_light")


PIECES = {f.__name__: f for f in (tile, eye, hatch, floor_panel, cube, button, door, turret, terminal, core, console, dispenser, ceiling_light)}


def preview(name):
    """A quick EEVEE render, framed on the model, to check it."""
    objs = [o for o in bpy.data.objects if o.type == "MESH"]
    lo = [min(v[i] for o in objs for v in (o.matrix_world @ c for c in [__import__("mathutils").Vector(b) for b in o.bound_box])) for i in range(3)]
    hi = [max(v[i] for o in objs for v in (o.matrix_world @ c for c in [__import__("mathutils").Vector(b) for b in o.bound_box])) for i in range(3)]
    center = [(a + b) / 2 for a, b in zip(lo, hi)]
    size = max(b - a for a, b in zip(lo, hi))
    target = empty("aim", center)
    bpy.ops.object.camera_add(location=(center[0] + size * 1.1, center[1] - size * 1.6, center[2] + size * 0.7))
    cam = bpy.context.active_object
    track = cam.constraints.new("TRACK_TO")
    track.target = target
    track.track_axis = "TRACK_NEGATIVE_Z"
    track.up_axis = "UP_Y"
    cam.data.lens = 50
    bpy.ops.object.light_add(type="AREA", location=(center[0] - size, center[1] - size * 1.5, center[2] + size * 2))
    key = bpy.context.active_object
    key.data.energy = 400 * size * size
    key.data.size = size * 2
    key.rotation_euler = (0.6, 0, -0.5)
    world = bpy.data.worlds.new("world")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.05, 0.05, 0.06, 1)
    scene = bpy.context.scene
    scene.world = world
    scene.camera = cam
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = scene.render.resolution_y = 420
    scene.view_settings.view_transform = "AgX"
    scene.render.filepath = os.path.join(RENDERS, f"model_{name}.png")
    bpy.ops.render.render(write_still=True)


def main():
    wanted = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else list(PIECES)
    os.makedirs(MODELS, exist_ok=True)
    os.makedirs(RENDERS, exist_ok=True)
    for name in wanted:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        PIECES[name]()
        path = os.path.join(MODELS, f"{name}.glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_yup=True)
        preview(name)
        print(f"MODEL {name}: {os.path.getsize(path) // 1024} KB")


if __name__ == "__main__":
    main()
