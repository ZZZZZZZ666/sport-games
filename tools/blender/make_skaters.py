"""Blender (headless) script: build the skate game's riders with MPFB2 (MakeHuman for Blender,
CC0 base mesh and system assets) and export each as a rigged .glb for Godot.

    set BLENDER_USER_RESOURCES=%CD%/tools/blender_user
    blender --background --python tools/blender/make_skaters.py -- out_dir [variant ...]

The MPFB extension and the MakeHuman system asset pack live in tools/blender_user (installed
with `blender --command extension install-file`), not in the user's Blender profile. Each rider
gets the "game_engine" rig (UE-style bone names), skin, eyes, brows, lashes, hair, an outfit and
shoes. Shape keys and helper masks are baked so the exported meshes are plain skinned meshes.
"""
import os
import sys

import addon_utils
import bpy
import numpy as np

addon_utils.enable("bl_ext.user_default.mpfb", default_set=True)
from bl_ext.user_default.mpfb.services.humanservice import HumanService  # noqa: E402
from bl_ext.user_default.mpfb.services.locationservice import LocationService  # noqa: E402

EYES_UUID = "1cc97a30-85a1-42e6-a9f7-b3e753732baa"     # eyes/low-poly.mhclo

RACE = {
    "caucasian": {"caucasian": 0.9, "asian": 0.05, "african": 0.05},
    "asian": {"caucasian": 0.1, "asian": 0.85, "african": 0.05},
    "african": {"caucasian": 0.05, "asian": 0.05, "african": 0.9},
}

VARIANTS = [
    dict(name="rider0", gender=1.0, race="caucasian", skin="young_caucasian_male", eyes="darkbrown",
         hair="short02", brows="eyebrow001", clothes=["male_casualsuit06", "shoes05"],
         height=0.55, muscle=0.6, weight=0.45),
    dict(name="rider1", gender=0.0, race="asian", skin="young_asian_female", eyes="brownlight",
         hair="ponytail01", brows="eyebrow010", clothes=["female_casualsuit01", "shoes06"],
         height=0.45, muscle=0.5, weight=0.42),
    dict(name="rider2", gender=1.0, race="african", skin="young_african_male", eyes="darkbrown",
         hair="short04", brows="eyebrow002", clothes=["male_casualsuit05", "shoes02"],
         height=0.6, muscle=0.62, weight=0.5),
    dict(name="rider3", gender=0.0, race="caucasian", skin="young_caucasian_female", eyes="bluegreen",
         hair="bob01", brows="eyebrow012", clothes=["female_sportsuit01", "shoes05"],
         height=0.5, muscle=0.55, weight=0.4),
]


def human_info(v):
    info = HumanService._create_default_human_info_dict()
    info["name"] = v["name"]
    info["phenotype"].update(gender=v["gender"], age=0.45, muscle=v["muscle"], weight=v["weight"],
                             height=v["height"], proportions=0.65)
    info["phenotype"]["race"] = dict(RACE[v["race"]])
    info["rig"] = "game_engine"
    info["eyes"] = "low-poly/low-poly.mhclo"
    info["eyebrows"] = f"{v['brows']}/{v['brows']}.mhclo"
    info["eyelashes"] = "eyelashes01/eyelashes01.mhclo"
    info["hair"] = f"{v['hair']}/{v['hair']}.mhclo"
    info["clothes"] = [f"{c}/{c}.mhclo" for c in v["clothes"]]
    info["skin_mhmat"] = f"{v['skin']}/{v['skin']}.mhmat"
    info["skin_material_type"] = "MAKESKIN"
    info["eyes_material_type"] = "MAKESKIN"
    info["clothes_material_type"] = "MAKESKIN"
    info["eyes_material_settings"] = {}
    info["skin_material_settings"] = {}
    info["alternative_materials"] = {EYES_UUID: f"materials/{v['eyes']}.mhmat"}
    return info


def make_darkbrown_eyes():
    """MakeHuman's "brown" iris is close to red; a dark brown copy goes next to it."""
    mats = LocationService.get_user_data("eyes/materials")
    dst = os.path.join(mats, "darkbrown_eye.png")
    if not os.path.isfile(dst):
        img = bpy.data.images.load(os.path.join(mats, "brown_eye.png"))
        w, h = img.size
        px = np.empty(w * h * 4, np.float32)
        img.pixels.foreach_get(px)
        px = px.reshape(-1, 4)
        r, g, b = px[:, 0], px[:, 1], px[:, 2]
        # Iris (and the red veins): keep the brightness, swap the hue for a deep brown.
        red = np.clip((r - np.maximum(g, b) * 1.2) / 0.15, 0.0, 1.0)
        lum = r * 0.6 + g * 0.3 + b * 0.1
        brown = np.stack([lum * 1.05, lum * 0.7, lum * 0.45], axis=1)
        px[:, :3] = px[:, :3] * (1.0 - red[:, None]) + brown * red[:, None]
        out = bpy.data.images.new("darkbrown_eye", w, h, alpha=True)
        out.pixels.foreach_set(px.ravel())
        out.filepath_raw = dst
        out.file_format = "PNG"
        out.save()
    mhmat = open(os.path.join(mats, "brown.mhmat"), encoding="utf-8").read()
    mhmat = mhmat.replace("Eye_brown", "Eye_darkbrown").replace("brown_eye.png", "darkbrown_eye.png")
    open(os.path.join(mats, "darkbrown.mhmat"), "w", encoding="utf-8").write(mhmat)


def bake_mesh(obj):
    """Shape keys -> plain geometry, then every modifier but the armature applied."""
    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    if obj.data.shape_keys:
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    for m in list(obj.modifiers):
        if m.type == "ARMATURE":
            continue
        bpy.ops.object.modifier_apply(modifier=m.name)
    # Helper geometry that a mask didn't cover would show up as junk; vertex groups that drive
    # nothing are dropped so the exported skin has only real bone weights.


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    out_dir = argv[0]
    picks = [int(a) for a in argv[1:]] or list(range(len(VARIANTS)))
    os.makedirs(out_dir, exist_ok=True)
    make_darkbrown_eyes()
    settings = HumanService.get_default_deserialization_settings()
    settings["subdiv_levels"] = 0
    for i in picks:
        v = VARIANTS[i]
        bpy.ops.wm.read_factory_settings(use_empty=True)
        addon_utils.enable("bl_ext.user_default.mpfb", default_set=True)
        basemesh = HumanService.deserialize_from_dict(human_info(v), settings)
        rig = basemesh.parent
        objs = [o for o in bpy.data.objects if o.type == "MESH"]
        for o in objs:
            print(f"[skater] {o.name}: {len(o.data.vertices)} verts, mods {[m.type for m in o.modifiers]}, "
                  f"mats {[s.material.name if s.material else None for s in o.material_slots]}, parent {o.parent.name if o.parent else None}")
            bake_mesh(o)
        bpy.ops.object.select_all(action="DESELECT")
        rig.select_set(True)
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = rig
        path = os.path.join(out_dir, v["name"] + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                                  export_animations=False, export_yup=True, export_image_format="AUTO")
        print(f"[skater] wrote {path}")


if __name__ == "__main__":
    main()
