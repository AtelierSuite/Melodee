"""Album covers for the sample library: mesh gradients only, nothing drawn on them."""

import colorsys
import hashlib
import io
import math
import random

from PIL import Image, ImageFilter


def rng_for(name):
    return random.Random(int(hashlib.sha256(name.encode()).hexdigest()[:16], 16))


def mesh_gradient(name, size, hues):
    """A soft mesh of colours drawn from `hues`, the same every time for the same name.

    Colour points are scattered over the canvas and blended by distance at a low
    resolution, then scaled up, which keeps the blends free of banding.
    """
    rng = rng_for(name)
    points = []
    for index in range(rng.randint(6, 8)):
        hue = (hues[index % len(hues)] + rng.uniform(-18, 18)) % 360
        red, green, blue = colorsys.hsv_to_rgb(hue / 360, rng.uniform(0.35, 0.8), rng.uniform(0.7, 1.0))
        points.append((rng.uniform(-0.15, 1.15), rng.uniform(-0.15, 1.15), (red, green, blue)))
    small_size = 72
    spread = rng.uniform(0.09, 0.14)
    small = Image.new("RGB", (small_size, small_size))
    for y in range(small_size):
        for x in range(small_size):
            u, v = x / (small_size - 1), y / (small_size - 1)
            totals = [0.0, 0.0, 0.0]
            weight_sum = 0.0
            for point_x, point_y, colour in points:
                weight = math.exp(-((u - point_x) ** 2 + (v - point_y) ** 2) / spread)
                weight_sum += weight
                for channel in range(3):
                    totals[channel] += colour[channel] * weight
            small.putpixel((x, y), tuple(int(255 * total / weight_sum) for total in totals))
    smooth = small.resize((size, size), Image.BICUBIC)
    return smooth.filter(ImageFilter.GaussianBlur(radius=size / 60))


def cover_jpeg(name, hues, size=800):
    buffer = io.BytesIO()
    mesh_gradient(name, size, hues).save(buffer, format="JPEG", quality=90)
    return buffer.getvalue()
