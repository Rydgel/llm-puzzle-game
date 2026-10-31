# Free assets

Every third-party asset in the game, where it comes from and its license. CC0 only. `python3 art/fetch_assets.py`
downloads them into `game/textures/` (kept out of git).

| In the game | Asset | Source | License | Used for |
|---|---|---|---|---|
| `tile_plastic` | Plastic 010, 2K | [ambientCG](https://ambientcg.com/view?id=Plastic010) | CC0 | her wall tiles, tinted warm grey |
| `brushed_metal` | Metal 009, 1K | [ambientCG](https://ambientcg.com/view?id=Metal009) | CC0 | brass and steel: her eyes, frames, machinery |
| `concrete_floor` | Concrete 048, 2K | [ambientCG](https://ambientcg.com/view?id=Concrete048) | CC0 | chamber floors, darkened and polished |
| `terrazzo` | Terrazzo 013, 2K | [ambientCG](https://ambientcg.com/view?id=Terrazzo013) | CC0 | her core and the office areas |

Models are made in Blender from `art/models.py` and need no attribution. The painted signs in `game/decals/` are
rendered by `art/decals.sh` in Noto Sans (SIL Open Font License); the game ships the images, not the font. The sounds in
`game/sounds/` are synthesized by `art/sounds.py`.
