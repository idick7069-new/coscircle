"""Export the approved CosCircle silhouette as a 128px pixel asset."""
from pathlib import Path

from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/design/assets/approved-calendar-handshake-logo.png"


def draw_mark() -> Image.Image:
    with Image.open(SOURCE) as artwork:
        # The approved artwork places its wordmark below the emblem.
        emblem = artwork.convert("RGB").crop((260, 160, 992, 980))

    palette = Image.new("RGBA", emblem.size)
    colors = []
    for red, green, blue in emblem.getdata():
        if max(red, green, blue) - min(red, green, blue) < 65:
            colors.append((0, 0, 0, 0))
        elif green > red:
            colors.append((109, 227, 206, 255))
        elif green > blue + 65:
            colors.append((244, 238, 218, 255))
        else:
            colors.append((179, 165, 255, 255))
    palette.putdata(colors)

    mark = ImageOps.contain(palette.crop(palette.getbbox()), (56, 56), Image.Resampling.NEAREST)
    canvas = Image.new("RGBA", (64, 64))
    canvas.paste(mark, ((64 - mark.width) // 2, (64 - mark.height) // 2))
    return canvas


if __name__ == "__main__":
    draw_mark().resize((128, 128), Image.Resampling.NEAREST).save(
        ROOT / "assets/brand/coscircle-mark.png"
    )
