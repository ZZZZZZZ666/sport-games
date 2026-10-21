"""Write Godot .import files for downloaded textures so they import VRAM-compressed with mipmaps
(headless --import can't detect 3D use, and uncompressed 4K maps would need GBs of VRAM).
Normal maps (names containing "_nor") get RGTC normal-map compression. Existing .import files
are left alone unless --force.

    python -I tools/write_imports.py game/assets/polyhaven [--force]
"""
import os
import sys

TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="{res}"

[params]

compress/mode=2
compress/high_quality={hq}
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map={normal}
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def main():
    root = os.path.abspath(sys.argv[1])
    force = "--force" in sys.argv
    game = root
    while not os.path.exists(os.path.join(game, "project.godot")):
        game = os.path.dirname(game)
    n = 0
    for d, _, files in os.walk(root):
        for f in files:
            if not f.lower().endswith((".jpg", ".jpeg", ".png", ".hdr", ".exr")):
                continue
            path = os.path.join(d, f)
            imp = path + ".import"
            if os.path.exists(imp) and not force:
                continue
            res = "res://" + os.path.relpath(path, game).replace(os.sep, "/")
            normal = "_nor" in f.lower()
            open(imp, "w", newline="\n").write(TEMPLATE.format(res=res, normal=1 if normal else 2, hq="false"))
            n += 1
    print(f"wrote {n} .import files")


if __name__ == "__main__":
    main()
