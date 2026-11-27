import subprocess
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import verificar


class Verificar(unittest.TestCase):
    def test_corre_os_quatro_passos_pela_ordem(self):
        feitos = []

        def correr(comando, cwd):
            feitos.append(comando)
            return subprocess.CompletedProcess(comando, 0)

        verificar.verificar(correr)
        self.assertEqual(len(feitos), 4)
        self.assertEqual(feitos[0][1:], ["analyze"])
        self.assertIn("ferramentas", feitos[1])
        self.assertEqual(feitos[2][1:], ["test", "--dart-define=PARTILHA=true", "test/edicao"])
        self.assertEqual(feitos[3][1:], ["test"])

    def test_para_no_primeiro_que_falha_e_diz_qual(self):
        feitos = []

        def correr(comando, cwd):
            feitos.append(comando)
            return subprocess.CompletedProcess(comando, 1 if comando[1:] == ["analyze"] else 0)

        with self.assertRaises(SystemExit) as e:
            verificar.verificar(correr)
        self.assertEqual(len(feitos), 1)
        self.assertIn("análise", str(e.exception))


if __name__ == "__main__":
    unittest.main()
