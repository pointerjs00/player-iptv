"""Rasteriza um ficheiro HTML/SVG num PNG com o Edge sem janela (Windows)."""
import subprocess
import sys
import tempfile
from pathlib import Path

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"


def renderizar(pagina: Path, saida: Path, largura: int, altura: int, transparente: bool = True) -> None:
    with tempfile.TemporaryDirectory() as perfil:
        args = [EDGE, "--headless", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
                f"--user-data-dir={perfil}", f"--window-size={largura},{altura}",
                f"--screenshot={saida}", pagina.resolve().as_uri()]
        if transparente:
            args.insert(2, "--default-background-color=00000000")
        subprocess.run(args, check=True, timeout=90, capture_output=True)
    if not saida.exists():
        raise RuntimeError(f"o Edge não gerou {saida}")


if __name__ == "__main__":
    renderizar(Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]))
