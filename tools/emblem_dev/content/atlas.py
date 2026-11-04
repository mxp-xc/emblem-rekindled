"""Pack generated textures without losing their logical paths or editable pixels."""

import io
import json
from collections import defaultdict
from pathlib import Path

from PIL import Image, UnidentifiedImageError
from rectpack import MaxRectsBssf, newPacker

from emblem_dev.content.assets import (
    owned_output_paths,
    texture_import_parameters,
    texture_import_settings,
)

ATLAS_SIZE = 1024


def _png(path: Path) -> Image.Image:
    try:
        with Image.open(path) as image:
            if image.format != "PNG" or set(image.info) - {"transparency"}:
                raise ValueError(f"Unsupported PNG metadata: {path}")
            return image.convert("RGBA")
    except (OSError, UnidentifiedImageError) as error:
        raise ValueError(f"Invalid PNG: {path}") from error


def _encoded(image: Image.Image) -> bytes:
    output = io.BytesIO()
    image.save(output, format="PNG")
    return output.getvalue()


def _json(value) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()


def _apply(writes: dict[Path, bytes], deletes: set[Path]) -> None:
    """Restore exact input bytes if an ordinary write or delete fails."""
    touched = set(writes) | deletes
    before = {path: path.read_bytes() if path.exists() else None for path in touched}
    existing_directories = {path.parent for path in writes if path.parent.exists()}
    try:
        for path, content in writes.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        for path in deletes:
            path.unlink()
    except BaseException:
        for path, content in before.items():
            if content is None:
                path.unlink(missing_ok=True)
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(content)
        for directory in sorted(
            {path.parent for path in writes}, key=lambda path: -len(path.parts)
        ):
            if (
                directory not in existing_directories
                and directory.is_dir()
                and not any(directory.iterdir())
            ):
                directory.rmdir()
        raise


def pack_chapter(chapter: Path) -> dict:
    chapter = chapter.resolve()
    generated = chapter / "generated"
    atlas = generated / "atlas"
    if atlas.exists():
        raise ValueError("Chapter is already packed or atlas directory is occupied")
    # Godot reads the application icon before autoloads can register the atlas loader.
    images = sorted(path for path in generated.rglob("*.png") if path != generated / "icon.png")
    if not images:
        raise ValueError("No generated textures to pack")
    owned = set()
    for provenance in generated.rglob("provenance.json"):
        metadata = json.loads(provenance.read_text())
        for path in owned_output_paths(provenance.parent, metadata["outputs"]):
            if path in owned:
                raise ValueError(f"Multiple owners for generated output: {path}")
            owned.add(path)
    if any(path not in owned for path in images):
        raise ValueError("Cannot pack an unowned generated texture")
    defaults = json.loads((generated / "shared/provenance.json").read_text())[
        "textureImportParameters"
    ]
    groups = defaultdict(list)
    sidecars = {}
    for path in images:
        image = _png(path)
        if image.width >= ATLAS_SIZE or image.height >= ATLAS_SIZE:
            raise ValueError(f"Texture is too large for an atlas: {path}")
        settings = texture_import_parameters(path, defaults)
        parameters = dict(settings)
        if (
            parameters.get("compress/mode", "0") != "0"
            or parameters.get("mipmaps/generate", "false") != "false"
            or parameters.get("process/size_limit", "0") != "0"
        ):
            raise ValueError(f"Unsupported atlas import settings: {path}")
        groups[settings].append((path, image))
        sidecar = Path(str(path) + ".import")
        sidecars[path.relative_to(chapter).as_posix()] = (
            sidecar.read_bytes().decode("utf-8") if sidecar.exists() else None
        )
    game = chapter.parents[1]
    textures = {}
    writes = {}
    atlas_number = 0
    for settings, group in sorted(groups.items()):
        packer = newPacker(pack_algo=MaxRectsBssf, rotation=False)
        for index, (_, image) in enumerate(group):
            packer.add_rect(image.width + 1, image.height + 1, rid=index)
        for _ in group:
            packer.add_bin(ATLAS_SIZE, ATLAS_SIZE)
        packer.pack()
        if sum(len(b) for b in packer) != len(group):
            raise ValueError("Some textures could not be packed")
        for packed in packer:
            width = max(rect.x + rect.width for rect in packed)
            height = max(rect.y + rect.height for rect in packed)
            canvas = Image.new("RGBA", (width, height))
            name = f"atlas_{atlas_number:03d}.png"
            target = atlas / name
            atlas_number += 1
            for rect in packed:
                path, image = group[rect.rid]
                canvas.paste(image, (rect.x, rect.y))
                logical = "res://" + path.relative_to(game).as_posix()
                textures[logical] = {
                    "texture": "res://" + target.relative_to(game).as_posix(),
                    "region": [rect.x, rect.y, image.width, image.height],
                }
            writes[target] = _encoded(canvas)
            atlas_settings = dict(settings)
            # Godot's border repair changes transparent RGB across adjacent tiles.
            # The game uses nearest filtering, so preserve the original RGBA bytes.
            atlas_settings["process/fix_alpha_border"] = "false"
            writes[Path(str(target) + ".import")] = texture_import_settings(
                tuple(sorted(atlas_settings.items()))
            )
    manifest = {"schemaVersion": 1, "textures": dict(sorted(textures.items()))}
    writes[atlas / "manifest.json"] = _json(manifest)
    writes[atlas / "provenance.json"] = _json(
        {
            "description": "Generated texture atlases and reversible source metadata",
            "outputs": [p.name for p in sorted(writes) if p.suffix != ".import"],
            "sourceSidecars": sidecars,
        }
    )
    deletes = set(images)
    deletes.update(p for path in images if (p := Path(str(path) + ".import")).exists())
    _apply(writes, deletes)
    return {"textures": len(images), "atlases": atlas_number}


def _region(
    game: Path, atlas: Path, owned: list[Path], definition: dict, images: dict
) -> Image.Image:
    target = definition.get("texture", "")
    if not isinstance(target, str) or not target.startswith("res://"):
        raise ValueError("Invalid atlas reference")
    path = (game / target[6:]).resolve()
    if path not in owned or path.parent != atlas or path.suffix != ".png":
        raise ValueError("Atlas reference is not an owned texture")
    if path not in images:
        images[path] = _png(path)
    region = definition.get("region")
    if not isinstance(region, list) or len(region) != 4 or any(type(v) is not int for v in region):
        raise ValueError("Invalid atlas region")
    x, y, width, height = region
    if (
        x < 0
        or y < 0
        or width <= 0
        or height <= 0
        or x + width > images[path].width
        or y + height > images[path].height
    ):
        raise ValueError("Atlas region is out of bounds")
    return images[path].crop((x, y, x + width, y + height))


def extract_texture(chapter: Path, logical: str, output: Path) -> None:
    """Export one logical texture for editing, without replacing an existing file."""
    chapter = chapter.resolve()
    atlas = chapter / "generated/atlas"
    manifest = json.loads((atlas / "manifest.json").read_text())
    metadata = json.loads((atlas / "provenance.json").read_text())
    if manifest.get("schemaVersion") != 1 or logical not in manifest.get("textures", {}):
        raise ValueError(f"Unknown atlas texture: {logical}")
    image = _region(
        chapter.parents[1],
        atlas,
        owned_output_paths(atlas, metadata["outputs"]),
        manifest["textures"][logical],
        {},
    )
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("xb") as stream:
        stream.write(_encoded(image))


def unpack_chapter(chapter: Path) -> dict:
    chapter = chapter.resolve()
    atlas = chapter / "generated/atlas"
    manifest = json.loads((atlas / "manifest.json").read_text())
    metadata = json.loads((atlas / "provenance.json").read_text())
    if manifest.get("schemaVersion") != 1 or not isinstance(manifest.get("textures"), dict):
        raise ValueError("Invalid atlas manifest")
    owned = owned_output_paths(atlas, metadata["outputs"])
    allowed = set(owned) | {atlas / "provenance.json"}
    allowed.update(Path(str(path) + ".import") for path in owned)
    if any(path.is_dir() or path not in allowed for path in atlas.iterdir()):
        raise ValueError("Atlas directory contains unowned files")
    game = chapter.parents[1]
    source_sidecars = metadata["sourceSidecars"]
    images = {}
    writes = {}
    for logical, definition in manifest["textures"].items():
        if not isinstance(logical, str) or not logical.startswith("res://"):
            raise ValueError("Invalid atlas texture path")
        destination = (game / logical[6:]).resolve()
        if not destination.is_relative_to(chapter / "generated") or destination.is_relative_to(
            atlas
        ):
            raise ValueError(f"Atlas source escapes generated content: {logical}")
        if logical != "res://" + destination.relative_to(game).as_posix():
            raise ValueError(f"Atlas source path is not canonical: {logical}")
        relative = destination.relative_to(chapter).as_posix()
        sidecar_path = Path(str(destination) + ".import")
        if destination.exists() or sidecar_path.exists() or relative not in source_sidecars:
            raise ValueError(f"Atlas source is occupied or missing metadata: {logical}")
        writes[destination] = _encoded(_region(game, atlas, owned, definition, images))
        sidecar = source_sidecars[relative]
        if sidecar is not None:
            if not isinstance(sidecar, str):
                raise ValueError("Invalid atlas source sidecar")
            writes[sidecar_path] = sidecar.encode()
    if len(writes) < len(source_sidecars) or len(manifest["textures"]) != len(source_sidecars):
        raise ValueError("Atlas source metadata does not match its textures")
    deletes = {path for path in atlas.rglob("*") if path.is_file()}
    _apply(writes, deletes)
    atlas.rmdir()
    return {"textures": len(manifest["textures"]), "atlases": len(images)}
