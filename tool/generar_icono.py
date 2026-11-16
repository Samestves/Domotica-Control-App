"""Genera el icono de la app (casa blanca sobre degradado azul) para Android.

Uso, desde la carpeta del proyecto:
    python tool/generar_icono.py

Crea:
  - assets/icono/icono_1024.png              icono completo, para documentos y tiendas
  - android/.../mipmap-*/ic_launcher.png     icono clásico con esquinas continuas
  - android/.../mipmap-*/ic_launcher_foreground.png   casa sola, para el icono adaptable
  - android/.../drawable/ic_launcher_background.xml   degradado de fondo del icono adaptable
  - android/.../mipmap-anydpi-v26/ic_launcher.xml     icono adaptable (Android 8 o más)
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android/app/src/main/res"
TOP, BOTTOM = (0x3A, 0xA0, 0xFF), (0x00, 0x60, 0xE0)
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
SS = 4  # sobremuestreo para bordes suaves


def gradient(size: int) -> Image.Image:
    """Degradado diagonal de arriba-izquierda a abajo-derecha."""
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM))
    return img


def squircle_mask(size: int, n: float = 5.0) -> Image.Image:
    """Máscara de superelipse: las esquinas continuas de los iconos de iOS."""
    mask = Image.new("L", (size, size), 0)
    r = size / 2
    pts = []
    for i in range(720):
        import math
        a = 2 * math.pi * i / 720
        c, s = math.cos(a), math.sin(a)
        x = r + r * (abs(c) ** (2 / n)) * (1 if c >= 0 else -1)
        y = r + r * (abs(s) ** (2 / n)) * (1 if s >= 0 else -1)
        pts.append((x, y))
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    return mask


def house(size: int, scale: float, color=(255, 255, 255, 255)) -> Image.Image:
    """Casa en una sola silueta con esquinas redondeadas y una puerta en arco recortada.

    `scale` es el ancho del techo respecto del lienzo.
    """
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    w = size * scale
    cx, cy = size / 2, size / 2 + w * 0.06
    stroke = w * 0.10  # el trazo grueso con uniones curvas es lo que redondea las esquinas
    eave, wall, base, apex = cy - w * 0.04, w * 0.38, cy + w * 0.40, cy - w * 0.46
    pts = [
        (cx, apex),
        (cx + w * 0.5, eave), (cx + wall, eave), (cx + wall, base),
        (cx - wall, base), (cx - wall, eave), (cx - w * 0.5, eave),
    ]
    d.polygon(pts, fill=color)
    d.line(pts + [pts[0]], fill=color, width=round(stroke), joint="curve")
    for x, y in pts:
        d.ellipse([x - stroke / 2, y - stroke / 2, x + stroke / 2, y + stroke / 2], fill=color)
    # Puerta en arco: se recorta dejando ver el fondo azul.
    dw = w * 0.10
    # Se extiende bajo la base para que su curva inferior quede fuera de la casa.
    d.rounded_rectangle([cx - dw, base - w * 0.28, cx + dw, base + stroke + dw], radius=dw, fill=(0, 0, 0, 0))
    return img

def render_full(px: int) -> Image.Image:
    big = px * SS
    bg = gradient(big).convert("RGBA")
    glyph = house(big, 0.56)
    icon = Image.alpha_composite(bg, glyph)
    out = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    out.paste(icon, (0, 0), squircle_mask(big))
    return out.resize((px, px), Image.LANCZOS)


def render_foreground(px: int) -> Image.Image:
    """Capa delantera del icono adaptable: 108 dp, con la casa dentro de la zona segura de 66 dp."""
    big = px * SS
    return house(big, 0.42).resize((px, px), Image.LANCZOS)


def main() -> None:
    (ROOT / "assets/icono").mkdir(parents=True, exist_ok=True)
    render_full(1024).save(ROOT / "assets/icono/icono_1024.png")
    for name, k in DENSITIES.items():
        folder = RES / f"mipmap-{name}"
        folder.mkdir(exist_ok=True)
        render_full(round(48 * k)).save(folder / "ic_launcher.png")
        render_foreground(round(108 * k)).save(folder / "ic_launcher_foreground.png")

    (RES / "drawable").mkdir(exist_ok=True)
    (RES / "drawable/ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!-- Fondo del icono adaptable: el mismo degradado azul del icono completo. -->\n'
        '<shape xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <gradient android:angle="315" android:startColor="#3AA0FF" android:endColor="#0060E0" />\n'
        "</shape>\n",
        encoding="utf-8",
    )
    (RES / "mipmap-anydpi-v26").mkdir(exist_ok=True)
    (RES / "mipmap-anydpi-v26/ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@drawable/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_foreground" />\n'
        "</adaptive-icon>\n",
        encoding="utf-8",
    )
    print("Icono generado.")


if __name__ == "__main__":
    main()
