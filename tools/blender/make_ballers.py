"""Blender (headless) script: build the basketball game's players with MPFB2 (same pipeline as
make_skaters.py) and export each as a rigged .glb for Godot.

    set BLENDER_USER_RESOURCES=%CD%/tools/blender_user
    blender --background --python tools/blender/make_ballers.py -- out_dir [variant ...]

MakeHuman has no basketball kit, so tee-and-jeans outfits are cut into one: the sleeves come
off (a sleeveless jersey) and the trouser legs end just above the knee (shorts). The body under
the clothes is masked out by MPFB; the arms and lower legs are taken out of that mask before it
is baked so the skin shows where the cloth was cut (with a little overlap under the hems). The
cloth is then split into "jacket" (jersey) and "pants" (shorts) materials, which Godot repaints
in the player's team colours (RSBallerRig).
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
    dict(name="baller0", gender=1.0, race="african", skin="young_african_male", eyes="darkbrown",
         hair="short04", brows="eyebrow002", clothes=["male_casualsuit04", "shoes02"],
         height=0.72, muscle=0.66, weight=0.45),
    dict(name="baller1", gender=0.0, race="asian", skin="young_asian_female", eyes="brownlight",
         hair="ponytail01", brows="eyebrow010", clothes=["female_casualsuit01", "shoes06"],
         height=0.55, muscle=0.55, weight=0.4),
    dict(name="baller2", gender=1.0, race="caucasian", skin="young_caucasian_male", eyes="green",
         hair="short02", brows="eyebrow001", clothes=["male_casualsuit06", "shoes05"],
         height=0.68, muscle=0.62, weight=0.47),
    dict(name="baller3", gender=0.0, race="african", skin="young_african_female", eyes="brown",
         hair="bob01", brows="eyebrow009", clothes=["female_casualsuit02", "shoes05"],
         height=0.55, muscle=0.58, weight=0.42),
]

ARM_BONES = ("upperarm_", "lowerarm_", "hand_", "thumb_", "index_", "middle_", "ring_", "pinky_")
SLEEVE_CUT = 0.42       ## cloth faces with more arm weight than this go
SKIN_SHOW = 0.3         ## body vertices with more arm weight than this are unmasked
SHORTS_ABOVE_KNEE = 0.05
SKIN_OVERLAP = 0.04


def arm_fraction(obj, bones):
    groups = {g.index: g.name for g in obj.vertex_groups if g.name in bones}
    out = []
    for v in obj.data.vertices:
        w_arm = sum(g.weight for g in v.groups if groups.get(g.group, "").startswith(ARM_BONES))
        w_all = sum(g.weight for g in v.groups if g.group in groups) or 1.0
        out.append(w_arm / w_all)
    return out


def unmask_body(body, suit_name, bones, knee_z):
    """Arms and lower legs out of the body's "Delete.<suit>" group, so they are kept."""
    grp = body.vertex_groups.get("Delete." + suit_name)
    if grp is None:
        print(f"[baller] no delete group for {suit_name}")
        return
    arm = arm_fraction(body, bones)
    mw = body.matrix_world
    drop = [v.index for v in body.data.vertices
            if arm[v.index] > SKIN_SHOW or (mw @ v.co).z < knee_z + SHORTS_ABOVE_KNEE + SKIN_OVERLAP]
    grp.remove(drop)
    print(f"[baller] {body.name}: {len(drop)} vertices unmasked")


def cut_suit(obj, bones, knee_z):
    arm = arm_fraction(obj, bones)
    mw = obj.matrix_world
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    kill = []
    for f in bm.faces:
        a = sum(arm[v.index] for v in f.verts) / len(f.verts)
        z = sum((mw @ v.co).z for v in f.verts) / len(f.verts)
        if a > SLEEVE_CUT or z < knee_z + SHORTS_ABOVE_KNEE:
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.to_mesh(obj.data)
    bm.free()
    print(f"[baller] {obj.name}: {len(kill)} faces cut, {len(obj.data.polygons)} left")


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
        basemesh = HumanService.deserialize_from_dict(ms.human_info(v), settings)
        rig = basemesh.parent
        bones = set(rig.data.bones.keys())
        knee_z = (rig.matrix_world @ rig.data.bones["calf_l"].head_local).z
        suit = v["clothes"][0]
        objs = [o for o in bpy.data.objects if o.type == "MESH"]
        unmask_body(basemesh, suit, bones, knee_z)
        for o in objs:
            ms.bake_mesh(o)
        for o in objs:
            if suit in o.name:
                cut_suit(o, bones, knee_z)
                mk.split_clothes(o, bones)
        bpy.ops.object.select_all(action="DESELECT")
        rig.select_set(True)
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = rig
        path = os.path.join(out_dir, v["name"] + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                                  export_animations=False, export_yup=True, export_image_format="AUTO")
        print(f"[baller] wrote {path}")


if __name__ == "__main__":
    main()
