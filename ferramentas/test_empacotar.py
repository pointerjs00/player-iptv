import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import empacotar


class VerificarConteudo(unittest.TestCase):
    def test_pasta_limpa_passa(self):
        with tempfile.TemporaryDirectory() as t:
            (Path(t) / "player_iptv.exe").write_text("x")
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


class NomesApk(unittest.TestCase):
    def test_nomes_de_saida(self):
        self.assertEqual(empacotar.APKS["app-arm64-v8a-release.apk"], "PlayerIPTV-android-arm64.apk")
        self.assertEqual(empacotar.APKS["app-armeabi-v7a-release.apk"], "PlayerIPTV-android-armv7.apk")

    def test_copiar_apks(self):
        with tempfile.TemporaryDirectory() as t:
            origem, dist = Path(t) / "o", Path(t) / "d"
            origem.mkdir()
            for n in empacotar.APKS:
                (origem / n).write_text(n)
            (origem / "app-x86_64-release.apk").write_text("x")
            feitos = empacotar.copiar_apks(origem, dist)
            self.assertEqual(sorted(p.name for p in feitos),
                             ["PlayerIPTV-android-arm64.apk", "PlayerIPTV-android-armv7.apk"])
            self.assertFalse((dist / "app-x86_64-release.apk").exists())

    def test_apk_em_falta(self):
        with tempfile.TemporaryDirectory() as t:
            with self.assertRaises(SystemExit):
                empacotar.copiar_apks(Path(t), Path(t) / "d")


class ZipWindows(unittest.TestCase):
    def test_raiz_playeriptv(self):
        with tempfile.TemporaryDirectory() as t:
            rel = Path(t) / "Release"
            (rel / "data").mkdir(parents=True)
            (rel / "player_iptv.exe").write_text("exe")
            (rel / "data" / "app.so").write_text("so")
            destino = Path(t) / "dist" / "PlayerIPTV-windows.zip"
            empacotar.criar_zip_windows(rel, destino)
            with zipfile.ZipFile(destino) as z:
                nomes = z.namelist()
            self.assertIn("PlayerIPTV/player_iptv.exe", nomes)
            self.assertIn("PlayerIPTV/data/app.so", nomes)
            self.assertTrue(all(n.startswith("PlayerIPTV/") for n in nomes))

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
        for n in ["PlayerIPTV-android-arm64.apk", "PlayerIPTV-android-armv7.apk",
                  "PlayerIPTV-windows.zip", "LEIA-ME.txt"]:
            (dist / n).write_text("velho")
        return dist

    def test_limpar_android_nao_toca_windows(self):
        with tempfile.TemporaryDirectory() as t:
            dist = self._dist_velha(t)
            empacotar.limpar_saidas(dist, android=True, windows=False)
            self.assertFalse((dist / "PlayerIPTV-android-arm64.apk").exists())
            self.assertFalse((dist / "PlayerIPTV-android-armv7.apk").exists())
            self.assertTrue((dist / "PlayerIPTV-windows.zip").exists())

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
            self.assertFalse((dist / "PlayerIPTV-android-arm64.apk").exists())
            self.assertFalse((dist / "LEIA-ME.txt").exists())
            self.assertTrue((dist / "PlayerIPTV-windows.zip").exists())

    def test_symlinks_nao_deixa_zip_velho(self):
        with tempfile.TemporaryDirectory() as t:
            dist = self._dist_velha(t)
            orig = (empacotar.RAIZ, empacotar.construir_windows)
            empacotar.RAIZ, empacotar.construir_windows = Path(t), lambda d: None
            try:
                empacotar.main(["--so-windows"])
            finally:
                empacotar.RAIZ, empacotar.construir_windows = orig
            self.assertFalse((dist / "PlayerIPTV-windows.zip").exists())
            self.assertTrue((dist / "PlayerIPTV-android-arm64.apk").exists())


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


if __name__ == "__main__":
    unittest.main()
