"""Verifica a app antes de um pacote: a análise, os testes destas ferramentas, os testes da edição
de partilha e os testes todos. Pára no primeiro passo que falhar.

Uso: python ferramentas/verificar.py
O empacotar.py corre-o antes de compilar (salvo com --sem-verificar).
"""
import shutil
import subprocess
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent


def _flutter() -> str:
    return shutil.which("flutter") or "flutter"


def passos() -> list[tuple[str, list[str]]]:
    """Os passos, pela ordem em que correm (os mais rápidos primeiro)."""
    f = _flutter()
    return [
        ("análise", [f, "analyze"]),
        ("testes das ferramentas", [sys.executable, "-m", "pytest", "-q", "ferramentas"]),
        ("testes da edição de partilha", [f, "test", "--dart-define=PARTILHA=true", "test/edicao"]),
        ("testes", [f, "test"]),
    ]


def verificar(correr=subprocess.run) -> None:
    """Corre os passos; o primeiro que falhar acaba com SystemExit a dizer qual."""
    for nome, comando in passos():
        print(f"\n== Verificar: {nome}", flush=True)
        r = correr(comando, cwd=RAIZ)
        if r.returncode != 0:
            raise SystemExit(f"A verificação falhou ({nome}): corrija antes de gerar os pacotes.")
    print("\nVerificação: tudo certo.")


if __name__ == "__main__":
    verificar()
