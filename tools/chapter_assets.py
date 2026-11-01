"""Own shared chapter textures offline; runtime manifests keep ordinary PNG references."""

import json
import os
import re
from pathlib import Path


def texture_import_parameters(path: Path, defaults: dict[str, str]) -> tuple[tuple[str, str], ...]:
    sidecar = Path(str(path) + ".import")
    if not sidecar.exists():
        return tuple(sorted(defaults.items()))
    text = sidecar.read_text()
    if not re.search(r'^importer="texture"$', text, re.M) or "[params]" not in text:
        raise ValueError(f"Expected ordinary Godot texture import: {sidecar}")
    section = text.split("[params]", 1)[1].split("\n[", 1)[0]
    return tuple(
        sorted(
            tuple(line.strip().split("=", 1))
            for line in section.splitlines()
            if line.strip() and not line.lstrip().startswith(";")
        )
    )


def owned_output_paths(directory: Path, names: list[str]) -> list[Path]:
    """Validate ownership before a publisher can copy or remove any output."""
    directory = directory.resolve()
    paths = []
    if not isinstance(names, list):
        raise ValueError(f"Expected an explicit outputs list: {directory}")
    for name in names:
        path = (directory / name).resolve()
        if not path.is_relative_to(directory) or path == directory / "provenance.json":
            raise ValueError(f"Output is outside its owned directory: {name}")
        for parent in path.parents:
            if parent == directory:
                break
            if (parent / "provenance.json").exists():
                raise ValueError(f"Output crosses another owner's directory: {path}")
        paths.append(path)
    if len(paths) != len(set(paths)):
        raise ValueError(f"Duplicate owned output: {directory}")
    return paths


def texture_import_settings(parameters: tuple[tuple[str, str], ...]) -> bytes:
    """Apply explicit parameters; Godot assigns identity to a genuinely new texture."""
    return (
        '[remap]\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n'
        + "\n".join(f"{key}={value}" for key, value in parameters)
        + "\n"
    ).encode()


def share_textures(chapter: Path, *, dry_run: bool = False) -> dict[str, int]:
    """Share byte/parameter-identical owned PNGs and update generated JSON references.

    Each provenance owns an explicit outputs list. Shared filenames are immutable across
    per-battle imports: another battle can retain an older image at the same source name.
    Authored resources and the chapter entry are read only, keeping referenced textures
    at their declared paths. This preserves per-battle regeneration of a private map.
    Validation and the complete write/delete plan precede mutation; dry_run writes nothing.
    """
    chapter = chapter.resolve()
    generated, shared = chapter / "generated", chapter / "generated/shared"
    game = chapter.parents[1]
    shared_provenance = shared / "provenance.json"
    shared_metadata = json.loads(shared_provenance.read_text())
    defaults = shared_metadata["textureImportParameters"]
    owners = {}
    ownership: dict[Path, Path] = {}
    for provenance in sorted(generated.rglob("provenance.json")):
        metadata = json.loads(provenance.read_text())
        owners[provenance] = metadata
        for path in owned_output_paths(provenance.parent, metadata["outputs"]):
            if path in ownership:
                raise ValueError(f"Multiple owners for generated output: {path}")
            if not path.is_file():
                raise ValueError(f"Missing owned output: {path}")
            ownership[path] = provenance
    for path in generated.rglob("*.png"):
        if path not in ownership:
            raise ValueError(f"Unowned generated texture: {path}")
    for path, owner in ownership.items():
        if path.is_relative_to(shared) and owner != shared_provenance:
            raise ValueError(f"A battle cannot own shared output: {path}")
        nearest_owner = max(
            (p for p in owners if path.is_relative_to(p.parent)), key=lambda p: len(p.parts)
        )
        if nearest_owner != owner:
            raise ValueError(f"Output crosses another owner's directory: {path}")

    manifests = {
        p: json.loads(p.read_text()) for p in chapter.rglob("*.json") if p.name != "provenance.json"
    }
    for path in manifests:
        if path.is_relative_to(generated) and path not in ownership:
            raise ValueError(f"Unowned generated manifest: {path}")

    def resolve(value: str, manifest: Path) -> Path | None:
        if not value.endswith(".png"):
            return None
        return (
            game / value[6:] if value.startswith("res://") else manifest.parent / value
        ).resolve()

    def visit(value, manifest, replace=None):
        if isinstance(value, dict):
            return {key: visit(item, manifest, replace) for key, item in value.items()}
        if isinstance(value, list):
            return [visit(item, manifest, replace) for item in value]
        if isinstance(value, str):
            source = resolve(value, manifest)
            if source is not None:
                references.add(source)
                if replace and source in replace:
                    target = replace[source]
                    return (
                        "res://" + target.relative_to(game).as_posix()
                        if value.startswith("res://")
                        else os.path.relpath(target, manifest.parent)
                    )
        return value

    references: set[Path] = set()
    protected: set[Path] = set()
    for manifest, data in manifests.items():
        visit(data, manifest)
        if manifest.is_relative_to(chapter / "authored") or manifest == chapter / "chapter.json":
            protected.update(references)
        references.clear()
    for manifest, data in manifests.items():
        visit(data, manifest)

    # Full bytes are compared directly; filenames and deployment IDs are not identity.
    canonical: dict[tuple[bytes, tuple], Path] = {}
    copies: dict[Path, Path] = {}
    paths = sorted(p for p in ownership if p.suffix == ".png")
    occupied = set(ownership)
    for path in paths:
        if path.is_relative_to(shared):
            canonical.setdefault(
                (path.read_bytes(), texture_import_parameters(path, defaults)), path
            )
    replacements = {}
    for path in paths:
        if path.is_relative_to(shared) or path in protected or path not in references:
            continue
        key = path.read_bytes(), texture_import_parameters(path, defaults)
        destination = canonical.get(key)
        if destination is None:
            destination = shared / path.relative_to(generated)
            suffix = 2
            while destination in occupied or destination.exists():
                destination = destination.with_name(f"{path.stem}_{suffix}.png")
                suffix += 1
            canonical[key] = destination
            occupied.add(destination)
            copies[destination] = path
        replacements[path] = destination

    writes: dict[Path, bytes] = {}
    references.clear()
    updated = {}
    for manifest, data in manifests.items():
        if manifest.is_relative_to(chapter / "authored") or manifest == chapter / "chapter.json":
            updated[manifest] = data
        else:
            updated[manifest] = visit(data, manifest, replacements)
    references.clear()
    for manifest, data in updated.items():
        visit(data, manifest)
        if data != manifests[manifest]:
            writes[manifest] = (json.dumps(data, ensure_ascii=False, indent=2) + "\n").encode()

    live_shared = {path for path in references if path.is_relative_to(shared)}
    if any(path not in ownership and path not in copies for path in live_shared):
        raise ValueError("A manifest references a missing or unowned shared texture")
    deletes = set(replacements)
    deletes.update(
        path for path in paths if path.is_relative_to(shared) and path not in live_shared
    )
    for destination, source in copies.items():
        if destination not in live_shared:
            continue
        writes[destination] = source.read_bytes()
        sidecar = Path(str(source) + ".import")
        if sidecar.exists():
            writes[Path(str(destination) + ".import")] = sidecar.read_bytes()
        else:
            # Apply the declared chapter profile even if project defaults change later.
            writes[Path(str(destination) + ".import")] = texture_import_settings(
                tuple(sorted(defaults.items()))
            )
    for provenance, data in owners.items():
        updated_metadata = dict(data)
        if provenance == shared_provenance:
            outputs = sorted(path.relative_to(shared).as_posix() for path in live_shared)
        else:
            outputs = sorted(
                name
                for name in data["outputs"]
                if (provenance.parent / name).resolve() not in deletes
            )
            sources = dict(data.get("textureSources", {}))
            sources.update(
                {
                    path.relative_to(provenance.parent).as_posix(): destination.relative_to(
                        chapter
                    ).as_posix()
                    for path, destination in replacements.items()
                    if ownership[path] == provenance
                }
            )
            updated_metadata["textureSources"] = {
                name: value
                for name, value in sorted(sources.items())
                if (chapter / value).resolve() in live_shared
            }
        updated_metadata["outputs"] = outputs
        if updated_metadata != data:
            writes[provenance] = (
                json.dumps(updated_metadata, ensure_ascii=False, indent=2) + "\n"
            ).encode()
    for path in tuple(deletes):
        sidecar = Path(str(path) + ".import")
        if sidecar.exists():
            deletes.add(sidecar)
    result = {
        "privateTexturesShared": len(replacements),
        "sharedTextures": len(live_shared),
        "texturesReused": len(replacements) - len(copies),
        "filesWritten": len(writes),
        "filesRemoved": len(deletes),
    }
    if not dry_run:
        for path, data in writes.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        for path in sorted(deletes):
            path.unlink()
    return result
