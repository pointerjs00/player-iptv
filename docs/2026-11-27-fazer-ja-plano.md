# «Fazer já» do relatório de análise — plano

Os seis pontos do quadrante «Fazer já» do relatório (Claude Docs, «TVIntel — análise da app e o que
melhorar», 27/11/2026). Branch `feature/redesenho`; o `main` avança no fim.

Decisões do utilizador (27/11):
- Chave do APK: **guardar a de depuração** (cópia de segurança + o build a usá-la explicitamente);
  não se troca (quem tem a app não precisa de reinstalar).
- Aviso de nova versão: **GitHub Releases** de `pointerjs00/player-iptv`; publicar as releases fica
  com o utilizador.

## Tarefas

1. **Chave do APK:** copiar `~/.android/debug.keystore` para uma pasta de cópia fora do repositório;
   `android/key.properties` (fora do git) aponta para ela; o `build.gradle.kts` assina o release com
   ela e só cai na de depuração se o ficheiro não existir. Confirmar que a impressão digital é a dos
   APKs já distribuídos.
2. **Preferências dos Jogos na cópia de segurança** (só na edição completa): exportar e importar o
   `desporto/preferencias.json`.
3. **Confirmar com dados reais** o que ficou por verificar (FotMob: emblemas, logótipos, minuto ao
   vivo, ids da Taça do Rei, Liga das Nações B–D e qualificações). Corrigir o que estiver mal.
4. **Script de verificação** `ferramentas/verificar.py` (análise, testes, testes da partilha, testes
   do `empacotar.py`); o `empacotar.py` corre-o antes de compilar (`--sem-verificar` para saltar).
5. **Aviso de nova versão:** ler a última release do GitHub e avisar uma vez por versão.
6. **Juntar o `feature/redesenho` ao `main`** (avanço rápido, sem push).

## Estado
- Tarefa 1 feita: chave copiada para `Documentos/TVIntel-chave-assinatura` (SHA-256 `11f1a4d8…ca9e`, a
  mesma dos APKs até à 1.0.25); `android/key.properties` (fora do git) aponta para ela; o
  `empacotar.py` recusa um APK com outra assinatura. Falta: o utilizador guardar uma 2.ª cópia da pasta.
- Próximo: tarefa 2 (preferências dos Jogos na cópia de segurança: `lib/dados/copia_seguranca.dart`).
