# Player IPTV — plano de implementação

**Objetivo:** app Flutter (Windows, Android, Android TV) que guarda listas IPTV, mostra o resultado da
última verificação, abre os grupos/canais de cada lista e toca o canal (janela separada no Windows,
ecrã inteiro no Android).

**Spec:** `docs/2026-11-16-player-design.md`
**Referência de comportamento:** `../tv-management/motor/*.py` e `../tv-management/tests/*.py`.
**Stack:** Flutter (estável), Dart 3, media_kit, desktop_multi_window, path_provider, archive (zip),
http fakes com `dart:io HttpServer` nos testes.

## Restrições globais

- Um só código para Windows/Android/Android TV; tudo utilizável só com setas/OK/Voltar.
- Credenciais só vão para o portal da própria lista; nada de telemetria; o pacote nunca leva contas.
- Nome das listas: `NNNHOST DDMMAA` (sem data: `NNNHOST`); INC à frente nas inconclusivas.
- Chave de deduplicação igual à do verificador (sem `/c/`, sem porta por omissão, MAC em maiúsculas).
- Android abre o player sempre em **ecrã inteiro** (sem PiP); Windows numa **janela separada**.
- Interface em português de Portugal. TDD: cada tarefa começa por testes que falham.

## Pontos a vigiar (não cobertos diretamente pelos testes)

1. Portais Stalker lentos/meio partidos: a lista de canais tem de aparecer por páginas, com cancelar.
2. Listas M3U enormes (100 000+ linhas): parse fora da UI (isolate) e lista virtualizada.
3. Foco perdido na TV depois de voltar do player ou de fechar um diálogo.
4. Stream que não abre no player: mensagem clara e "tentar de novo", nunca ecrã preto mudo.
5. Duas listas iguais importadas de formatos diferentes (JSON + .ini) ficam numa só.

---

## Fase 0 — Ambiente e esqueleto

### Tarefa 0.1: Ferramentas
- Instalar o Flutter SDK (estável) e o Visual Studio 2022 Build Tools com "Desktop development with C++".
- Android SDK já existe (`%LOCALAPPDATA%\Android\Sdk`, plataformas 34–37, JDK 17).
- Verificação: `flutter doctor` sem erros para Windows e Android.

### Tarefa 0.2: Projeto
- `flutter create --platforms=windows,android --org pt.player player_iptv` dentro deste repositório.
- Dependências: `media_kit`, `media_kit_video`, `media_kit_libs_video`, `desktop_multi_window`,
  `path_provider`, `archive`, `file_picker`.
- `analysis_options.yaml` com `flutter_lints`; `.gitignore` com `build/`, `*.json` de contas de teste.
- Verificação: `flutter test` (teste vazio) e `flutter build windows` / `flutter build apk --debug`.

## Fase 1 — Modelo e importação (Dart puro)

### Tarefa 1.1: `lib/modelo/conta.dart`
- Produz: `enum Tipo {stalker, xtream, m3u}`; `class Conta {nome, tipo, endereco, mac, utilizador,
  password, original}`; `Object chave(Conta)`; `String nomeLista(int n, Conta c, String validade)`;
  `Conta? contaDeDict(Map)`; `Conta? contaDeLinha(String)`; `List<Conta> deduplicar(List<Conta>)`;
  `String linkConta(Conta)`.
- Testes (`test/modelo/conta_test.dart`), portados de `tests/test_conta.py`: `nome lista`,
  `a mesma lista escrita de outra forma tem a mesma chave`, `deduplicar junta variantes`,
  `xtream dict com get.php usa a raiz`, `link conta`, `linhas outras`.

### Tarefa 1.2: Importadores `lib/importar/`
- Produz: `List<Conta> lerAccountsJson(String)`, `Conta? lerIni(String texto, String nomeFicheiro)`,
  `List<Conta> lerLinhas(String)`, `ImportacaoHistorico lerHistoricoVerificador(String)` (contas +
  último estado/validade por chave), `List<Conta> importarFicheiros(List<File>)` (decide pelo
  conteúdo, não só pela extensão).
- Testes: ini do exemplo `003NXTBOX 161027.ini` (CRLF e LF); JSON com campos em falta; histórico com
  entradas inválidas ignoradas; ficheiro .txt com linhas misturadas e lixo.

### Tarefa 1.3: Parser M3U `lib/importar/m3u.dart`
- Produz: `ConteudoLista lerM3u(String)` → grupos (pela ordem de aparição) e canais
  `{nome, grupo, url, logo, userAgent, referer}`; corre num isolate acima de 5 000 linhas.
- Testes: `group-title` ausente → grupo "Sem grupo"; `#EXTVLCOPT:http-user-agent`; atributos com
  vírgulas no nome; 100 000 canais em < 2 s.

## Fase 2 — Biblioteca e ecrã Início

### Tarefa 2.1: `lib/dados/biblioteca.dart`
- Produz: `class Biblioteca` com `listas` (Conta + `UltimaVerificacao? {estado, motivo, data,
  validade, canais}` + favoritos), `adicionar(List<Conta>) -> int novas`, `remover`, `guardar`
  (escrita atómica: ficheiro temporário + rename), `abrir(Directory)`.
- Testes: adicionar repetidas não duplica; ficheiro corrompido → começa vazia e guarda cópia `.bak`;
  ordem estável (nº de ordem não muda ao apagar outras).

### Tarefa 2.2: Início `lib/ui/inicio/`
- Cartão: nome `NNNHOST DDMMAA`, tipo, selo de estado e data relativa ("há 2 dias"), validade,
  botão "Verificar de novo"; barra com pesquisa, filtro por estado e ordenação (como o verificador).
- "Adicionar listas": ficheiros/pasta (`file_picker`), colar texto, URL M3U.
- Testes de widget: cartões aparecem com o estado; filtrar por "Não funciona"; navegar com setas e
  OK abre o conteúdo (Fase 4); tocar no botão chama a verificação (Fase 6, falso por agora).

## Fase 3 — Protocolos (abrir listas e obter o link do canal)

Interface comum (`lib/protocolos/protocolo.dart`):
`Future<ConteudoLista> abrir(Conta, {Cancelamento?})` e `Future<FonteVideo> fonte(Conta, Canal)`
com `FonteVideo {url, headers}`.

### Tarefa 3.1: Rede `lib/rede/http.dart`
- Timeouts, cancelamento, ritmo por host e repetição em 429 (porta de `motor/rede.py`).
- Servidor falso de testes `test/apoio/servidor_falso.dart` (porta de `tests/servidor_falso.py`).

### Tarefa 3.2: Xtream `lib/protocolos/xtream.dart`
- `player_api.php` (user_info → validade), `get_live_categories`, `get_live_streams`;
  URL `/live/user/pass/id.ts` (ou `.m3u8` se `allowed_output_formats` não tiver ts).
- Testes portados de `tests/test_xtream.py` (validade, conta expirada, categorias vazias).

### Tarefa 3.3: Stalker `lib/protocolos/stalker.dart`
- handshake → token; get_profile; get_main_info (validade, incluindo o campo `phone`);
  `get_genres`; `get_ordered_list` por página (e `get_all_channels` quando existe);
  `create_link` → URL com o stream preenchido; headers MAC/Bearer.
- Testes portados de `tests/test_stalker.py` (endpoints `/c/` e `/stalker_portal/`, 456/459,
  `validade_do_texto`, `_preencher_stream`).

### Tarefa 3.4: M3U remoto
- Descarregar a lista (com o user-agent da lista) e usar o parser da 1.3; Xtream `get.php` sem
  `player_api` cai aqui.

## Fase 4 — Conteúdo da lista `lib/ui/conteudo/`

- Duas colunas (grupos | canais); no telemóvel, chips de grupos + lista. Pesquisa global de canais
  sem acentos; filtro na coluna de grupos; ★ Favoritos no topo; contagens por grupo.
- Carregamento por páginas com indicador e "Cancelar"; cache em disco com "Atualizar".
- Testes de widget: pesquisar "rtp" mostra canais de vários grupos; filtrar grupos; marcar favorito
  persiste; foco: setas entre colunas, Voltar regressa ao Início com o cartão focado.

## Fase 5 — Player

### Tarefa 5.1: Player comum `lib/ui/player/player.dart`
- media_kit com `FonteVideo` (headers); overlay com nome/grupo/lista; cima/baixo = canal anterior/
  seguinte do grupo; OK mostra o overlay; erro → mensagem + "Tentar de novo" (pede `fonte()` outra vez,
  porque os links Stalker expiram).

### Tarefa 5.2: Android — ecrã inteiro
- Rota em ecrã inteiro, `SystemChrome.setEnabledSystemUIMode(immersiveSticky)`, orientação livre na
  TV e paisagem no telemóvel; Voltar sai e devolve o foco ao canal na lista.
- Manifesto: `LEANBACK_LAUNCHER`, `android:banner`, `touchscreen required=false`.

### Tarefa 5.3: Windows — janela separada `lib/janelas/player_windows.dart`
- `desktop_multi_window`: 1.ª escolha cria a janela do player; as seguintes enviam
  `{fonte, nome, grupo, lista}` e a janela troca de canal; F11/duplo clique = ecrã inteiro;
  fechar a janela pára o vídeo. Se o media_kit falhar na 2.ª janela: lançar o .exe com `--player` e
  falar por socket em 127.0.0.1 (registar a decisão no plano).

## Fase 6 — Verificação

### Tarefa 6.1: Motor `lib/verificar/`
- Porta de `motor/verificador.py`, `canais.py`, `candidatos.py`, `video.py`: 3 estados, vários
  canais (funciona se um abrir), 2.ª volta das inconclusivas, reteste de uma conta, limite por conta,
  workers, um MAC de cada vez, validade.
- Testes portados de `tests/test_verificador.py`, `test_canais.py`, `test_video.py`.

### Tarefa 6.2: Ligação ao Início
- "Verificar de novo" num cartão e "Verificar todas"; o resultado fica em `UltimaVerificacao` e o
  cartão atualiza ao vivo.

## Fase 7 — Separador "Verificar"

- Paridade com `tv-management/interface.html`: fontes (ficheiros, colar, stbstalker entre datas),
  escolha de canais, análise ao vivo, reteste, seleção, exportar Accounts.json / zip de .ini,
  "Adicionar à biblioteca" (as que funcionam ou as selecionadas).
- Testes: os de `tests/test_interface.py` que fazem sentido sem HTTP (exportar, seleção, repetidas).

## Fase 8 — Pacotes e testes reais

- Windows: `flutter build windows` → zip portátil (como o `VerificadorIPTV.zip`).
- Android: `flutter build apk --release --split-per-abi`; instalar por ADB no telemóvel e no
  Fire Stick 4K Max / Android TV.
- Lista de verificação manual: importar Accounts.json + .ini + M3U; abrir uma lista Stalker, uma
  Xtream e uma M3U; trocar de canal com o comando; Voltar; verificar de novo; janela do player no
  Windows com a principal em uso.

## Ordem e entregas

0 → 1 → 2 → 3 → 4 → 5 dão a **primeira versão utilizável** (listas, conteúdo, player). 6 e 7 trazem a
verificação para dentro da app; até lá, o Início mostra os resultados importados do
`historico.json` do verificador. 8 no fim de cada marco (v0.1 depois da Fase 5, v0.2 depois da 7).

---

## Registo de decisões durante a implementação

- **Fase 5.3 — janela do player no Windows:** em vez de `desktop_multi_window`, a janela do player é
  o mesmo .exe lançado com `--player <porta>`, ligado à janela principal por um socket em 127.0.0.1
  (linhas JSON). O link de cada canal é sempre pedido pela janela principal (no Stalker precisa da
  sessão do portal). Custo se estiver errado: trocar para outra forma de janela não mexe no player.
- **Fase 6 — verificação:** reaproveita os protocolos que abrem as listas (o mesmo código lista os
  canais para ver e para verificar). Diferença para o Python: a procura do canal de teste usa a
  lista completa de canais (não pesquisa por páginas primeiro).
- **Fase 7 — separador Verificar:** canais de teste, verificar todas/selecionadas, selecionar e exportar
  (Accounts.json ou zip de .ini). A importação do stbstalker entre datas ainda não foi portada.
- **Gravações da biblioteca** passam a ser feitas em fila (várias verificações a acabar juntas
  estragavam o ficheiro temporário).
