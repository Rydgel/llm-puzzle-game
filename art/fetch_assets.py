"""Download the free assets the game uses into game/textures/. All CC0; see ASSETS.md.

    python3 art/fetch_assets.py

Textures are kept out of git: this script reproduces them. Each asset keeps only the maps Godot uses
(color, OpenGL normal, roughness, metalness), renamed to color/normal/roughness/metalness.jpg.
"""

import io
import json
import urllib.request
import zipfile
from pathlib import Path

GAME = Path(__file__).resolve().parent.parent / "game" / "textures"

# name in the game: (ambientCG asset id, resolution)
ASSETS = {
    "tile_plastic": ("Plastic010", "2K"),
    "brushed_metal": ("Metal009", "1K"),
    "concrete_floor": ("Concrete048", "2K"),
    "terrazzo": ("Terrazzo013", "2K"),
}
MAPS = {"Color": "color", "NormalGL": "normal", "Roughness": "roughness", "Metalness": "metalness"}


def fetch(asset_id, resolution):
    query = f"https://ambientcg.com/api/v2/full_json?id={asset_id}&include=downloadData"
    with urllib.request.urlopen(query, timeout=30) as r:
        asset = json.load(r)["foundAssets"][0]
    downloads = asset["downloadFolders"]["default"]["downloadFiletypeCategories"]["zip"]["downloads"]
    url = next(d["fullDownloadPath"] for d in downloads if d["attribute"] == f"{resolution}-JPG")
    request = urllib.request.Request(url, headers={"User-Agent": "vesper-asset-fetch"})
    with urllib.request.urlopen(request, timeout=120) as r:
        return zipfile.ZipFile(io.BytesIO(r.read()))


def main():
    for name, (asset_id, resolution) in ASSETS.items():
        target = GAME / name
        if target.exists() and any(target.iterdir()):
            print(f"{name}: already there")
            continue
        target.mkdir(parents=True, exist_ok=True)
        archive = fetch(asset_id, resolution)
        kept = []
        for member in archive.namelist():
            for suffix, short in MAPS.items():
                if member.endswith(f"_{suffix}.jpg"):
                    (target / f"{short}.jpg").write_bytes(archive.read(member))
                    kept.append(short)
        print(f"{name}: {asset_id} {resolution}, {', '.join(sorted(kept))}")


if __name__ == "__main__":
    main()
