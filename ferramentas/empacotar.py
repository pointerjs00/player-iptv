"""Gera em dist/ os pacotes a partilhar: APK Android (arm64, armv7) e zip Windows.

Uso: python ferramentas/empacotar.py [--so-android | --so-windows] [--partilha]
Com --partilha gera a edição de partilha (sem a importação automática: stbstalker e Telegram)
em dist/partilha/: corre antes os testes dessa edição e recusa pacotes que ainda a tragam.
Nunca altera definições do sistema.
"""
import argparse
import fnmatch
import hashlib
import os
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
APKS = {
    "app-arm64-v8a-release.apk": "TVIntel-android-arm64.apk",
    "app-armeabi-v7a-release.apk": "TVIntel-android-armv7.apk",
}
PASTA_APK = Path("build/app/outputs/flutter-apk")
PASTA_WINDOWS = Path("build/windows/x64/runner/Release")
RAIZ_ZIP = "TVIntel"
PROIBIDOS = ["Accounts*.json", "*.ini", "historico.json", "biblioteca.json"]
MSG_SYMLINK = "Building with plugins requires symlink support"
# o libmpv completo (com os filtros do ffmpeg: bwdif...) que o windows/libmpv_completo.cmake instala;
# o do media_kit é mínimo e deixaria o desentrelaçamento só com o shader
SHA256_LIBMPV = "88504ee5560942a955405e99dfb5971368e4cf851321f36565bf2a667271db1b"
# os textos das licenças do libmpv/ffmpeg (GPLv3) que têm de ir com o pacote
LICENCAS_WINDOWS = ["AVISOS-LICENCAS.txt", "licencas/GPL-3.0.txt", "licencas/LGPL-2.1.txt"]
# no APK vão como assets da app (pubspec.yaml), mostrados em Definições -> Licenças
LICENCAS_APK = [
    "assets/flutter_assets/third_party/libmpv_completo/AVISOS-LICENCAS.txt",
    "assets/flutter_assets/third_party/libmpv_completo/licencas/GPL-3.0.txt",
    "assets/flutter_assets/third_party/libmpv_completo/licencas/LGPL-2.1.txt",
]
FICHEIRO_SHA256 = RAIZ / "third_party" / "libmpv_completo" / "SHA256.txt"
# a edição de partilha (lib/edicao.dart): o que não pode estar no código compilado dela
DEFINE_PARTILHA = "--dart-define=PARTILHA=true"
PROIBIDOS_PARTILHA = [b"alaaeldinee", b"stbstalker", b"michelstv4", b"t.me/s/", b"elegram",  # "elegram": Telegram e telegram
                      # os «Jogos» (lib/desporto): os anfitriões das fontes dos jogos e das grelhas
                      b"fotmob", b"meo.pt", b"sporttv.pt", b"fpb.pt", b"espn"]
# o código Dart compilado: no APK (por ABI) e na pasta do Windows
LIBAPP_APK = "lib/{abi}/libapp.so"
APP_WINDOWS = Path("data/app.so")
# os --dart-define da compilação (a edição de partilha junta o DEFINE_PARTILHA)
DEFINES: list[str] = []


def ler_sha256_libmpv_android(ficheiro: Path = FICHEIRO_SHA256) -> dict[str, str]:
    """abi -> SHA-256 do libmpv.so do mpv-android (as linhas "<sha> <pasta>/x/lib/<abi>/libmpv.so")."""
    r = {}
    for linha in Path(ficheiro).read_text(encoding="utf-8").splitlines():
        partes = linha.split()
        if len(partes) == 2 and partes[1].endswith("/libmpv.so") and "/lib/" in partes[1]:
            r[partes[1].split("/")[-2]] = partes[0]
    return r


# o libmpv completo de cada APK (android/libmpv_completo.gradle); o do media_kit é mínimo
SHA256_LIBMPV_ANDROID = ler_sha256_libmpv_android()
# o ABI de cada APK do Flutter
ABI_APK = {"app-arm64-v8a-release.apk": "arm64-v8a", "app-armeabi-v7a-release.apk": "armeabi-v7a"}

LEIA_ME = """\
TVINTEL - COMO INSTALAR
=======================

Que ficheiro escolher
---------------------
- Windows:  TVIntel-windows.zip
- Android (telemóvel, tablet, Fire TV, Android TV):
  * TVIntel-android-arm64.apk  -> a escolha certa para a maioria dos
    telemóveis, tablets e boxes Android TV recentes.
  * TVIntel-android-armv7.apk  -> Fire TV e aparelhos mais antigos.
    No Fire TV Stick 4K Max use o armv7 (o Fire OS 7 só instala 32 bits).
    Se o arm64 não instalar ("App não instalada"), use este.

Windows
-------
1. Descompacte o TVIntel-windows.zip (botão direito -> Extrair tudo).
2. Abra a pasta TVIntel e execute TVIntel.exe.
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
3. adb install TVIntel-android-armv7.apk   (Fire TV; arm64 noutros aparelhos)

Importar as listas
------------------
A aplicação não traz listas nem contas. Na primeira abertura importe as suas:
- Accounts.json  (ficheiro de contas exportado)
- ficheiros .ini (um por lista)
- ficheiros .m3u / .m3u8
- ou cole o endereço / conteúdo da lista diretamente na aplicação.
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


def verificar_libmpv(pasta: Path) -> None:
    """Recusa empacotar sem o libmpv completo (SHA-256 fixado) e sem os avisos de licença dele."""
    dll = Path(pasta) / "libmpv-2.dll"
    if not dll.is_file():
        raise SystemExit("Empacotamento recusado: falta o libmpv-2.dll.")
    if hashlib.sha256(dll.read_bytes()).hexdigest() != SHA256_LIBMPV:
        raise SystemExit(
            "Empacotamento recusado: o libmpv-2.dll não é o libmpv completo (windows/libmpv_completo.cmake)."
        )
    for nome in LICENCAS_WINDOWS:
        if not (Path(pasta) / "licencas-libmpv" / nome).is_file():
            raise SystemExit(f"Empacotamento recusado: falta licencas-libmpv/{nome} (licença do libmpv/ffmpeg).")


def verificar_sem_importacao_auto(codigo: bytes, nome: str) -> None:
    """Edição de partilha: recusa o código compilado que ainda traga a importação automática."""
    for p in PROIBIDOS_PARTILHA:
        if p in codigo:
            raise SystemExit(
                f"Empacotamento recusado: {nome} da edição de partilha ainda tem '{p.decode()}' (lib/edicao.dart)."
            )


def verificar_apk(apk: Path, abi: str) -> None:
    """Recusa um APK sem o libmpv completo no ABI dele (SHA-256 fixado) ou sem os textos das licenças."""
    with zipfile.ZipFile(apk) as z:
        nomes = set(z.namelist())
        lib = f"lib/{abi}/libmpv.so"
        if lib not in nomes:
            raise SystemExit(f"Empacotamento recusado: {Path(apk).name} sem {lib}.")
        h = hashlib.sha256(z.read(lib)).hexdigest()
        if h != SHA256_LIBMPV_ANDROID.get(abi):
            raise SystemExit(
                f"Empacotamento recusado: o {lib} de {Path(apk).name} não é o libmpv completo "
                "(android/libmpv_completo.gradle; foi construído com libmpvMinimo?)."
            )
        for a in LICENCAS_APK:
            if a not in nomes:
                raise SystemExit(f"Empacotamento recusado: {Path(apk).name} sem {a} (licença do libmpv/ffmpeg).")
        if DEFINE_PARTILHA in DEFINES:
            verificar_sem_importacao_auto(z.read(LIBAPP_APK.format(abi=abi)), Path(apk).name)


def copiar_apks(origem: Path, dist: Path) -> list[Path]:
    # todos verificados antes de copiar o primeiro: nunca fica um APK sem o libmpv completo em dist/
    for nome_flutter in APKS:
        src = Path(origem) / nome_flutter
        if not src.is_file():
            raise SystemExit(f"APK em falta: {src}")
        verificar_apk(src, ABI_APK[nome_flutter])
    dist.mkdir(parents=True, exist_ok=True)
    feitos = []
    for nome_flutter, nome_final in APKS.items():
        src = Path(origem) / nome_flutter
        destino = dist / nome_final
        shutil.copy2(src, destino)
        feitos.append(destino)
    return feitos


def criar_zip_windows(pasta_release: Path, destino: Path) -> Path:
    pasta_release = Path(pasta_release)
    verificar_conteudo(pasta_release)
    verificar_libmpv(pasta_release)
    if DEFINE_PARTILHA in DEFINES:
        verificar_sem_importacao_auto((pasta_release / APP_WINDOWS).read_bytes(), "o TVIntel.exe")
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


def limpar_saidas(dist: Path, android: bool, windows: bool) -> None:
    """Apaga saidas antigas dos alvos a construir, para nunca partilhar ficheiros velhos."""
    nomes = ["LEIA-ME.txt"]
    if android:
        nomes += list(APKS.values())
    if windows:
        nomes.append("TVIntel-windows.zip")
    for n in nomes:
        (Path(dist) / n).unlink(missing_ok=True)


def configurar_saida(*fluxos) -> None:
    """UTF-8 com substituicao, para a saida do Flutter nunca rebentar em cp1252."""
    for f in fluxos:
        f.reconfigure(encoding="utf-8", errors="replace")


def _flutter() -> str:
    return shutil.which("flutter") or "flutter"


def construir_android(dist: Path) -> list[Path]:
    r = subprocess.run([_flutter(), "build", "apk", "--release", "--split-per-abi", *DEFINES], cwd=RAIZ)
    if r.returncode != 0:
        raise SystemExit("Falhou 'flutter build apk'.")
    return copiar_apks(RAIZ / PASTA_APK, dist)


def construir_windows(dist: Path) -> Path | None:
    """Devolve o zip, ou None se faltar o suporte de symlinks (Modo de Programador)."""
    r = subprocess.run([_flutter(), "build", "windows", "--release", *DEFINES], cwd=RAIZ,
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    saida = (r.stdout or "") + (r.stderr or "")
    print(saida)
    if r.returncode != 0:
        if falta_symlinks(saida):
            return None
        raise SystemExit("Falhou 'flutter build windows'.")
    return criar_zip_windows(RAIZ / PASTA_WINDOWS, dist / "TVIntel-windows.zip")


def testar_partilha() -> None:
    """Os testes da edição de partilha (test/edicao), compilados como ela."""
    r = subprocess.run([_flutter(), "test", DEFINE_PARTILHA, "test/edicao"], cwd=RAIZ)
    if r.returncode != 0:
        raise SystemExit("Falharam os testes da edição de partilha (test/edicao).")


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    g = p.add_mutually_exclusive_group()
    g.add_argument("--so-android", action="store_true")
    g.add_argument("--so-windows", action="store_true")
    p.add_argument("--partilha", action="store_true", help="a edição de partilha, em dist/partilha/")
    a = p.parse_args(argv)
    configurar_saida(sys.stdout, sys.stderr)
    DEFINES[:] = [DEFINE_PARTILHA] if a.partilha else []
    dist = RAIZ / "dist" / "partilha" if a.partilha else RAIZ / "dist"
    dist.mkdir(parents=True, exist_ok=True)
    limpar_saidas(dist, android=not a.so_windows, windows=not a.so_android)
    avisos = []
    gerados = []
    if a.partilha:
        testar_partilha()

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
    print(f"\nGerado em {dist.relative_to(RAIZ).as_posix()}/:")
    for g_ in gerados:
        print(f"  {g_.name}  ({g_.stat().st_size / 1e6:.1f} MB)")
    for av in avisos:
        print(f"\nAVISO: {av}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
