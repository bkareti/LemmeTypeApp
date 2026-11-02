#!/usr/bin/env python3
"""Render the LemmeType app icons from one vector definition of the "L." mark.

The geometry is the L in "Logos/Jade teal LemmeType logo with white wordmark-1.png",
measured in that image's pixel space (1816 x 866). Everything else is derived, so the
Mac and iPhone/iPad icons cannot drift apart:

    Design/AppIcon/*.svg                                   vector masters
    App/LemmeType/Assets.xcassets/AppIcon.appiconset       Mac: 16-512 pt at 1x and 2x
    App/LemmeTypeiOS/Assets.xcassets/AppIcon.appiconset    iPhone/iPad: light, dark, tinted

Needs rsvg-convert (`brew install librsvg`). The PNGs are committed, so a normal build
does not need it; run this only when the artwork changes (`make app-icons`).

    scripts/make-app-icons.py [--root <repository root>]
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

JADE = "#03A58D"  # median colour of the L in the source logo
WHITE = "#FFFFFF"
NIGHT = "#0A1A17"  # dark-appearance background (the wordmark's natural canvas)
BLACK = "#000000"

# The L and its separate "dot" block, in the source logo's pixels. The stem is 157 wide
# with a semicircular cap; the outer corner radius is 208 and the inner one 78.
MARK_PATHS = (
    "M177 272.5A78.5 78.5 0 0 1 334 272.5L334 524A78 78 0 0 0 412 602"
    "L552 602L552 726L385 726A208 208 0 0 1 177 518Z",
    "M595 568H676V726H595Z",
)
MARK_CENTER = (426.5, 460.0)  # centre of the mark's bounding box (x 177-676, y 194-726)

# The mark is about half the icon's height, as in Apple's own app icons.
IOS_MARK_SCALE = 1.0  # 532 px tall on a 1024 canvas
MAC_TILE = (100, 100, 824, 824, 185)  # x, y, width, height, corner radius (Apple's grid)
MAC_MARK_SCALE = IOS_MARK_SCALE * MAC_TILE[2] / 1024

MAC_SIZES = (16, 32, 128, 256, 512)  # points; each is written at 1x and 2x


def mark(fill: str, scale: float) -> str:
    tx = 512 - scale * MARK_CENTER[0]
    ty = 512 - scale * MARK_CENTER[1]
    paths = "".join(f'<path d="{d}"/>' for d in MARK_PATHS)
    return f'<g fill="{fill}" transform="translate({tx:.2f} {ty:.2f}) scale({scale:.4f})">{paths}</g>'


def svg(body: str, defs: str = "") -> str:
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n'
        f"<title>LemmeType app icon</title>\n{defs}{body}\n</svg>\n"
    )


def square(color: str) -> str:
    return f'<rect width="1024" height="1024" fill="{color}"/>'


def mac_svg() -> str:
    x, y, w, h, r = MAC_TILE
    shadow = (
        '<defs><filter id="shadow" x="-10%" y="-10%" width="120%" height="125%">'
        '<feGaussianBlur in="SourceAlpha" stdDeviation="12"/><feOffset dy="10" result="soft"/>'
        '<feFlood flood-color="#000" flood-opacity="0.28"/><feComposite in2="soft" operator="in"/>'
        '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>\n'
    )
    tile = f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{JADE}" filter="url(#shadow)"/>'
    return svg(tile + mark(WHITE, MAC_MARK_SCALE), shadow)


# name -> (svg text, file name in the iOS catalog, appearance in Contents.json or None)
def ios_variants() -> dict[str, tuple[str, str, str | None]]:
    return {
        "ios.svg": (svg(square(JADE) + mark(WHITE, IOS_MARK_SCALE)), "AppIcon-1024.png", None),
        "ios-dark.svg": (svg(square(NIGHT) + mark(JADE, IOS_MARK_SCALE)), "AppIcon-Dark-1024.png", "dark"),
        "ios-tinted.svg": (svg(square(BLACK) + mark(WHITE, IOS_MARK_SCALE)), "AppIcon-Tinted-1024.png", "tinted"),
    }


def render(svg_path: Path, pixels: int, out: Path) -> None:
    subprocess.run(
        ["rsvg-convert", "-w", str(pixels), "-h", str(pixels), str(svg_path), "-o", str(out)],
        check=True,
    )


def assert_no_alpha(path: Path) -> None:
    """The App Store rejects an iOS icon with an alpha channel; rsvg-convert omits it for opaque art."""
    color_type = path.read_bytes()[25]  # IHDR colour type: 2 = RGB, 6 = RGBA
    assert color_type == 2, f"{path.name} has an alpha channel"


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n")


def make_catalog(root: Path) -> Path:
    root.mkdir(parents=True, exist_ok=True)
    write_json(root / "Contents.json", {"info": {"author": "xcode", "version": 1}})
    icons = root / "AppIcon.appiconset"
    shutil.rmtree(icons, ignore_errors=True)
    icons.mkdir()
    return icons


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    root: Path = parser.parse_args().root
    if shutil.which("rsvg-convert") is None:
        print("Missing rsvg-convert: brew install librsvg", file=sys.stderr)
        return 1

    design = root / "Design" / "AppIcon"
    design.mkdir(parents=True, exist_ok=True)

    # Mac: a rounded tile with a margin and shadow, because macOS does not mask icons itself.
    (design / "macos.svg").write_text(mac_svg())
    mac = make_catalog(root / "App" / "LemmeType" / "Assets.xcassets")
    mac_images = []
    for points in MAC_SIZES:
        for scale in (1, 2):
            name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
            render(design / "macos.svg", points * scale, mac / name)
            mac_images.append(
                {"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{points}x{points}"}
            )
    write_json(mac / "Contents.json", {"images": mac_images, "info": {"author": "xcode", "version": 1}})

    # iPhone and iPad: full-bleed squares; iOS applies the mask. Dark and tinted are the
    # appearances iOS 18 and later offer on the Home Screen.
    ios = make_catalog(root / "App" / "LemmeTypeiOS" / "Assets.xcassets")
    ios_images = []
    for source, (text, filename, appearance) in ios_variants().items():
        (design / source).write_text(text)
        render(design / source, 1024, ios / filename)
        assert_no_alpha(ios / filename)
        image: dict[str, object] = {"filename": filename, "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        if appearance:
            image["appearances"] = [{"appearance": "luminosity", "value": appearance}]
        ios_images.append(image)
    write_json(ios / "Contents.json", {"images": ios_images, "info": {"author": "xcode", "version": 1}})

    print(f"Wrote {len(mac_images)} Mac icons and {len(ios_images)} iPhone/iPad icons.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
