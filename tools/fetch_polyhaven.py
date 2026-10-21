"""Optional authoring helper for adding new CC0 assets from https://polyhaven.com.

For normal project setup, use `node tools/sync_assets.mjs` instead: it restores the
project's exact SHA-256-pinned files and applies the documented privacy cleanup.

    python -I tools/fetch_polyhaven.py textures 4k clean_asphalt patterned_concrete_pavers
    python -I tools/fetch_polyhaven.py models 2k street_lamp_01 fire_hydrant
    python -I tools/fetch_polyhaven.py hdris 4k kloppenheim_06_puresky

Textures: diffuse, OpenGL normal and ARM (AO/roughness/metal = Godot's ORM) as jpg.
Models: the glTF with its .bin and textures, in the layout the .gltf expects.
HDRIs: the .hdr panorama.
Files already there (same size) are skipped. Every asset is listed in CREDITS.md.
"""
import json
import os
import sys
import urllib.request

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "assets", "polyhaven")
API = "https://api.polyhaven.com"
UA = {"User-Agent": "regina-sports-asset-fetch/1.0"}


def get_json(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return json.load(r)


def fetch(url, dest, size=None):
    if os.path.exists(dest) and (size is None or os.path.getsize(dest) == size):
        return False
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    tmp = dest + ".part"
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=300) as r, open(tmp, "wb") as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
    os.replace(tmp, dest)
    return True


def credit(kind, asset_id, info):
    path = os.path.join(ROOT, "CREDITS.md")
    lines = open(path, encoding="utf-8").read().splitlines() if os.path.exists(path) else [
        "# Poly Haven assets", "", "All CC0 (public domain), from https://polyhaven.com.", ""]
    authors = ", ".join(info.get("authors", {}).keys())
    line = f"- {kind[:-1]} `{asset_id}` ({info.get('name', asset_id)}) by {authors}: https://polyhaven.com/a/{asset_id}"
    if line not in lines:
        lines.append(line)
        open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")


def main():
    kind, res, ids = sys.argv[1], sys.argv[2], sys.argv[3:]
    assert kind in ("textures", "models", "hdris"), kind
    for asset_id in ids:
        files = get_json(f"{API}/files/{asset_id}")
        info = get_json(f"{API}/info/{asset_id}")
        out = os.path.join(ROOT, kind, asset_id)
        got = 0
        if kind == "textures":
            for key, short in (("Diffuse", "diff"), ("nor_gl", "nor_gl"), ("arm", "arm")):
                f = files[key][res]["jpg"]
                got += fetch(f["url"], os.path.join(out, f"{asset_id}_{short}_{res}.jpg"), f["size"])
        elif kind == "models":
            g = files["gltf"][res]["gltf"]
            got += fetch(g["url"], os.path.join(out, os.path.basename(g["url"])), g["size"])
            for rel, f in g["include"].items():
                got += fetch(f["url"], os.path.join(out, rel), f["size"])
        else:
            f = files["hdri"][res]["hdr"]
            got += fetch(f["url"], os.path.join(out, f"{asset_id}_{res}.hdr"), f["size"])
        credit(kind, asset_id, info)
        print(f"{asset_id}: {got} new file(s)")


if __name__ == "__main__":
    main()
