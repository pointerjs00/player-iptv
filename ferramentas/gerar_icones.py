"""Gera os ícones do TVIntel a partir das imagens de origem em ferramentas/marca/:
`icone-origem.webp` (o cérebro com a TV, sobre o fundo escuro) e `banner-origem.webp` (o ícone
com o nome). Produz: Android (ícone clássico e adaptativo), banner da Android TV / Fire TV, o
.ico do Windows e o logótipo dentro da app (sem fundo).

Precisa do Pillow. Corre com:
    python ferramentas/gerar_icones.py
"""
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parent
RES = RAIZ / "android" / "app" / "src" / "main" / "res"
ICONE = AQUI / "marca" / "icone-origem.webp"
BANNER = AQUI / "marca" / "banner-origem.webp"

DENSIDADES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def cor_do_fundo(im: Image.Image) -> tuple[int, int, int]:
    """A cor média dos cantos (o fundo da imagem)."""
    w, h = im.size
    cantos = [im.getpixel(p) for p in ((2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3))]
    return tuple(round(sum(c[i] for c in cantos) / len(cantos)) for i in range(3))


def quadrada(im: Image.Image, fundo) -> Image.Image:
    """Alarga a imagem para um quadrado com a cor do fundo (o desenho fica centrado)."""
    lado = max(im.size)
    q = Image.new("RGB", (lado, lado), fundo)
    q.paste(im, ((lado - im.width) // 2, (lado - im.height) // 2))
    return q


def sem_fundo(im: Image.Image, fundo) -> Image.Image:
    """Tira o fundo escuro ("cor para transparência"): cada píxel fica com a opacidade de quanto
    se afasta do fundo, e a cor sem a mistura com ele. O brilho à volta das linhas fica suave."""
    px = im.convert("RGB").load()
    out = Image.new("RGBA", im.size)
    po = out.load()
    for y in range(im.height):
        for x in range(im.width):
            p = px[x, y]
            a = max((p[i] - fundo[i]) / (255 - fundo[i]) for i in range(3))
            a = min(max(a, 0.0), 1.0)
            if a <= 0.02:
                po[x, y] = (0, 0, 0, 0)
                continue
            cor = tuple(min(255, max(0, round((p[i] - fundo[i] * (1 - a)) / a))) for i in range(3))
            po[x, y] = (*cor, round(a * 255))
    return out


def arredondada(im: Image.Image, raio: float = 0.225) -> Image.Image:
    """O quadrado com os cantos arredondados (transparentes)."""
    escala = 4  # máscara desenhada maior e reduzida: bordas suaves
    lado = im.width
    m = Image.new("L", (lado * escala, lado * escala), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, lado * escala - 1, lado * escala - 1),
                                        radius=lado * escala * raio, fill=255)
    m = m.resize((lado, lado), Image.LANCZOS)
    out = im.convert("RGBA")
    out.putalpha(ImageChops.multiply(out.getchannel("A"), m))
    return out


def recortar_conteudo(im: Image.Image, margem: float = 0.04) -> Image.Image:
    """Corta o transparente à volta e deixa uma margem igual nos quatro lados (quadrado)."""
    caixa = im.getchannel("A").point(lambda a: 255 if a > 24 else 0).getbbox()
    c = im.crop(caixa)
    lado = round(max(c.size) * (1 + 2 * margem))
    q = Image.new("RGBA", (lado, lado), (0, 0, 0, 0))
    q.paste(c, ((lado - c.width) // 2, (lado - c.height) // 2), c)
    return q


def reduzir(im: Image.Image, lado: int) -> Image.Image:
    return im.resize((lado, lado), Image.LANCZOS)


def main() -> None:
    origem = Image.open(ICONE).convert("RGB")
    fundo = cor_do_fundo(origem)
    # ícone clássico (Android < 8 e Windows): a imagem inteira, quadrada e arredondada
    classico = arredondada(reduzir(quadrada(origem, fundo), 1024))
    # o desenho sem o fundo (logótipo da app e frente do ícone adaptativo)
    desenho = recortar_conteudo(sem_fundo(reduzir(quadrada(origem, fundo), 1024), fundo))
    # adaptativo (Android 8+): o desenho dentro da zona segura (66 de 108 dp) sobre a cor do fundo
    frente = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    d = reduzir(desenho, round(1024 * 0.64))
    frente.paste(d, ((1024 - d.width) // 2, (1024 - d.height) // 2), d)

    for nome, f in DENSIDADES.items():
        pasta = RES / f"mipmap-{nome}"
        pasta.mkdir(parents=True, exist_ok=True)
        reduzir(classico, round(48 * f)).save(pasta / "ic_launcher.png")
        reduzir(frente, round(108 * f)).save(pasta / "ic_launcher_foreground.png")
    (RES / "values").mkdir(exist_ok=True)
    (RES / "values" / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<!-- o fundo do ícone adaptativo: a cor do fundo de ferramentas/marca/icone-origem.webp -->\n"
        "<resources>\n"
        f'    <color name="ic_launcher_background">#{fundo[0]:02X}{fundo[1]:02X}{fundo[2]:02X}</color>\n'
        "</resources>\n",
        encoding="utf-8")

    # banner 320x180 (16:9): o centro da imagem 2:1 (o ícone e o nome cabem com folga)
    b = Image.open(BANNER).convert("RGB")
    largura = round(b.height * 16 / 9)
    x = (b.width - largura) // 2
    (RES / "drawable-xhdpi").mkdir(exist_ok=True)
    b.crop((x, 0, x + largura, b.height)).resize((320, 180), Image.LANCZOS).save(
        RES / "drawable-xhdpi" / "banner.png")

    # Windows: .ico com todos os tamanhos
    tamanhos = [16, 20, 24, 32, 40, 48, 64, 128, 256]
    imagens = [reduzir(classico, t) for t in tamanhos]
    imagens[-1].save(RAIZ / "windows" / "runner" / "resources" / "app_icon.ico",
                     sizes=[(t, t) for t in tamanhos], append_images=imagens[:-1])

    (RAIZ / "assets" / "marca").mkdir(parents=True, exist_ok=True)
    reduzir(desenho, 256).save(RAIZ / "assets" / "marca" / "logo.png")
    print("ok")


if __name__ == "__main__":
    main()
