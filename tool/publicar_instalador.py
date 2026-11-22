"""Arma la página del instalador de placas y, con --publicar, la sube a GitHub Pages (rama gh-pages).

    python tool/publicar_instalador.py             # solo arma build/instalador para revisarla
    python tool/publicar_instalador.py --servir    # la arma y la abre en http://localhost:8765/#prueba
    python tool/publicar_instalador.py --publicar  # la arma y la publica

Qué versión instala cada placa se elige en web/instalador/placas.fuente.json. Los programas salen de
firmware/versiones/<versión>/ (bootloader.bin, partitions.bin, boot_app0.bin y app.bin), con las mismas
direcciones que usa tool/cargar_esp32.ps1. La página comprueba el tamaño y la huella MD5 de cada archivo
antes de instalarlo.
"""
import argparse
import datetime
import functools
import hashlib
import http.server
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "web" / "instalador"
OUT = ROOT / "build" / "instalador"
PARTS = [("bootloader.bin", 0x1000), ("partitions.bin", 0x8000), ("boot_app0.bin", 0xE000), ("app.bin", 0x10000)]
BRANCH = "gh-pages"


def build() -> dict:
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    # El código lleva su huella en el nombre pedido (app.js?v=...): así el navegador nunca mezcla un
    # index.html nuevo con un app.js viejo guardado en su caché.
    def stamp(name: str) -> str:
        return hashlib.md5((SRC / name).read_bytes()).hexdigest()[:10]
    icons_v = stamp("icons.js")
    app = (SRC / "app.js").read_text(encoding="utf-8").replace("'./icons.js'", f"'./icons.js?v={icons_v}'")
    (OUT / "app.js").write_text(app, encoding="utf-8", newline="")
    app_v = hashlib.md5(app.encode("utf-8")).hexdigest()[:10]
    html = (SRC / "index.html").read_text(encoding="utf-8").replace('src="app.js"', f'src="app.js?v={app_v}"')
    (OUT / "index.html").write_text(html, encoding="utf-8", newline="")
    shutil.copy2(SRC / "icons.js", OUT / "icons.js")
    shutil.copytree(SRC / "lib", OUT / "lib")
    (OUT / "fonts").mkdir()
    for name in ("D-DIN.otf", "D-DIN-Bold.otf", "OFL-D-DIN.txt"):
        shutil.copy2(ROOT / "assets" / "fonts" / name, OUT / "fonts" / name)
    (OUT / ".nojekyll").write_text("")  # GitHub Pages sirve los archivos tal cual

    source = json.loads((SRC / "placas.fuente.json").read_text(encoding="utf-8"))
    boards = []
    for b in source["boards"]:
        version = b["version"]
        src_dir = ROOT / "firmware" / "versiones" / version
        if not src_dir.is_dir():
            sys.exit(f"No existe firmware/versiones/{version}")
        dst = OUT / "firmware" / version
        dst.mkdir(parents=True)
        files = []
        for name, address in PARTS:
            data = (src_dir / name).read_bytes()
            if name == "bootloader.bin" and (data[0] != 0xE9 or data[2] != 2 or data[3] != 0x2F):
                sys.exit(f"{version}/bootloader.bin no tiene el encabezado esperado (DIO, 80 MHz, 4 MB)")
            (dst / name).write_bytes(data)
            files.append({
                "name": name,
                "url": f"firmware/{version}/{name}",
                "address": address,
                "size": len(data),
                "md5": hashlib.md5(data).hexdigest(),
            })
        boards.append({k: v for k, v in b.items() if k != "comentario"} | {"files": files})

    manifest = {"updated": datetime.date.today().strftime("%d-%m-%Y"), "boards": boards}
    (OUT / "placas.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Armada en {OUT}: " + ", ".join(b["version"] for b in boards))
    return manifest


def git(*args, cwd=ROOT, check=True):
    return subprocess.run(["git", *args], cwd=cwd, check=check, capture_output=True, text=True)


def publish(manifest: dict):
    versions = ", ".join(b["version"] for b in manifest["boards"])
    remote_has = git("ls-remote", "--heads", "origin", BRANCH).stdout.strip() != ""
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp) / "sitio"
        if remote_has:
            git("fetch", "origin", f"{BRANCH}:refs/remotes/origin/{BRANCH}")
            git("worktree", "add", "--detach", str(work), f"origin/{BRANCH}")
            git("checkout", "-B", BRANCH, cwd=work)
        else:
            git("worktree", "add", "--detach", str(work))
            git("checkout", "--orphan", BRANCH, cwd=work)
        try:
            # Reemplaza todo el sitio por lo recién armado.
            for item in work.iterdir():
                if item.name == ".git":
                    continue
                shutil.rmtree(item) if item.is_dir() else item.unlink()
            for item in OUT.iterdir():
                (shutil.copytree if item.is_dir() else shutil.copy2)(item, work / item.name)
            git("add", "-A", cwd=work)
            if git("diff", "--cached", "--quiet", cwd=work, check=False).returncode == 0:
                print("Sin cambios: la página publicada ya es esta.")
                return
            message = f"Instalador de placas: {versions}\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
            git("commit", "-m", message, cwd=work)
            git("push", "origin", f"HEAD:{BRANCH}", cwd=work)
            print(f"Publicada en la rama {BRANCH}: {versions}")
        finally:
            git("worktree", "remove", "--force", str(work), check=False)
            git("branch", "-D", BRANCH, check=False)


def serve():
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(OUT))
    print("Abriendo http://localhost:8765/#prueba (Ctrl+C para cerrar)")
    http.server.ThreadingHTTPServer(("127.0.0.1", 8765), handler).serve_forever()


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--publicar", action="store_true")
    ap.add_argument("--servir", action="store_true")
    a = ap.parse_args()
    m = build()
    if a.publicar:
        publish(m)
    if a.servir:
        serve()
