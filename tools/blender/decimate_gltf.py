"""Blender (headless) script: load a glTF, decimate every mesh to a total triangle budget, export
a .gltf (textures in textures_lod/) for the game to use instead of the heavy original.

    blender --background --factory-startup --python tools/blender/decimate_gltf.py -- in.gltf out.gltf 8000
"""
import sys

import bpy


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    src, dst, budget = argv[0], argv[1], int(argv[2])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    deps = bpy.context.evaluated_depsgraph_get()
    total = 0
    for o in meshes:
        total += sum(len(p.vertices) - 2 for p in o.evaluated_get(deps).data.polygons)
    ratio = min(1.0, budget / max(total, 1))
    print(f"[decimate] {src}: {total} tris -> ratio {ratio:.3f}")
    if ratio < 1.0:
        for o in meshes:
            m = o.modifiers.new("dec", "DECIMATE")
            m.decimate_type = "COLLAPSE"
            m.ratio = ratio
            m.use_collapse_triangulate = True
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.modifier_apply(modifier=m.name)
    after = sum(len(p.vertices) - 2 for o in meshes for p in o.data.polygons)
    print(f"[decimate] after: {after} tris")
    # Separate files: the game imports the jpgs with VRAM compression (tools/write_imports.py).
    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLTF_SEPARATE", export_texture_dir="textures_lod",
                              export_apply=True, export_yup=True, export_image_format="AUTO")


main()
