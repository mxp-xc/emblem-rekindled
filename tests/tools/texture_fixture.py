"""Small valid PNGs for texture-import fixtures."""

from io import BytesIO

from PIL import Image


def png(data: bytes) -> bytes:
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return data
    pixels = len(data).to_bytes(4, "big") + data
    pixels += b"\0" * (-len(pixels) % 4)
    image = Image.frombytes("RGBA", (len(pixels) // 4, 1), pixels)
    output = BytesIO()
    image.save(output, format="PNG")
    return output.getvalue()
