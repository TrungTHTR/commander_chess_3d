"""Run with Blender: blender -b --python-exit-code 1 -P tool/import_blender_models.py -- SOURCE."""

import math
from pathlib import Path
import shutil
import sys

import bpy
from mathutils import Matrix, Vector


PIECE_NAMES = {
    "airforce": "air_force",
    "antiair": "anti_aircraft",
    "hq": "headquarters",
    "sam": "missile",
}


def export_piece(source, destination, piece, lod1_only):
    bpy.ops.wm.open_mainfile(filepath=str(source))
    scene = bpy.context.scene
    scene.frame_set(1)
    originals = list(scene.objects)
    root = bpy.data.objects.new(f"piece_{piece}", None)
    scene.collection.objects.link(root)
    parts = []
    palette = {}

    for original in originals:
        if original.type != "MESH":
            continue
        pedestal = original.name.startswith("Red team base")
        # The ink shell was authored for Blender's backface-culling shader.
        for modifier in list(original.modifiers):
            if modifier.name == "Ink shell":
                original.modifiers.remove(modifier)
            elif modifier.type == "BEVEL":
                modifier.segments = min(modifier.segments, 2)
        depsgraph = bpy.context.evaluated_depsgraph_get()
        evaluated = original.evaluated_get(depsgraph)
        mesh = bpy.data.meshes.new_from_object(evaluated, depsgraph=depsgraph)
        mesh.transform(evaluated.matrix_world)
        for index, material in enumerate(mesh.materials):
            name = "mat_team_ring" if pedestal else material.name
            if name not in palette:
                color = material.diffuse_color[:]
                output = bpy.data.materials.new(name)
                output.use_nodes = True
                shader = output.node_tree.nodes.get("Principled BSDF")
                shader.inputs["Base Color"].default_value = color
                shader.inputs["Roughness"].default_value = 0.72
                palette[name] = output
            mesh.materials[index] = palette[name]
        part = bpy.data.objects.new("base_pedestal" if pedestal else "body_hull", mesh)
        scene.collection.objects.link(part)
        part.parent = root
        parts.append((part, pedestal))

    positions = [vertex.co for part, _ in parts for vertex in part.data.vertices]
    lower = Vector(tuple(min(vertex[i] for vertex in positions) for i in range(3)))
    upper = Vector(tuple(max(vertex[i] for vertex in positions) for i in range(3)))
    extent = upper - lower
    center = Vector(((lower.x + upper.x) / 2, (lower.y + upper.y) / 2, lower.z))
    scale = min(0.78 / max(extent.x, extent.y), 0.85 / extent.z)
    transform = Matrix.Scale(scale, 4) @ Matrix.Translation(-center)

    bpy.ops.object.select_all(action="DESELECT")
    for part, _ in parts:
        part.data.transform(transform)

    merged = []
    for pedestal in (False, True):
        group = [part for part, is_pedestal in parts if pedestal == is_pedestal]
        bpy.ops.object.select_all(action="DESELECT")
        for part in group:
            part.select_set(True)
        active = group[0]
        bpy.context.view_layer.objects.active = active
        if len(group) > 1:
            bpy.ops.object.join()
        merged.append(active)
        active.name = "base_pedestal" if pedestal else "body_hull"
        dissolve = active.modifiers.new("Simplify planar faces", "DECIMATE")
        dissolve.decimate_type = "DISSOLVE"
        dissolve.angle_limit = math.radians(8)
        dissolve.delimit = {"MATERIAL"}
        bpy.ops.object.modifier_apply(modifier=dissolve.name)
        active.data.calc_loop_triangles()
        if len(active.data.loop_triangles) > 1800:
            collapse = active.modifiers.new("Board triangle budget", "DECIMATE")
            collapse.ratio = 1800 / len(active.data.loop_triangles)
            bpy.ops.object.modifier_apply(modifier=collapse.name)

    socket_count = {"tank": 2, "navy": 2, "air_force": 2, "engineer": 1, "headquarters": 1}
    for index in range(socket_count.get(piece, 0)):
        socket = bpy.data.objects.new(f"socket_passenger_{index}", None)
        scene.collection.objects.link(socket)
        socket.parent = root
        socket.location = (-0.13 if index == 0 else 0.13, 0.08, extent.z * scale * 0.72)

    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children:
        child.select_set(True)
    if not lod1_only:
        write_glb(destination)

    for part, triangles in zip(merged, (360, 48)):
        part.data.calc_loop_triangles()
        if len(part.data.loop_triangles) > triangles:
            simplify = part.modifiers.new("Overview triangle budget", "DECIMATE")
            simplify.ratio = triangles / len(part.data.loop_triangles)
            bpy.context.view_layer.objects.active = part
            bpy.ops.object.modifier_apply(modifier=simplify.name)

    write_glb(destination.with_name(destination.name.replace("_lod0.glb", "_lod1.glb")))


def write_glb(destination):
    bpy.ops.export_scene.gltf(
        filepath=str(destination), export_format="GLB", use_selection=True,
        export_animations=False, export_texcoords=False,
    )


def main():
    source_root = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
    lod1_only = "--lod1-only" in sys.argv[sys.argv.index("--") + 2:]
    assets = Path(__file__).resolve().parents[1] / "assets" / "models"
    pieces = assets / "pieces"
    pieces.mkdir(parents=True, exist_ok=True)
    sources = sorted(source_root.glob("*/*.blend"))
    if not sources:
        raise ValueError(f"No faction .blend files found under {source_root}")
    for source in sources:
        faction = "usa" if source.parent.name == "united_states" else source.parent.name
        piece = PIECE_NAMES.get(source.stem, source.stem)
        copy = assets / "blender" / source.parent.name / source.name
        copy.parent.mkdir(parents=True, exist_ok=True)
        if source.resolve() != copy.resolve():
            shutil.copy2(source, copy)
        export_piece(copy, pieces / f"{faction}_{piece}_lod0.glb", piece, lod1_only)


if __name__ == "__main__":
    main()
