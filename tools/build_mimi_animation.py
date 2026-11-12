import argparse
from pathlib import Path

from PIL import Image, ImageOps


SIZE = 64


def pixel_frames(images: list[Image.Image]) -> list[Image.Image]:
    frames = [image.convert('RGBA').resize((SIZE, SIZE), Image.Resampling.NEAREST)
              for image in images]
    opaque = [pixel[:3] for frame in frames for pixel in frame.getdata()
              if pixel[3] >= 128]
    if not opaque:
        raise ValueError('Expected a visible mascot on a transparent background')
    samples = Image.new('RGB', (len(opaque), 1))
    samples.putdata(opaque)
    palette = samples.quantize(colors=16, method=Image.Quantize.MEDIANCUT)
    indexed = []
    for frame in frames:
        encoded = frame.convert('RGB').quantize(palette=palette, dither=Image.Dither.NONE)
        encoded.putdata([color if alpha >= 128 else 255 for color, alpha in
                         zip(encoded.getdata(), frame.getchannel('A').getdata())])
        encoded.info['transparency'] = 255
        indexed.append(encoded)
    return indexed


def build_static(source: Path, destination: Path, name: str) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    source_image = Image.open(source).convert('RGBA')
    if source_image.size == (SIZE, SIZE):
        source_image.save(destination / f'{name}.png')
        return
    bounds = source_image.getchannel('A').point(lambda alpha: 255 if alpha >= 128 else 0).getbbox()
    if bounds is None:
        raise ValueError('Expected a visible mascot')
    sprite = ImageOps.contain(source_image.crop(bounds), (SIZE - 8, SIZE - 8), Image.Resampling.NEAREST)
    canvas = Image.new('RGBA', (SIZE, SIZE))
    canvas.paste(sprite, ((SIZE - sprite.width) // 2, (SIZE - sprite.height) // 2))
    image = pixel_frames([canvas])[0].convert('RGBA')
    image.save(destination / f'{name}.png')


def build(source: Path, destination: Path, scene: str) -> None:
    sheet = Image.open(source).convert('RGBA')
    if sheet.width < SIZE * 2 or sheet.height < SIZE * 2:
        raise ValueError('Expected a 2x2 sprite sheet with at least 64px per cell')
    frames = [sheet.crop((x * sheet.width // 2, y * sheet.height // 2,
                          (x + 1) * sheet.width // 2, (y + 1) * sheet.height // 2))
              for y in range(2) for x in range(2)]
    indexed = pixel_frames(frames)
    destination.mkdir(parents=True, exist_ok=True)
    gif = destination / f'{scene}.gif'
    indexed[0].save(gif, save_all=True, append_images=indexed[1:],
                    loop=0, duration=[360, 180, 180, 280], disposal=2,
                    transparency=255, optimize=False)
    with Image.open(gif) as result:
        if result.n_frames != 4 or result.info.get('loop') != 0:
            raise ValueError('Animation must contain four looping frames')
        result.convert('RGBA').save(destination / f'{scene}-still.png')
    print(f'{gif}: four frames, {SIZE}x{SIZE}, loop=0, {gif.stat().st_size} bytes')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('scene', choices=['reading', 'map', 'portrait', 'avatar-placeholder'])
    parser.add_argument('--destination', type=Path, default=Path('assets/mimi/cute-v1'))
    args = parser.parse_args()
    if args.scene in ('portrait', 'avatar-placeholder'):
        build_static(args.source, args.destination, args.scene)
    else:
        build(args.source, args.destination, args.scene)
