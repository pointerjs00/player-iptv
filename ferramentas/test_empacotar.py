import hashlib
import sys
import tempfile
import unittest
import unittest.mock
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import empacotar


def _licencas_windows(p: Path) -> None:
    (p / "licencas-libmpv" / "licencas").mkdir(parents=True)
    (p / "licencas-libmpv" / "AVISOS-LICENCAS.txt").write_text("x")
    for n in ["GPL-3.0.txt", "LGPL-2.1.txt"]:
        (p / "licencas-libmpv" / "licencas" / n).write_text("x")


_LIBMPV = {"arm64-v8a": b"libmpv do mpv-android arm64", "armeabi-v7a": b"libmpv do mpv-android armv7"}
_FIXADOS = {abi: hashlib.sha256(c).hexdigest() for abi, c in _LIBMPV.items()}


def _apk(caminho: Path, abi: str, libmpv=b"", licencas=True) -> None:
    """Um APK de mentira (zip) com o lib/<abi>/libmpv.so e os assets das licenças."""
    if libmpv == b"":
        libmpv = _LIBMPV[abi]
    with zipfile.ZipFile(caminho, "w") as z:
        if libmpv is not None:
            z.writestr(f"lib/{abi}/libmpv.so", libmpv)
        if licencas:
            for a in empacotar.LICENCAS_APK:
                z.writestr(a, "x")


class VerificarConteudo(unittest.TestCase):
    def test_pasta_limpa_passa(self):
        with tempfile.TemporaryDirectory() as t:
            (Path(t) / "TVIntel.exe").write_text("x")
            empacotar.verificar_conteudo(Path(t))

    def test_recusa_ficheiros_proibidos(self):
        for nome in ["Accounts.json", "Accounts_casa.json", "lista.ini",
                     "historico.json", "biblioteca.json"]:
            with self.subTest(nome=nome), tempfile.TemporaryDirectory() as t:
                sub = Path(t) / "data"
                sub.mkdir()
                (sub / nome).write_text("{}")
                with self.assertRaises(SystemExit):
                    empacotar.verificar_conteudo(Path(t))


class VerificarLibmpv(unittest.TestCase):
    def _pasta(self, t, conteudo=b"x", licencas=True):
        p = Path(t)
        (p / "libmpv-2.dll").write_bytes(conteudo)
        if licencas:
            _licencas_windows(p)
        return p

    def test_dll_certa_passa(self):
        with tempfile.TemporaryDirectory() as t:
            conteudo = b"dll completa"
            with unittest.mock.patch.object(empacotar, "SHA256_LIBMPV", hashlib.sha256(conteudo).hexdigest()):
                empacotar.verificar_libmpv(self._pasta(t, conteudo))

    def test_dll_minima_do_media_kit_recusa(self):
        with tempfile.TemporaryDirectory() as t:
            with self.assertRaises(SystemExit) as e:
                empacotar.verificar_libmpv(self._pasta(t, b"outra dll"))
            self.assertIn("libmpv", str(e.exception))

    def test_sem_dll_recusa(self):
        with tempfile.TemporaryDirectory() as t:
            with self.assertRaises(SystemExit):
                empacotar.verificar_libmpv(Path(t))

    def test_sem_os_textos_das_licencas_recusa(self):
        with tempfile.TemporaryDirectory() as t:
            conteudo = b"dll completa"
            p = self._pasta(t, conteudo)
            (p / "licencas-libmpv" / "licencas" / "GPL-3.0.txt").unlink()
            with unittest.mock.patch.object(empacotar, "SHA256_LIBMPV", hashlib.sha256(conteudo).hexdigest()):
                with self.assertRaises(SystemExit) as e:
                    empacotar.verificar_libmpv(p)
            self.assertIn("GPL-3.0.txt", str(e.exception))

    def test_sem_licencas_recusa(self):
        with tempfile.TemporaryDirectory() as t:
            conteudo = b"dll completa"
            with unittest.mock.patch.object(empacotar, "SHA256_LIBMPV", hashlib.sha256(conteudo).hexdigest()):
                with self.assertRaises(SystemExit):
                    empacotar.verificar_libmpv(self._pasta(t, conteudo, licencas=False))


class NomesApk(unittest.TestCase):
    def test_nomes_de_saida(self):
        self.assertEqual(empacotar.APKS["app-arm64-v8a-release.apk"], "TVIntel-android-arm64.apk")
        self.assertEqual(empacotar.APKS["app-armeabi-v7a-release.apk"], "TVIntel-android-armv7.apk")

    def test_copiar_apks(self):
        with tempfile.TemporaryDirectory() as t:
            origem, dist = Path(t) / "o", Path(t) / "d"
            origem.mkdir()
            for n, abi in [("app-arm64-v8a-release.apk", "arm64-v8a"), ("app-armeabi-v7a-release.apk", "armeabi-v7a")]:
                _apk(origem / n, abi)
            (origem / "app-x86_64-release.apk").write_text("x")
            with unittest.mock.patch.object(empacotar, "SHA256_LIBMPV_ANDROID", _FIXADOS):
                feitos = empacotar.copiar_apks(origem, dist)
            self.assertEqual(sorted(p.name for p in feitos),
                             ["TVIntel-android-arm64.apk", "TVIntel-android-armv7.apk"])
            self.assertFalse((dist / "app-x86_64-release.apk").exists())

    def test_apk_com_o_libmpv_minimo_recusa(self):
        with tempfile.TemporaryDirectory() as t:
            origem = Path(t) / "o"
            origem.mkdir()
            _apk(origem / "app-arm64-v8a-release.apk", "arm64-v8a", libmpv=b"o minimo do media_kit")
            _apk(origem / "app-armeabi-v7a-release.apk", "armeabi-v7a")
            with unittest.mock.patch.object(empacotar, "SHA256_LIBMPV_ANDROID", _FIXADOS):
                with self.assertRaises(SystemExit) as e:
                    empacotar.copiar_apks(origem, Path(t) / "d")
            self.assertIn("libmpv", str(e.exception))
            self.assertFalse((Path(t) / "d" / "TVIntel-android-arm64.apk").exists())

    def test_apk_sem_libmpv_ou_sem_licencas_recusa(self):
        for falta in ["libmpv", "licencas"]:
            with self.subTest(falta=falta), tempfile.TemporaryDirectory() as t:
                origem = Path(t) / "o"
                origem.mkdir()
                _apk(origem / "app-arm64-v8a-release.apk", "arm64-v8a",
                     libmpv=None if falta == "libmpv" else _LIBMPV["arm64-v8a"], licencas=falta != "licencas")
                _apk(origem / "app-armeabi-v7a-release.apk", "armeabi-v7a")
                with unittest.mock.patch.object(empacotar, "SHA256_LIBMPV_ANDROID", _FIXADOS):
                    with self.assertRaises(SystemExit):
                        empacotar.copiar_apks(origem, Path(t) / "d")

    def test_sha256_do_libmpv_android_vem_do_sha256_txt(self):
        fixados = empacotar.ler_sha256_libmpv_android()
        self.assertEqual(fixados["arm64-v8a"], "03d2d02db0451cebf4da2648188df7b2502005c6409fad1841b1d2b91ca8a814")
        self.assertEqual(fixados["armeabi-v7a"], "433381171115bce0d02b53b1402943815678a852fa5eee9a6c38873b25bf5c26")
        self.assertEqual(fixados["x86_64"], "97f0621d8f6e236ed5491a89565c2ed526f5450074ec58df560ada5f5f1bc5f8")

    def test_apk_em_falta(self):
        with tempfile.TemporaryDirectory() as t:
            with self.assertRaises(SystemExit):
                empacotar.copiar_apks(Path(t), Path(t) / "d")


class ZipWindows(unittest.TestCase):
    def test_raiz_playeriptv(self):
        with tempfile.TemporaryDirectory() as t:
            rel = Path(t) / "Release"
            (rel / "data").mkdir(parents=True)
            (rel / "TVIntel.exe").write_text("exe")
            (rel / "data" / "app.so").write_text("so")
            (rel / "libmpv-2.dll").write_bytes(b"completa")
            _licencas_windows(rel)
            destino = Path(t) / "dist" / "TVIntel-windows.zip"
            with unittest.mock.patch.object(empacotar, "SHA256_LIBMPV", hashlib.sha256(b"completa").hexdigest()):
                empacotar.criar_zip_windows(rel, destino)
            with zipfile.ZipFile(destino) as z:
                nomes = z.namelist()
            self.assertIn("TVIntel/libmpv-2.dll", nomes)
            self.assertIn("TVIntel/licencas-libmpv/AVISOS-LICENCAS.txt", nomes)
            self.assertIn("TVIntel/licencas-libmpv/licencas/GPL-3.0.txt", nomes)
            self.assertIn("TVIntel/TVIntel.exe", nomes)
            self.assertIn("TVIntel/data/app.so", nomes)
            self.assertTrue(all(n.startswith("TVIntel/") for n in nomes))

    def test_zip_recusa_dados_pessoais(self):
        with tempfile.TemporaryDirectory() as t:
            rel = Path(t) / "Release"
            rel.mkdir()
            (rel / "Accounts.json").write_text("{}")
            with self.assertRaises(SystemExit):
                empacotar.criar_zip_windows(rel, Path(t) / "z.zip")


class Symlinks(unittest.TestCase):
    def test_deteta(self):
        self.assertTrue(empacotar.falta_symlinks("Error: Building with plugins requires symlink support.\nPlease enable"))
        self.assertFalse(empacotar.falta_symlinks("Some other error"))


class LimparSaidas(unittest.TestCase):
    def _dist_velha(self, t):
        dist = Path(t) / "dist"
        dist.mkdir()
        for n in ["TVIntel-android-arm64.apk", "TVIntel-android-armv7.apk",
                  "TVIntel-windows.zip", "LEIA-ME.txt"]:
            (dist / n).write_text("velho")
        return dist

    def test_limpar_android_nao_toca_windows(self):
        with tempfile.TemporaryDirectory() as t:
            dist = self._dist_velha(t)
            empacotar.limpar_saidas(dist, android=True, windows=False)
            self.assertFalse((dist / "TVIntel-android-arm64.apk").exists())
            self.assertFalse((dist / "TVIntel-android-armv7.apk").exists())
            self.assertTrue((dist / "TVIntel-windows.zip").exists())

    def test_falha_android_nao_deixa_apk_velho(self):
        with tempfile.TemporaryDirectory() as t:
            dist = self._dist_velha(t)
            def falha(d):
                raise SystemExit("falhou")
            orig = (empacotar.RAIZ, empacotar.construir_android)
            empacotar.RAIZ, empacotar.construir_android = Path(t), falha
            try:
                with self.assertRaises(SystemExit):
                    empacotar.main(["--so-android"])
            finally:
                empacotar.RAIZ, empacotar.construir_android = orig
            self.assertFalse((dist / "TVIntel-android-arm64.apk").exists())
            self.assertFalse((dist / "LEIA-ME.txt").exists())
            self.assertTrue((dist / "TVIntel-windows.zip").exists())

    def test_symlinks_nao_deixa_zip_velho(self):
        with tempfile.TemporaryDirectory() as t:
            dist = self._dist_velha(t)
            orig = (empacotar.RAIZ, empacotar.construir_windows)
            empacotar.RAIZ, empacotar.construir_windows = Path(t), lambda d: None
            try:
                empacotar.main(["--so-windows"])
            finally:
                empacotar.RAIZ, empacotar.construir_windows = orig
            self.assertFalse((dist / "TVIntel-windows.zip").exists())
            self.assertTrue((dist / "TVIntel-android-arm64.apk").exists())


class Codificacao(unittest.TestCase):
    def test_imprimir_fora_de_cp1252_nao_falha(self):
        import io
        bruto = io.BytesIO()
        fluxo = io.TextIOWrapper(bruto, encoding="cp1252")
        with self.assertRaises(UnicodeEncodeError):
            fluxo.write("✓ → あ"); fluxo.flush()
        bruto = io.BytesIO()
        fluxo = io.TextIOWrapper(bruto, encoding="cp1252")
        empacotar.configurar_saida(fluxo)
        fluxo.write("✓ → あ ok"); fluxo.flush()
        self.assertIn("ok".encode(), bruto.getvalue())


class LeiaMe(unittest.TestCase):
    def test_fire_tv_4k_max_aponta_para_o_armv7(self):
        # Minor B: o Fire TV Stick 4K Max (Fire OS 7) tem userland de 32 bits
        texto = empacotar.LEIA_ME
        linha = next(l for l in texto.splitlines() if "4K Max" in l)
        bloco = texto[texto.index(linha) - 200:texto.index(linha) + 200]
        self.assertIn("armv7", bloco)
        arm64 = texto[texto.index("arm64.apk  ->"):texto.index("armv7.apk  ->")]
        self.assertNotIn("4K Max", arm64)

    def test_acentos(self):
        self.assertNotIn("conteudo", empacotar.LEIA_ME)
        self.assertIn("conteúdo", empacotar.LEIA_ME)


class EdicaoPartilha(unittest.TestCase):
    def test_codigo_com_importacao_auto_recusa(self):
        empacotar.verificar_sem_importacao_auto(b"codigo sem nada", "app.so")
        for mau in [b"x https://stbstalker.alaaeldinee.com/ y", b"Listas do stbstalker",
                    b"michelstv4", b"https://t.me/s/canal"]:
            with self.assertRaises(SystemExit):
                empacotar.verificar_sem_importacao_auto(mau, "app.so")

    def test_partilha_vai_para_dist_partilha_com_os_testes_e_o_define(self):
        with tempfile.TemporaryDirectory() as t:
            vistos = {}

            def android(d):
                vistos["dist"] = d
                vistos["defines"] = list(empacotar.DEFINES)
                return []

            orig = (empacotar.RAIZ, empacotar.construir_android, empacotar.testar_partilha)
            empacotar.RAIZ, empacotar.construir_android = Path(t), android
            empacotar.testar_partilha = lambda: vistos.setdefault("testes", True)
            try:
                empacotar.main(["--so-android", "--partilha"])
            finally:
                empacotar.RAIZ, empacotar.construir_android, empacotar.testar_partilha = orig
                empacotar.DEFINES.clear()
            self.assertEqual(vistos["dist"], Path(t) / "dist" / "partilha")
            self.assertEqual(vistos["defines"], [empacotar.DEFINE_PARTILHA])
            self.assertTrue(vistos["testes"])
            self.assertTrue((Path(t) / "dist" / "partilha" / "LEIA-ME.txt").exists())

    def test_sem_partilha_nao_ha_define(self):
        with tempfile.TemporaryDirectory() as t:
            vistos = {}
            orig = (empacotar.RAIZ, empacotar.construir_android)
            empacotar.RAIZ = Path(t)
            empacotar.construir_android = lambda d: vistos.update(defines=list(empacotar.DEFINES), dist=d) or []
            try:
                empacotar.main(["--so-android"])
            finally:
                empacotar.RAIZ, empacotar.construir_android = orig
            self.assertEqual(vistos["defines"], [])
            self.assertEqual(vistos["dist"], Path(t) / "dist")



class JuntarPacotes(unittest.TestCase):
    def test_versao_do_pubspec_sem_a_compilacao(self):
        with tempfile.TemporaryDirectory() as t:
            f = Path(t) / "pubspec.yaml"
            f.write_text("name: x\nversion: 1.0.23+24\n", encoding="utf-8")
            self.assertEqual(empacotar.ler_versao(f), "1.0.23")

    def test_as_duas_edicoes_numa_pasta_com_a_versao_no_nome(self):
        with tempfile.TemporaryDirectory() as t:
            completa, partilha, destino = Path(t) / "c", Path(t) / "p", Path(t) / "TVIntel-1.0.23"
            for d in (completa, partilha):
                d.mkdir()
                for n in ["TVIntel-android-arm64.apk", "TVIntel-android-armv7.apk", "TVIntel-windows.zip"]:
                    (d / n).write_text(d.name + n)
            destino.mkdir()
            (destino / "velho.apk").write_text("de uma versão antiga")
            gerados = empacotar.juntar_pacotes(completa, partilha, destino, "1.0.23")
            nomes = sorted(g.name for g in gerados)
            self.assertEqual(nomes, sorted([
                "TVIntel-1.0.23-android-arm64.apk", "TVIntel-1.0.23-android-armv7.apk", "TVIntel-1.0.23-windows.zip",
                "TVIntel-1.0.23-partilha-android-arm64.apk", "TVIntel-1.0.23-partilha-android-armv7.apk",
                "TVIntel-1.0.23-partilha-windows.zip", "LEIA-ME.txt",
            ]))
            self.assertFalse((destino / "velho.apk").exists(), "a pasta só tem esta versão")
            self.assertEqual((destino / "TVIntel-1.0.23-partilha-windows.zip").read_text(), "pTVIntel-windows.zip")
            leia = (destino / "LEIA-ME.txt").read_text(encoding="utf-8")
            self.assertIn("TVIntel-1.0.23-partilha-android-arm64.apk", leia)
            self.assertIn("TVIntel-1.0.23-windows.zip", leia)
            self.assertIn("edição de partilha", leia.lower())

    def test_um_pacote_que_falta_nao_impede_os_outros(self):
        with tempfile.TemporaryDirectory() as t:
            completa, partilha, destino = Path(t) / "c", Path(t) / "p", Path(t) / "d"
            completa.mkdir()
            partilha.mkdir()
            (completa / "TVIntel-android-arm64.apk").write_text("x")
            gerados = empacotar.juntar_pacotes(completa, partilha, destino, "1.0.23")
            self.assertEqual(sorted(g.name for g in gerados), ["LEIA-ME.txt", "TVIntel-1.0.23-android-arm64.apk"])


if __name__ == "__main__":
    unittest.main()
