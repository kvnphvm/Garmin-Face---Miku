#!/usr/bin/env python3
"""Build Miku's sprite and idle animation from the source GIF.

Writes two things:

  resources/drawables/miku.png   one frame, drawn when the watch is asleep
  build/miku-idle.gif            the full loop, input to Monkey Motion

The fenix 8 Solar's panel is ARGB2222 (see `pixelFormat` in the device's
compiler.json): 8 bits per pixel, two per channel, so the whole colour space is
the 64-point lattice {0, 85, 170, 255}^3. The source sprite uses 15 colours,
none of which land on that lattice.

Nearest-colour rounding is almost right. Its one bad call is the skin: the
lightest tone lands on (255,255,170) and her face turns yellow. Fixing those
six warm tones by hand is enough, and it beats dithering on both counts —
error diffusion speckles a face that is only twelve pixels tall, and because
the pattern is recomputed per frame it crawls when the animation plays.

    python3 tools/generate_miku.py
"""

import os
import sys

try:
    from PIL import Image, ImageSequence
except ImportError:
    sys.exit("Pillow is required: python3 -m pip install --user Pillow")

SOURCE = "PC _ Computer - Miku 'n Pop - Miku Hatsune - Idle.gif"

# The source holds the loop twice over; frames 10-19 are pixel-identical to
# 0-9. Encoding the repeat would double the resource for no visible gain.
LOOP_FRAMES = 10
STATIC_FRAME = 0     # eyes open, arms neutral
FRAME_MS = 100       # 10 fps, which is also Monkey Motion's ceiling
SCALE = 2            # integer only; anything else destroys the pixel grid

LEVELS = (0, 85, 170, 255)

# The source's warm ramp: skin from lightest to darkest, then the hair-tie
# accent. The nearest lattice colour to the lightest skin tone is a sickly
# yellow, so each one is placed by hand instead.
WARM_TONES = {
    (253, 230, 211): (255, 170, 170),
    (229, 185, 164): (255, 170, 170),
    (205, 147, 122): (170, 85, 85),
    (173, 99, 72): (170, 85, 85),
    (91, 48, 37): (85, 0, 0),
    (204, 36, 53): (255, 0, 0),
}


def rgb222_palette():
    """A 1x1 P-mode image carrying the display's full 64-colour palette."""
    entries = []
    for r in LEVELS:
        for g in LEVELS:
            for b in LEVELS:
                entries += [r, g, b]
    palette = Image.new("P", (1, 1))
    palette.putpalette(entries + [0] * (768 - len(entries)))
    return palette


def load_frames(path):
    """The loop, every frame on the same canvas.

    Cropping each frame to its own bounding box would be smaller, but the
    bounds move as she breathes, and the sprite would jitter around the screen
    as a result.
    """
    with Image.open(path) as gif:
        frames = [
            frame.convert("RGBA")
            for frame in ImageSequence.Iterator(gif)
        ][:LOOP_FRAMES]
    if len(frames) < LOOP_FRAMES:
        raise IndexError("expected %d frames in %s" % (LOOP_FRAMES, path))
    return frames


def to_display_colours(frame, palette):
    """Map into the 64-colour display palette, over black.

    The panel reports alphaBlendingSupport: false and the watch face
    background is solid black, so baking the background in is both lossless
    here and one less thing for the resource compiler to interpret.
    """
    opaque = frame.getchannel("A").point(lambda a: 255 if a >= 128 else 0)
    flat = Image.new("RGB", frame.size, (0, 0, 0))
    flat.paste(frame, (0, 0), frame)

    quantized = flat.quantize(palette=palette, dither=Image.NONE).convert("RGB")

    source = frame.load()
    result = quantized.load()
    for y in range(frame.height):
        for x in range(frame.width):
            pixel = source[x, y]
            if pixel[3] < 128:
                continue
            replacement = WARM_TONES.get(pixel[:3])
            if replacement is not None:
                result[x, y] = replacement

    black = Image.new("RGB", frame.size, (0, 0, 0))
    sprite = Image.composite(quantized, black, opaque)
    return sprite.resize(
        (sprite.width * SCALE, sprite.height * SCALE), Image.NEAREST
    )


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    project = os.path.dirname(here)
    source = os.path.join(project, "assets", SOURCE)

    if not os.path.exists(source):
        sys.exit("source sprite sheet not found: %s" % source)

    palette = rgb222_palette()
    sprites = [to_display_colours(f, palette) for f in load_frames(source)]

    still = os.path.join(project, "resources", "drawables", "miku.png")
    sprites[STATIC_FRAME].save(still)

    build = os.path.join(project, "build")
    if not os.path.isdir(build):
        os.makedirs(build)
    loop = os.path.join(build, "miku-idle.gif")
    sprites[0].save(
        loop,
        save_all=True,
        append_images=sprites[1:],
        duration=FRAME_MS,
        loop=0,
    )

    width, height = sprites[0].size
    colours = len(set(sprites[STATIC_FRAME].getdata()))
    print("%dx%d, %d colours" % (width, height, colours))
    print("  still  -> %s" % still)
    print("  %2d fr  -> %s" % (len(sprites), loop))


if __name__ == "__main__":
    main()
