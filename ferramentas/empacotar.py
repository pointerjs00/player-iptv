"""Gera em dist/ os pacotes a partilhar: APK Android (arm64, armv7) e zip Windows.

Uso: python ferramentas/empacotar.py [--so-android | --so-windows]
Nunca altera definições do sistema.
"""
import argparse
import fnmatch
import os
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
APKS = {
    "app-arm64-v8a-release.apk": "PlayerIPTV-android-arm64.apk",
    "app-armeabi-v7a-release.apk": "PlayerIPTV-android-armv7.apk",
}
PASTA_APK = Path("build/app/outputs/flutter-apk")
PASTA_WINDOWS = Path("build/windows/x64/runner/Release")
RAIZ_ZIP = "PlayerIPTV"
PROIBIDOS = ["Accounts*.json", "*.ini", "historico.json", "biblioteca.json"]
MSG_SYMLINK = "Building with plugins requires symlink support"

LEIA_ME = """\
PLAYER IPTV - COMO INSTALAR
===========================

Que ficheiro escolher
---------------------
- Windows:  PlayerIPTV-windows.zip
- Android (telemóvel, tablet, Fire TV, Android TV):
  * PlayerIPTV-android-arm64.apk  -> a escolha certa para quase todos os
    aparelhos recentes, incluindo o Fire TV Stick 4K Max.
  * PlayerIPTV-android-armv7.apk  -> aparelhos mais antigos (Fire TV Stick
    antigos, telemóveis muito velhos). Se o arm64 não instalar, use este.

Windows
-------
1. Descompacte o PlayerIPTV-windows.zip (botão direito -> Extrair tudo).
2. Abra a pasta PlayerIPTV e execute player_iptv.exe.
   Não mova o .exe para fora da pasta: precisa dos restantes ficheiros.

Telemóvel ou tablet Android
---------------------------
1. Copie o APK para o aparelho (cabo, partilha, e-mail...).
2. Abra o ficheiro. Se o Android avisar, permita "Instalar apps
   desconhecidas" para a aplicação que usou (Ficheiros, Chrome...).
3. Toque em Instalar.

Fire TV / Android TV
--------------------
Opção A - app Downloader:
1. Instale a app "Downloader" (loja de apps do aparelho).
2. Nas definições do Fire TV, ative "Apps de fontes desconhecidas" para o
   Downloader (Minha Fire TV -> Opções de programador).
3. Na app Downloader, escreva o endereço onde alojou o APK e instale.
Opção B - adb, a partir de um computador na mesma rede:
1. Ative "Depuração ADB" nas opções de programador do aparelho.
2. adb connect ENDEREÇO_IP_DO_APARELHO
3. adb install PlayerIPTV-android-arm64.apk

Importar as listas
------------------
A aplicação não traz listas nem contas. Na primeira abertura importe as suas:
- Accounts.json  (ficheiro de contas exportado)
- ficheiros .ini (um por lista)
- ficheiros .m3u / .m3u8
- ou cole o endereço / conteudo da lista diretamente na aplicação.
"""


def verificar_conteudo(pasta: Path) -> None:
    """Recusa empacotar listas/contas/historico/biblioteca."""
    for caminho in sorted(Path(pasta).rglob("*")):
        if not caminho.is_file():
            continue
        for padrao in PROIBIDOS:
            if fnmatch.fnmatch(caminho.name.lower(), padrao.lower()):
                rel = caminho.relative_to(pasta)
                raise SystemExit(
                    f"Empacotamento recusado: '{rel}' contém dados pessoais e não pode ir no pacote."
                )


def copiar_apks(origem: Path, dist: Path) -> list[Path]:
    dist.mkdir(parents=True, exist_ok=True)
    feitos = []
    for nome_flutter, nome_final in APKS.items():
        src = Path(origem) / nome_flutter
        if not src.is_file():
            raise SystemExit(f"APK em falta: {src}")
        destino = dist / nome_final
        shutil.copy2(src, destino)
        feitos.append(destino)
    return feitos


def criar_zip_windows(pasta_release: Path, destino: Path) -> Path:
    pasta_release = Path(pasta_release)
    verificar_conteudo(pasta_release)
    destino = Path(destino)
    destino.parent.mkdir(parents=True, exist_ok=True)
    destino.unlink(missing_ok=True)
    with zipfile.ZipFile(destino, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(pasta_release.rglob("*")):
            if f.is_file():
                z.write(f, f"{RAIZ_ZIP}/{f.relative_to(pasta_release).as_posix()}")
    return destino


def falta_symlinks(texto: str) -> bool:
    return MSG_SYMLINK in texto


def _flutter() -> str:
    return shutil.which("flutter") or "flutter"


def construir_android(dist: Path) -> list[Path]:
    r = subprocess.run([_flutter(), "build", "apk", "--release", "--split-per-abi"], cwd=RAIZ)
    if r.returncode != 0:
        raise SystemExit("Falhou 'flutter build apk'.")
    return copiar_apks(RAIZ / PASTA_APK, dist)


def construir_windows(dist: Path) -> Path | None:
    """Devolve o zip, ou None se faltar o suporte de symlinks (Modo de Programador)."""
    r = subprocess.run([_flutter(), "build", "windows", "--release"], cwd=RAIZ,
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    saida = (r.stdout or "") + (r.stderr or "")
    print(saida)
    if r.returncode != 0:
        if falta_symlinks(saida):
            return None
        raise SystemExit("Falhou 'flutter build windows'.")
    return criar_zip_windows(RAIZ / PASTA_WINDOWS, dist / "PlayerIPTV-windows.zip")


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    g = p.add_mutually_exclusive_group()
    g.add_argument("--so-android", action="store_true")
    g.add_argument("--so-windows", action="store_true")
    a = p.parse_args(argv)
    dist = RAIZ / "dist"
    dist.mkdir(exist_ok=True)
    avisos = []
    gerados = []

    if not a.so_windows:
        gerados += construir_android(dist)
    if not a.so_android:
        z = construir_windows(dist)
        if z is None:
            avisos.append(
                "O pacote Windows NAO foi gerado: o Flutter precisa de suporte para "
                "ligações simbólicas (symlinks). Ligue o Modo de Programador do Windows "
                "(Definições -> Sistema -> Para programadores) e volte a correr o script. "
                "O script não altera definições do sistema."
            )
        else:
            gerados.append(z)

    (dist / "LEIA-ME.txt").write_text(LEIA_ME, encoding="utf-8")
    gerados.append(dist / "LEIA-ME.txt")
    print("\nGerado em dist/:")
    for g_ in gerados:
        print(f"  {g_.name}  ({g_.stat().st_size / 1e6:.1f} MB)")
    for av in avisos:
        print(f"\nAVISO: {av}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
