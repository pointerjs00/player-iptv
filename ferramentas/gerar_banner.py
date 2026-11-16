"""Gera o banner da Android TV (320x180) e o ícone (192x192) sem dependências: fundo escuro,
um ecrã azul arredondado e um triângulo de "play". Corre com: python ferramentas/gerar_banner.py"""
import struct
import zlib
from pathlib import Path

FUNDO = (14, 17, 22)
ACENTO = (124, 156, 255)
BRANCO = (255, 255, 255)


def png(largura, altura, pixel):
    linhas = b"".join(
        b"\x00" + b"".join(bytes(pixel(x, y)) for x in range(largura)) for y in range(altura))

    def bloco(tipo, dados):
        return struct.pack(">I", len(dados)) + tipo + dados + struct.pack(">I", zlib.crc32(tipo + dados))

    return (b"\x89PNG\r\n\x1a\n" + bloco(b"IHDR", struct.pack(">IIBBBBB", largura, altura, 8, 2, 0, 0, 0))
            + bloco(b"IDAT", zlib.compress(linhas, 9)) + bloco(b"IEND", b""))


def desenho(largura, altura):
    # ecrã: retângulo arredondado centrado; play: triângulo no centro
    ew, eh = largura * 0.62, altura * 0.62 if largura > altura else altura * 0.5
    ex0, ey0 = (largura - ew) / 2, (altura - eh) / 2
    raio = min(ew, eh) * 0.14
    cx, cy, t = largura / 2, altura / 2, min(ew, eh) * 0.22

    def dentro_ecra(x, y):
        dx = max(ex0 + raio - x, 0, x - (ex0 + ew - raio))
        dy = max(ey0 + raio - y, 0, y - (ey0 + eh - raio))
        return dx * dx + dy * dy <= raio * raio

    def dentro_play(x, y):
        # triângulo com vértices (cx - t*.6, cy - t), (cx - t*.6, cy + t), (cx + t, cy)
        if x < cx - t * 0.6 or x > cx + t:
            return False
        meia = t * (1 - (x - (cx - t * 0.6)) / (t * 1.6))
        return abs(y - cy) <= meia

    def pixel(x, y):
        if dentro_play(x + .5, y + .5):
            return BRANCO
        if dentro_ecra(x + .5, y + .5):
            return ACENTO
        return FUNDO

    return png(largura, altura, pixel)


raiz = Path(__file__).resolve().parent.parent / "android" / "app" / "src" / "main" / "res"
(raiz / "drawable").mkdir(parents=True, exist_ok=True)
(raiz / "drawable" / "banner.png").write_bytes(desenho(320, 180))
for pasta, lado in (("mipmap-mdpi", 48), ("mipmap-hdpi", 72), ("mipmap-xhdpi", 96),
                    ("mipmap-xxhdpi", 144), ("mipmap-xxxhdpi", 192)):
    (raiz / pasta).mkdir(parents=True, exist_ok=True)
    (raiz / pasta / "ic_launcher.png").write_bytes(desenho(lado, lado))
print("ok")
