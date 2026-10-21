"""Blender (headless) script: build the golf game's players with MPFB2 (same pipeline as
make_skaters.py / make_ballers.py) and export each as a rigged .glb for Godot.

    set BLENDER_USER_RESOURCES=%CD%/tools/blender_user
    blender --background --python tools/blender/make_golfers.py -- out_dir [variant ...]

Golf wear from MakeHuman's casual outfits: long sleeves are cut at the elbow (a polo's short
sleeve), with the forearms taken out of the body's delete mask so the skin shows. The cloth is
split into "jacket" (shirt) and "pants" materials, which Godot repaints (RSGolferRig); the cap
is added in Godot too.
"""
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_skaters as ms  # noqa: E402
import make_skiers as mk  # noqa: E402
from make_skaters import HumanService, addon_utils  # noqa: E402

VARIANTS = [
    dict(name="golfer0", gender=1.0, race="caucasian", skin="middleage_caucasian_male", eyes="blue",
         hair="short03", brows="eyebrow006", clothes=["male_casualsuit04", "shoes03"],
         height=0.6, muscle=0.5, weight=0.55, age=0.62, cut=True),
    dict(name="golfer1", gender=0.0, race="asian", skin="young_asian_female", eyes="brownlight",
         hair="ponytail01", brows="eyebrow010", clothes=["female_casualsuit02", "shoes06"],
         height=0.5, muscle=0.5, weight=0.42, age=0.45, cut=False),
    dict(name="golfer2", gender=1.0, race="african", skin="middleage_african_male", eyes="darkbrown",
         hair="short01", brows="eyebrow002", clothes=["male_casualsuit06", "shoes02"],
         height=0.66, muscle=0.58, weight=0.5, age=0.56, cut=True),
    dict(name="golfer3", gender=0.0, race="caucasian", skin="young_caucasian_female2", eyes="green",
         hair="braid01", brows="eyebrow011", clothes=["female_casualsuit01", "shoes05"],
         height=0.55, muscle=0.48, weight=0.45, age=0.5, cut=False),
]

FOREARM_BONES = ("lowerarm_", "hand_", "thumb_", "index_", "middle_", "ring_", "pinky_")
SLEEVE_CUT = 0.42       ## cloth faces with more forearm weight than this go
SKIN_SHOW = 0.3         ## body vertices with more forearm weight than this are unmasked


def fore_fraction(obj, bones):
    groups = {g.index: g.name for g in obj.vertex_groups if g.name in bones}
    out = []
    for v in obj.data.vertices:
        w_arm = sum(g.weight for g in v.groups if groups.get(g.group, "").startswith(FOREARM_BONES))
        w_all = sum(g.weight for g in v.groups if g.group in groups) or 1.0
        out.append(w_arm / w_all)
    return out


def unmask_forearms(body, suit_name, bones):
    grp = body.vertex_groups.get("Delete." + suit_name)
    if grp is None:
        print(f"[golfer] no delete group for {suit_name}")
        return
    arm = fore_fraction(body, bones)
    drop = [v.index for v in body.data.vertices if arm[v.index] > SKIN_SHOW]
    grp.remove(drop)
    print(f"[golfer] {body.name}: {len(drop)} vertices unmasked")


def cut_sleeves(obj, bones):
    arm = fore_fraction(obj, bones)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    kill = [f for f in bm.faces if sum(arm[v.index] for v in f.verts) / len(f.verts) > SLEEVE_CUT]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.to_mesh(obj.data)
    bm.free()
    print(f"[golfer] {obj.name}: {len(kill)} faces cut, {len(obj.data.polygons)} left")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    out_dir = argv[0]
    picks = [int(a) for a in argv[1:]] or list(range(len(VARIANTS)))
    os.makedirs(out_dir, exist_ok=True)
    ms.make_darkbrown_eyes()
    settings = HumanService.get_default_deserialization_settings()
    settings["subdiv_levels"] = 0
    for i in picks:
        v = VARIANTS[i]
        bpy.ops.wm.read_factory_settings(use_empty=True)
        addon_utils.enable("bl_ext.user_default.mpfb", default_set=True)
        info = ms.human_info(v)
        info["phenotype"]["age"] = v["age"]
        basemesh = HumanService.deserialize_from_dict(info, settings)
        rig = basemesh.parent
        bones = set(rig.data.bones.keys())
        suit = v["clothes"][0]
        objs = [o for o in bpy.data.objects if o.type == "MESH"]
        if v["cut"]:
            unmask_forearms(basemesh, suit, bones)
        for o in objs:
            ms.bake_mesh(o)
        for o in objs:
            if suit in o.name:
                if v["cut"]:
                    cut_sleeves(o, bones)
                mk.split_clothes(o, bones)
        bpy.ops.object.select_all(action="DESELECT")
        rig.select_set(True)
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = rig
        path = os.path.join(out_dir, v["name"] + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                                  export_animations=False, export_yup=True, export_image_format="AUTO")
        print(f"[golfer] wrote {path}")


if __name__ == "__main__":
    main()
