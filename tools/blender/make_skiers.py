"""Blender (headless) script: build the ski game's skiers with MPFB2 (same pipeline as
make_skaters.py) and export each as a rigged .glb for Godot.

    set BLENDER_USER_RESOURCES=%CD%/tools/blender_user
    blender --background --python tools/blender/make_skiers.py -- out_dir [variant ...]

MakeHuman has no ski wear, so the outfits are split for the game to dress: every UV island of
the clothes becomes "jacket" (above the hips) or "pants" (below), and the hands of the skin
become "glove". Godot repaints those three as nylon in the player's colours and adds the
helmet, goggles, boots, skis and poles itself (RSSkierRig).
"""
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_skaters as ms  # noqa: E402
from make_skaters import HumanService, addon_utils  # noqa: E402

VARIANTS = [
    dict(name="skier0", gender=1.0, race="asian", skin="young_asian_male", eyes="darkbrown",
         hair="short01", brows="eyebrow004", clothes=["male_casualsuit05", "shoes03"],
         height=0.55, muscle=0.6, weight=0.48),
    dict(name="skier1", gender=0.0, race="caucasian", skin="young_caucasian_female", eyes="lightblue",
         hair="long01", brows="eyebrow011", clothes=["male_casualsuit05", "shoes06"],
         height=0.5, muscle=0.5, weight=0.42),
    dict(name="skier2", gender=1.0, race="caucasian", skin="young_caucasian_male", eyes="green",
         hair="short03", brows="eyebrow006", clothes=["male_casualsuit03", "shoes02"],
         height=0.62, muscle=0.62, weight=0.5),
    dict(name="skier3", gender=0.0, race="african", skin="young_african_female", eyes="brown",
         hair="braid01", brows="eyebrow009", clothes=["male_casualsuit02", "shoes05"],
         height=0.47, muscle=0.55, weight=0.44),
]

HAND_BONES = ("hand_", "thumb_", "index_", "middle_", "ring_", "pinky_")
LEG_BONES = ("thigh_", "calf_", "foot_", "ball_")


def split_clothes(obj, bones):
    """UV islands skinned mostly to the legs -> a "pants" copy of the material, the rest
    (torso and sleeves) -> "jacket"."""
    groups = {g.index: g.name for g in obj.vertex_groups if g.name in bones}
    leg = []
    for v in obj.data.vertices:
        w_leg = sum(g.weight for g in v.groups if groups.get(g.group, "").startswith(LEG_BONES))
        w_all = sum(g.weight for g in v.groups if g.group in groups) or 1.0
        leg.append(w_leg / w_all)
    base = obj.material_slots[0].material
    jacket = base.copy()
    jacket.name = "jacket"
    pants = base.copy()
    pants.name = "pants"
    obj.data.materials.clear()
    obj.data.materials.append(jacket)
    obj.data.materials.append(pants)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    uv = bm.loops.layers.uv.active
    parent = list(range(len(bm.faces)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    bm.faces.ensure_lookup_table()
    for e in bm.edges:
        lf = e.link_faces
        if len(lf) != 2:
            continue
        # Same island when the two faces agree on the UVs of both edge ends.
        a, b = lf
        same = True
        for v in e.verts:
            ua = next(lp[uv].uv for lp in a.loops if lp.vert == v)
            ub = next(lp[uv].uv for lp in b.loops if lp.vert == v)
            same = same and (ua - ub).length < 1e-5
        if same:
            parent[find(a.index)] = find(b.index)
    sums = {}
    for f in bm.faces:
        r = find(f.index)
        w = sum(leg[v.index] for v in f.verts) / len(f.verts)
        s = sums.setdefault(r, [0.0, 0.0])
        s[0] += w * f.calc_area()
        s[1] += f.calc_area()
    for f in bm.faces:
        s = sums[find(f.index)]
        f.material_index = 1 if s[0] / max(s[1], 1e-9) > 0.5 else 0
    n_up = sum(1 for f in bm.faces if f.material_index == 0)
    bm.to_mesh(obj.data)
    bm.free()
    print(f"[skier] {obj.name}: {len(sums)} UV islands, {n_up} jacket / {len(obj.data.polygons) - n_up} pants faces")


def add_gloves(obj, bones):
    """Faces weighted (mostly) to hand and finger bones get a "glove" material."""
    groups = {g.index: g.name for g in obj.vertex_groups if g.name in bones}
    glove = obj.material_slots[0].material.copy()
    glove.name = "glove"
    obj.data.materials.append(glove)
    gi = len(obj.data.materials) - 1
    hand = []
    for v in obj.data.vertices:
        w_hand = sum(g.weight for g in v.groups if groups.get(g.group, "").startswith(HAND_BONES))
        w_all = sum(g.weight for g in v.groups if g.group in groups) or 1.0
        hand.append(w_hand / w_all > 0.5)
    n = 0
    for p in obj.data.polygons:
        if sum(hand[i] for i in p.vertices) * 2 >= len(p.vertices):
            p.material_index = gi
            n += 1
    print(f"[skier] {obj.name}: {n} glove faces")


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
        objs = [o for o in bpy.data.objects if o.type == "MESH"]
        for o in objs:
            ms.bake_mesh(o)
        for o in objs:
            nm = o.name.lower()
            if any(c in nm for c in ("casualsuit", "sportsuit", "worksuit")):
                split_clothes(o, set(rig.data.bones.keys()))
            elif o == basemesh:
                add_gloves(o, set(rig.data.bones.keys()))
        bpy.ops.object.select_all(action="DESELECT")
        rig.select_set(True)
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = rig
        path = os.path.join(out_dir, v["name"] + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                                  export_animations=False, export_yup=True, export_image_format="AUTO")
        print(f"[skier] wrote {path}")


if __name__ == "__main__":
    main()
