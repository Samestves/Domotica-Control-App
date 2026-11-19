"""Genera el icono de la app para Android: fondo blanco y el símbolo de la app en negro
(la casa de línea fina con una señal adentro, el mismo de la barra de inicio).

Uso, desde la carpeta del proyecto:
    python tool/generar_icono.py

Crea:
  - assets/icono/icono_1024.png              icono completo, para documentos y tiendas
  - android/.../mipmap-*/ic_launcher.png     icono clásico (Android 7 o más viejo)
  - android/.../mipmap-*/ic_launcher_foreground.png   símbolo solo, para el icono adaptable
  - android/.../drawable/ic_launcher_background.xml   fondo blanco del icono adaptable
  - android/.../mipmap-anydpi-v26/ic_launcher.xml     icono adaptable (Android 8 o más)
  - android/.../drawable*/launch_background.xml       pantalla de arranque clara y oscura
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android/app/src/main/res"
BG = (255, 255, 255, 255)
INK = (10, 11, 13, 255)
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
SS = 4  # sobremuestreo para bordes suaves


def mark(size: int, scale: float, color=INK) -> Image.Image:
    """El símbolo, igual al de la app (AppMark en lib/ui/widgets/kit.dart), centrado en el lienzo.

    `scale` es el lado del símbolo respecto del lienzo.
    """
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = size * scale
    ox = oy = (size - s) / 2

    def p(x, y):
        return (ox + x * s, oy + y * s)

    w = s * 0.065

    def dot(xy, r):
        d.ellipse([xy[0] - r, xy[1] - r, xy[0] + r, xy[1] + r], fill=color)

    def polyline(points):
        pts = [p(*q) for q in points]
        d.line(pts, fill=color, width=round(w), joint="curve")
        for q in pts:  # puntas redondas
            dot(q, w / 2)

    polyline([(0.08, 0.47), (0.5, 0.1), (0.92, 0.47)])  # techo
    polyline([(0.2, 0.38), (0.2, 0.9), (0.8, 0.9), (0.8, 0.38)])  # paredes
    cx, cy = p(0.5, 0.75)
    dot((cx, cy), s * 0.055)
    for r in (0.15, 0.27):  # señal: dos ondas hacia arriba
        rr = s * r
        d.arc([cx - rr - w / 2, cy - rr - w / 2, cx + rr + w / 2, cy + rr + w / 2], 225, 315, fill=color, width=round(w))
        for a in (225, 315):
            dot((cx + rr * math.cos(math.radians(a)), cy + rr * math.sin(math.radians(a))), w / 2)
    return img


def circle_mask(size: int) -> Image.Image:
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).ellipse([0, 0, size - 1, size - 1], fill=255)
    return m


def render_full(px: int, round_shape: bool = True) -> Image.Image:
    big = px * SS
    bg = Image.new("RGBA", (big, big), BG)
    icon = Image.alpha_composite(bg, mark(big, 0.56))
    if round_shape:
        out = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        out.paste(icon, (0, 0), circle_mask(big))
        icon = out
    return icon.resize((px, px), Image.LANCZOS)


def render_foreground(px: int) -> Image.Image:
    """Capa delantera del icono adaptable: 108 dp, con el símbolo dentro de la zona segura de 66 dp."""
    big = px * SS
    return mark(big, 0.46).resize((px, px), Image.LANCZOS)


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def main() -> None:
    (ROOT / "assets/icono").mkdir(parents=True, exist_ok=True)
    render_full(1024, round_shape=False).save(ROOT / "assets/icono/icono_1024.png")
    for name, k in DENSITIES.items():
        folder = RES / f"mipmap-{name}"
        folder.mkdir(exist_ok=True)
        render_full(round(48 * k)).save(folder / "ic_launcher.png")
        render_foreground(round(108 * k)).save(folder / "ic_launcher_foreground.png")

    write(
        RES / "drawable/ic_launcher_background.xml",
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<!-- Fondo del icono adaptable: blanco, como el icono completo. -->\n"
        '<color xmlns:android="http://schemas.android.com/apk/res/android" android:color="#FFFFFF" />\n',
    )
    write(
        RES / "mipmap-anydpi-v26/ic_launcher.xml",
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@drawable/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_foreground" />\n'
        "</adaptive-icon>\n",
    )
    # Pantalla de arranque del color de fondo de la app (claro y oscuro), sin destellos.
    for folder, color, note in [
        ("drawable", "#F3F3F4", "modo claro"),
        ("drawable-v21", "#F3F3F4", "modo claro"),
        ("drawable-night", "#000000", "modo oscuro"),
        ("drawable-night-v21", "#000000", "modo oscuro"),
    ]:
        write(
            RES / folder / "launch_background.xml",
            '<?xml version="1.0" encoding="utf-8"?>\n'
            f"<!-- Pantalla de arranque ({note}): el color del fondo de la app. -->\n"
            '<layer-list xmlns:android="http://schemas.android.com/apk/res/android">\n'
            f'    <item><color android:color="{color}" /></item>\n'
            "</layer-list>\n",
        )
    print("Icono generado.")


if __name__ == "__main__":
    main()
