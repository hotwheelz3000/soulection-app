#!/usr/bin/env python3
"""Download a site's largest icon and save it as a 1024x1024 opaque PNG.

Usage: fetch-app-icon.py <site-url> <output.png>

Looks at apple-touch-icon / icon <link> tags, the web app manifest, and the
usual fallback paths, downloads each candidate, keeps the largest raster
image (apple-touch-icon wins ties), pads it to a square, scales it to
1024x1024 and flattens any transparency onto black, or onto white when the
artwork itself is dark (a black logo on a transparent background). Requires
Pillow.
"""
import io
import json
import sys
import urllib.request
from html.parser import HTMLParser
from urllib.parse import urljoin

from PIL import Image, ImageStat

USER_AGENT = (
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
)
SIZE = 1024


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.geturl(), resp.read()


class IconLinkParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.icons = []  # (href, is_apple_touch)
        self.manifests = []

    def handle_starttag(self, tag, attrs):
        if tag != "link":
            return
        attrs = {k.lower(): (v or "") for k, v in attrs}
        rel = attrs.get("rel", "").lower().split()
        href = attrs.get("href")
        if not href:
            return
        if "manifest" in rel:
            self.manifests.append(href)
        elif any(r.startswith("apple-touch-icon") for r in rel):
            self.icons.append((href, True))
        elif "icon" in rel:
            self.icons.append((href, False))


def background_for(image):
    """Black, unless the visible artwork is dark enough to vanish on black."""
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A")
    if alpha.getextrema()[0] == 255:
        return (0, 0, 0)  # already opaque; padding only
    visible = alpha.point(lambda a: 255 if a >= 128 else 0)
    if visible.getextrema()[1] == 0:
        return (0, 0, 0)
    mean = ImageStat.Stat(rgba.convert("L"), mask=visible).mean[0]
    return (255, 255, 255) if mean < 96 else (0, 0, 0)


def is_blank(image):
    rgba = image.convert("RGBA")
    if rgba.getchannel("A").getextrema()[1] == 0:
        return True
    return all(lo == hi for lo, hi in rgba.getextrema())


def candidates(site_url):
    page_url, html = fetch(site_url)
    parser = IconLinkParser()
    parser.feed(html.decode("utf-8", errors="replace"))

    found = [(urljoin(page_url, href), apple) for href, apple in parser.icons]
    for href in parser.manifests:
        manifest_url = urljoin(page_url, href)
        try:
            _, data = fetch(manifest_url)
            for icon in json.loads(data).get("icons", []):
                if icon.get("src"):
                    found.append((urljoin(manifest_url, icon["src"]), False))
        except Exception as e:
            print(f"  skipping manifest {manifest_url}: {e}")
    for path, apple in [
        ("/apple-touch-icon.png", True),
        ("/apple-touch-icon-precomposed.png", True),
        ("/favicon.ico", False),
    ]:
        found.append((urljoin(page_url, path), apple))

    seen = set()
    for url, apple in found:
        if url not in seen:
            seen.add(url)
            yield url, apple


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    site_url, out_path = sys.argv[1], sys.argv[2]

    best = None  # (side, apple, url, image)
    for url, apple in candidates(site_url):
        try:
            _, data = fetch(url)
            image = Image.open(io.BytesIO(data))
            image.load()
        except Exception as e:
            print(f"  skipping {url}: {e}")
            continue
        if is_blank(image):
            print(f"  skipping {url}: blank image")
            continue
        side = min(image.size)
        print(f"  found {url}: {image.size[0]}x{image.size[1]}{' (apple-touch-icon)' if apple else ''}")
        if best is None or (side, apple) > best[:2]:
            best = (side, apple, url, image)

    if best is None:
        sys.exit(f"error: no usable icon found at {site_url}")
    _, _, url, image = best
    print(f"Using {url} ({image.size[0]}x{image.size[1]})")

    image = image.convert("RGBA")
    background = background_for(image)
    # Pad to a square so the icon is not distorted.
    side = max(image.size)
    square = Image.new("RGBA", (side, side), background + (255,))
    square.alpha_composite(image, ((side - image.width) // 2, (side - image.height) // 2))
    square = square.resize((SIZE, SIZE), Image.LANCZOS)
    # Flatten onto an opaque background: App Store icons may not have alpha.
    flat = Image.new("RGB", (SIZE, SIZE), background)
    flat.paste(square, mask=square.getchannel("A"))
    flat.save(out_path, "PNG")
    print(f"Wrote {out_path} ({SIZE}x{SIZE}, {flat.mode}, background {background})")


if __name__ == "__main__":
    main()
