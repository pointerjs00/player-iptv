"""Gera os ícones do TVIntel a partir do desenho em SVG (um cérebro em traço com uma TV de
antenas ao centro, nos azuis da app): Android (ícone clássico e adaptativo), banner da Android
TV / Fire TV, o .ico do Windows e o logótipo dentro da app.

Precisa do Pillow e do Microsoft Edge (rasteriza o SVG sem janela). Corre com:
    python ferramentas/gerar_icones.py
"""
import sys
import tempfile
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent / "marca"))
from renderizar import renderizar  # noqa: E402

RAIZ = Path(__file__).resolve().parent.parent
RES = RAIZ / "android" / "app" / "src" / "main" / "res"
SVG = (Path(__file__).resolve().parent / "marca" / "icone.svg").read_text(encoding="utf-8")

# o fundo dos ícones e as cores do desenho: os azuis da app (Tokens.fundo, superficie3, acento, anelFoco)
FUNDO_CLARO, FUNDO_ESCURO = "#1A3A66", "#0A1628"

DENSIDADES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def svg(traco: int = 26) -> str:
    return SVG.replace('stroke-width="26"', f'stroke-width="{traco}"', 1)


def pagina(corpo: str, largura: int, altura: int, fundo: str = "transparent") -> str:
    return (f'<!doctype html><html><head><meta charset="utf-8"><style>html,body{{margin:0;padding:0;'
            f'width:{largura}px;height:{altura}px;overflow:hidden;background:{fundo}}}'
            f'svg{{display:block}}</style></head><body>{corpo}</body></html>')


def com_tamanho(s: str, lado: float, x: float = 0, y: float = 0) -> str:
    return s.replace("<svg ", f'<svg style="position:absolute;left:{x}px;top:{y}px" '
                             f'width="{lado}" height="{lado}" ', 1)


def quadrado(traco: int, escala: float, fundo: bool, lado: int = 1024) -> str:
    """O cérebro centrado num quadrado de `lado`, a `escala` do lado; com ou sem o fundo."""
    t = lado * escala
    corpo = com_tamanho(svg(traco), t, (lado - t) / 2, (lado - t) / 2)
    if fundo:
        corpo = (f'<div style="position:absolute;inset:0;border-radius:{lado * 0.225}px;'
                 f'background:radial-gradient(circle at 30% 20%,{FUNDO_CLARO},{FUNDO_ESCURO} 75%)"></div>'
                 + corpo)
    return pagina(corpo, lado, lado)


def banner() -> str:
    """320x180 (desenhado a 4x): o ícone à esquerda e o nome à direita."""
    l, a = 1280, 720
    icone = com_tamanho(svg(28), 560, 70, 80)
    texto = ('<div style="position:absolute;left:640px;top:0;height:720px;display:flex;align-items:center;'
             'font-family:\'Segoe UI\',Arial,sans-serif;font-weight:700;font-size:170px;letter-spacing:-4px">'
             '<span style="background:linear-gradient(135deg,#8EC5FF,#5A9CFF 55%,#2F7BF6);'
             '-webkit-background-clip:text;color:transparent">TV</span>'
             '<span style="color:#EEF4FF">Intel</span></div>')
    fundo = (f'<div style="position:absolute;inset:0;background:radial-gradient(ellipse at 25% 40%,'
             f'{FUNDO_CLARO},{FUNDO_ESCURO} 70%)"></div>')
    return pagina(fundo + icone + texto, l, a)


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)

        def png(html: str, nome: str, l: int = 1024, a: int = 1024) -> Image.Image:
            (tmp / f"{nome}.html").write_text(html, encoding="utf-8")
            renderizar(tmp / f"{nome}.html", tmp / f"{nome}.png", l, a)
            return Image.open(tmp / f"{nome}.png").convert("RGBA")

        # ícone clássico (Android < 8 e Windows): o cérebro sobre o quadrado arredondado escuro;
        # nos tamanhos pequenos, o traço mais grosso para se ler
        classico = png(quadrado(26, 0.86, True), "classico")
        grosso = png(quadrado(40, 0.9, True), "grosso")
        # adaptativo (Android 8+): só o desenho, dentro da zona segura (66 de 108 dp)
        frente = png(quadrado(28, 0.62, False), "frente")
        # o logótipo dentro da app (sem fundo)
        logo = png(quadrado(34, 1.0, False), "logo")
        ban = png(banner(), "banner", 1280, 720)

    def reduzir(im: Image.Image, lado: int) -> Image.Image:
        return im.resize((lado, lado), Image.LANCZOS)

    for d, f in DENSIDADES.items():
        pasta = RES / f"mipmap-{d}"
        pasta.mkdir(parents=True, exist_ok=True)
        lado = round(48 * f)
        reduzir(grosso if lado <= 72 else classico, lado).save(pasta / "ic_launcher.png")
        reduzir(frente, round(108 * f)).save(pasta / "ic_launcher_foreground.png")

    (RES / "drawable-xhdpi").mkdir(exist_ok=True)
    ban.convert("RGB").resize((320, 180), Image.LANCZOS).save(RES / "drawable-xhdpi" / "banner.png")
    antigo = RES / "drawable" / "banner.png"
    if antigo.exists():
        antigo.unlink()

    # Windows: .ico com todos os tamanhos (os pequenos com o traço grosso)
    tamanhos = [16, 20, 24, 32, 40, 48, 64, 128, 256]
    imagens = [reduzir(grosso if t <= 48 else classico, t) for t in tamanhos]
    imagens[-1].save(RAIZ / "windows" / "runner" / "resources" / "app_icon.ico",
                     sizes=[(t, t) for t in tamanhos], append_images=imagens[:-1])

    (RAIZ / "assets" / "marca").mkdir(parents=True, exist_ok=True)
    reduzir(logo, 256).save(RAIZ / "assets" / "marca" / "logo.png")
    # a pré-visualização em grande (README, loja)
    classico.save(RAIZ / "ferramentas" / "marca" / "icone-1024.png")
    print("ok")


if __name__ == "__main__":
    main()
