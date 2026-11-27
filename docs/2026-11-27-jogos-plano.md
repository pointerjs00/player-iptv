# Jogos (onde dá o jogo e ver com um toque): plano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** um ecrã «Jogos» com os jogos das competições seguidas, os canais portugueses onde dão e, para cada canal, as fontes de todas as listas do Ver TV, ordenadas pela probabilidade de funcionar. «▶ Ver» abre a melhor e passa sozinho à seguinte se falhar.

**Architecture:** adaptadores em `lib/desporto/`, todos com funções puras e testados com respostas gravadas:
- **jogos:** FotMob, ESPN e FPB, que produzem `Jogo`;
- **grelhas:** guia de TV do FotMob, MEO e Sport TV, que produzem `Emissao`.

Um `Casador` junta-os em `Transmissao`. Um `IndiceCanais` (num isolate) liga cada canal canónico às fontes das listas, e o `OndeVer` ordena-as. O player passa a aceitar fontes de várias listas (`FonteCanal`) e ganha a troca automática.

**Tech Stack:** Dart e Flutter, como o resto da app; `lib/rede/http.dart` (raízes TLS incluídas, `RitmoHost`, `Cancelamento`); cache em JSON com `escreverAtomico`; isolates (`Isolate.run`).

**Spec:** docs/2026-11-27-jogos-design.md

## Global Constraints

- Texto em pt-PT, sempre com `tr()` e a chave em inglês em `lib/idioma/ingles.dart` (o `test/idioma` falha sem ela). Cores e medidas de `Tokens`; mensagens com `mostrarMensagem`/`mensageiroDe`.
- **D-pad em primeiro lugar:**
  - cada linha é uma só paragem do foco, e os filtros são uma fila;
  - a TV a 960×540 a 80 % e o telemóvel a 360×800 com a letra a 1,3 não transbordam.
- **Pedidos:**
  - só os do §6 da spec, com cache;
  - identificação genérica (sem nome do utilizador, e-mail ou ids da conta);
  - nunca registar nem mostrar links de streams, MACs ou credenciais das listas.
- **Poupar dados móveis:** sem atualização em segundo plano em dados móveis. A atualização à mão das grelhas passa por `PoupancaDados.autorizar`.
- **Edição de partilha:** tudo atrás de `if (!edicaoPartilha)` (constante, para o compilador cortar o código). Os anfitriões (`fotmob`, `meo.pt`, `sporttv`, `fpb.pt`, `espn`) entram em `PROIBIDOS_PARTILHA` em `ferramentas/empacotar.py`. Revê-se se a decisão 1 da spec mudar.
- **Testes:**
  - sem rede nem relógio de parede: relógio injetável e cliente HTTP falso com as respostas gravadas em `test/desporto/respostas/`;
  - `flutter analyze` sem avisos, `flutter test` verde;
  - `flutter test --dart-define=PARTILHA=true test/edicao` verde.
- **Respostas gravadas:** gravam-se a partir do browser, como na análise (o que a própria página carregou). Só se guardam as partes necessárias, sem dados pessoais.

## Review Focus

1. **Falsos positivos no casamento**:
   - Sporting CP ≠ Sporting CP B;
   - jogo feminino ≠ masculino;
   - a repetição da DAZN no dia seguinte não conta como direto;
   - «Antevisão Marítimo x Nacional» não é o jogo. — Task 7.
2. **Canais trocados:** «SPORTV» (Brasil) ≠ «SPORT TV»; «DAZN 1» espanhol ≠ português; «SPORT TV 1» ≠ «SPORT TV 1 PREMIUM» de outro país. — Task 2/8.
3. **Fuso horário da MEO:** um programa às 20:00 de 15/7 (verão) é às 19:00 UTC; às 20:00 de 15/1 é às 20:00 UTC. — Task 5.
4. **Troca automática sem ciclos:** cada fonte tenta-se uma vez; ao fim de todas, um erro claro; sair do player cancela a troca; não fica uma fonte a tocar por trás. — Task 9.
5. **Desempenho:** índice de 32 listas com até 100 mil canais, sem bloquear a interface; reconstrução só quando a cache muda. — Task 8.

---

### Task 1: Catálogo, modelo e confirmação dos ids em falta

**Files:** Create `lib/desporto/modelo.dart`, `lib/desporto/catalogo.dart`; Test `test/desporto/catalogo_test.dart`.

**Interfaces:**
- `enum Desporto { futebol, tenis, basquetebol }`
- `class Competicao { String id; Desporto desporto; String nome; String? fotmob /* primaryId */; String? espn /* slug ou tour */; String? fpb; bool seguidaPorOmissao; }`
- `class Jogo { String id /* fonte:id */; Desporto desporto; String competicaoId; String casa, fora; String? casaCurto, foraCurto; String? emblemaCasa, emblemaFora; DateTime inicio /* UTC */; EstadoJogo estado; String? resultado; String? minuto; String? ronda; bool feminino; }` e `enum EstadoJogo { agendado, aoVivo, intervalo, terminado, adiado, cancelado }`
- `class CanalTv { String id /* 'sporttv1' */; String nome; String? meo /* callLetter */; String? sportTv; List<String> nomesFotmob; List<String> alternativos; }` com os canais do §5 da spec.
- `class Emissao { String canal /* CanalTv.id */; DateTime inicio, fim; String titulo; bool? direto; String origem; }`
- `class Transmissao { String jogoId; String canal; Confianca confianca; String origem; }` e `enum Confianca { confirmado, provavel, possivel }`
- `catalogoCompeticoes` (as do §4 da spec, com os ids confirmados) e `catalogoCanais`.

- [ ] Confirmar os ids «a confirmar» do §4: Taça do Rei saudita, Liga das Nações B/C/D e as qualificações (Europeu; Mundial UEFA e CONMEBOL). Procurar pelo nome e pelo país em respostas reais de `matches?date=`, e anotar no catálogo a data da confirmação.
- [ ] Testes que falham: não há ids repetidos; cada competição tem fonte; cada `CanalTv` tem pelo menos um nome; as competições seguidas por omissão são as do §2.
- [ ] Correr → FALHAM. Implementar. PASSAM; analyze.
- [ ] Commit `feat(desporto): modelo, catálogo de competições e canais portugueses`

### Task 2: Nomes de canais e de equipas

**Files:** Create `lib/desporto/nomes.dart`; Test `test/desporto/nomes_test.dart` (com nomes reais das listas e títulos reais da MEO e da Sport TV gravados na análise).

**Interfaces:**
- `CanalReconhecido? reconhecerCanal(String nomeNaLista, {String grupo = ''})` → `(CanalTv canal, Qualidade qualidade, bool portugues, double confianca)`. Tira os prefixos de país, a qualidade (4K/UHD/FHD/HD/SD/HEVC/H265/50FPS e os sobrescritos ᴴᴰ ⁴ᴷ), «(backup)», «VIP» e «Alt».
- `String normalizarEquipa(String nome)` e `bool mesmaEquipa(String a, String b)`: acentos, sufixos (FC/SC/CF/CD/SAD), abreviaturas e o dicionário de alternativos (clubes portugueses, os grandes estrangeiros e as seleções em português e inglês). As reservas (B, Sub-23, Sub-19) nunca são iguais à equipa principal.
- `TituloEmissao? lerTitulo(String titulo)` → modalidade, feminino, casa, fora, competição e direto. Devolve null para títulos de enchimento: o nome do canal, «Fora de Horas», «Sem Transmissão», «Antevisão», «Resumo», «Highlights» e «Magazine».

- [ ] Testes que falham:
  - **canais reconhecidos:**
    - «|PT| SPORT TV 1 FHD» → sporttv1, FHD, português;
    - «PT: SPORTTV1 ᴴᴰ» → sporttv1;
    - «SPORT TV+ 4K» → sporttvmais;
    - «ELEVEN SPORTS 1» → dazn1 com confiança mais baixa;
    - «BENFICA TV» → btv;
  - **canais rejeitados:**
    - «|BR| SPORTV 1» → null;
    - «DAZN 1 ES» e «|DE| DAZN 1» → não português;
  - **equipas:**
    - mesmaEquipa(«FC Porto», «Porto»), mesmaEquipa(«Sporting CP», «Sporting») e mesmaEquipa(«Man United», «Manchester United») → true;
    - mesmaEquipa(«Sporting CP B», «Sporting CP») → false;
  - **títulos:**
    - lerTitulo(«Basquetebol Fem.: Benfica x Uzkk Student Nis - Eurocup Women») → feminino;
    - lerTitulo(«DAZN 3») → null.
- [ ] Correr → FALHAM. Implementar. PASSAM; analyze.
- [ ] Commit `feat(desporto): reconhecer canais e equipas pelo nome`

### Task 3: Cache das fontes e cliente

**Files:** Create `lib/desporto/armazem_desporto.dart`, `lib/desporto/cliente_desporto.dart`; Test `test/desporto/armazem_test.dart`.

**Interfaces:**
- `ArmazemDesporto.abrir(Directory)` com `Future<T?> ler<T>(String chave, Duration validade, T Function(Object?) de)` e `Future<void> gravar(String chave, Object json)`. Usa `escreverAtomico` e `arrumar({required DateTime agora})`, que apaga o que tem mais de 8 dias.
- `ClienteDesporto({Future<String> Function(Uri, {Map<String,String> cabecalhos})? obter, DateTime Function()? agora})`. Usa `lib/rede/http.dart` e respeita `RitmoHost` e `Cancelamento`. Nos testes recebe um `obter` falso.
- Validades do §6 da spec, numa tabela única.

- [ ] Testes que falham: dentro da validade não pede à rede; fora dela pede e regrava; uma falha da rede com cache antiga devolve a antiga marcada como velha (`velho: true`); `arrumar` apaga o que tem mais de 8 dias.
- [ ] Correr → FALHAM. Implementar. PASSAM; analyze.
- [ ] Commit `feat(desporto): cache em disco e cliente das fontes`

### Task 4: FotMob — jogos do dia e guia de TV

**Files:** Create `lib/desporto/fontes/fotmob.dart`; Test `test/desporto/fotmob_test.dart` + `test/desporto/respostas/fotmob-matches-20261127.json`, `fotmob-tvguide-pt.json` (recortes).

**Interfaces:**
- `Future<List<Jogo>> jogosFotmob(ClienteDesporto, DateTime dia, Set<String> competicoes)`. Pede `api/data/matches?date=AAAAMMDD&timezone=Europe/Lisbon&ccode3=PRT&includeNextDayLateNight=true` e filtra pelas competições seguidas por **`primaryId`** (não por `id`). Limpa os caracteres de direção do minuto.
- `Future<List<(String jogoId, Emissao)>> guiaTvFotmob(ClienteDesporto)`. Pede `api/data/tvguide?country=pt&timezone=Europe/Lisbon`. Cada `channels[].name` passa a `CanalTv` pelo `nomesFotmob`. «Canal a confirmar» é ignorado.
- Emblemas: `images.fotmob.com/image_resources/logo/teamlogo/<id>_small.png` (a confirmar no 1.º passo).

- [ ] Gravar as respostas a partir do browser e confirmar o endereço dos emblemas.
- [ ] Testes que falham:
  - a Bélgica (`id` 937988, `primaryId` 40) entra quando a Pro League é seguida;
  - um jogo da Ligue 2 não entra;
  - Marítimo–Nacional tem a emissão `sporttv1` com confiança Confirmado;
  - Moreirense–Santa Clara («Canal a confirmar») não tem emissão;
  - `utcTime` → `inicio` em UTC.
- [ ] Correr → FALHAM. Implementar. PASSAM; analyze.
- [ ] Commit `feat(desporto): jogos e guia de TV do FotMob`

### Task 5: MEO — grelha por canal e dia

**Files:** Create `lib/desporto/fontes/meo.dart`, `lib/desporto/hora_lisboa.dart`; Test `test/desporto/meo_test.dart`, `test/desporto/hora_lisboa_test.dart` + respostas gravadas (SPT1HD, DAZN2, SLBHD, EURHD, de 27/11).

**Interfaces:**
- `Future<List<Emissao>> grelhaMeo(ClienteDesporto, CanalTv canal, DateTime dia)`. Pede `GetLiveChannelProgramsByDate?callLetter=<meo>&date=AAAA-MM-DD&userAgent=IPTV_OFR_GTV`. Lê `Result[].Title/StartDate/EndDate` e marca `direto` quando há «(Direto)».
- `DateTime lisboaParaUtc(DateTime local)` com a regra portuguesa do horário de verão: do último domingo de março à 01:00 UTC ao último domingo de outubro à 01:00 UTC.

- [ ] Testes que falham:
  - títulos de enchimento ficam de fora;
  - «Ajax x FC Thun - UEFA Conference League» às 22:30 de 27/11 (repetição) mantém-se como emissão, mas sem `direto`; o casador decide pela hora;
  - 20:00 de 15/7 → 19:00 UTC; 20:00 de 15/1 → 20:00 UTC;
  - uma resposta `Status` diferente de OK → lista vazia, sem rebentar.
- [ ] Correr → FALHAM. Implementar. PASSAM; analyze.
- [ ] Commit `feat(desporto): grelha da MEO com a hora de Lisboa`

### Task 6: Sport TV — guia oficial

**Files:** Create `lib/desporto/fontes/sporttv.dart`, `lib/desporto/devalue.dart`; Test `test/desporto/sporttv_test.dart` + `respostas/sporttv-guia.html` (recorte com ~20 programas).

**Interfaces:**
- `Object? lerDevalue(List<dynamic> raiz)`: resolve as referências por índice e os marcadores `Reactive`, `ShallowReactive`, `Ref`, `Set`, `Map` e `Date`.
- `Future<List<Emissao>> grelhaSportTv(ClienteDesporto)`. Faz GET de `sporttv.pt/guia` e lê `<script id="__NUXT_DATA__">`. Fica com os objetos que têm `canal`, `descricao`, `data` e `duracao`. `canal.nome` passa a `CanalTv` pelo campo `sportTv`. `direto = tipoEmissao == 'DIRETO'`. Guarda `modalidade.codigo` e `evento.nome` no título (formato «Modalidade: A x B - Evento»).

- [ ] Testes que falham:
  - «MARÍTIMO X CD NACIONAL» na SPORT.TV1 → emissão direta às 20:01 de 27/11;
  - a «ANTEVISÃO …» é lida mas marcada para o casador ignorar;
  - «INDIANA PACERS X OKLAHOMA CITY THUNDER» → basquetebol, direto;
  - HTML sem `__NUXT_DATA__` → lista vazia.
- [ ] Correr → FALHAM. Implementar. PASSAM; analyze.
- [ ] Commit `feat(desporto): grelha oficial da Sport TV`

### Task 7: Casador

**Files:** Create `lib/desporto/casador.dart`; Test `test/desporto/casador_test.dart`.

**Interfaces:**
- `List<Transmissao> casar(List<Jogo> jogos, List<Emissao> emissoes, {List<(String, Emissao)> ligadasPorId = const []})`. As regras e a confiança são as do §7 da spec. As ligadas por id (FotMob) são Confirmado.

- [ ] Testes que falham (Review Focus 1):
  - Sporting CP B–Amarante não casa com «Sporting CP x …»;
  - um jogo masculino não casa com «Fem.»;
  - a repetição da DAZN no dia seguinte não casa;
  - «Antevisão» não casa;
  - Feyenoord–FC Porto casa com «Feyenoord x FC Porto - Liga dos Campeões» (MEO, Provável) e com a Sport TV DIRETO (Confirmado), e fica a confiança mais alta;
  - «Ténis: ATP Finals (Direto)» → Possível em todos os encontros desse torneio na janela;
  - uma emissão 2 h depois do início não casa.
- [ ] Correr → FALHAM. Implementar. PASSAM; analyze.
- [ ] Commit `feat(desporto): casar jogos com as emissões dos canais`

### Task 8: Índice de canais das listas e «Onde ver»

**Files:** Create `lib/desporto/indice_canais.dart`, `lib/desporto/onde_ver.dart`; Modify `lib/dados/preferencias.dart` (associações manuais, «funcionou da última vez», qualidade preferida); Test `test/desporto/indice_canais_test.dart`, `test/desporto/onde_ver_test.dart`.

**Interfaces:**
- `IndiceCanais(Biblioteca)` com `Future<void> atualizar()`. Num isolate, lê só as listas cuja `dataCache` mudou. Expõe `List<FonteCanal> fontes(String canalTv)` e `int listasSemCache`. Guarda o índice em `desporto/indice.json`.
- `class FonteCanal { Lista lista; Canal canal; Qualidade qualidade; }`
- `List<FonteCanal> ordenarFontes(List<FonteCanal>, {UltimaFonte? funcionou, Qualidade preferida})`, pela ordem do §8 da spec, usando `estadoDe(lista)`.
- Preferências: `associacoesCanais` (lista → canal da lista → `CanalTv.id`, ou «não é este»), `ultimaFonte` (por `CanalTv.id`: lista, canal e data) e `qualidadePreferida`.

- [ ] Testes que falham:
  - **Review Focus 2:** «|BR| SPORTV 1» não entra; «DAZN 1» de um grupo «ESPAÑA» não entra;
  - 3 listas com Sport TV 1 → ordem: a que funcionou da última vez, depois as que funcionam, e por fim as que não funcionam (marcadas);
  - **Review Focus 5:** uma lista de 100 mil canais indexa num isolate; uma 2.ª chamada sem mudança na cache não relê nada (`leiturasCache` igual);
  - a associação manual sobrepõe-se ao reconhecimento.
- [ ] Correr → FALHAM. Implementar. PASSAM; analyze.
- [ ] Commit `feat(desporto): índice de canais das listas e ordem das fontes`

### Task 9: Player com fontes de várias listas e troca automática

**Files:**
- Modify:
  - `lib/ui/player/abrir_canal.dart`: `abrirFontes(context, List<FonteCanal>, {bool trocaAutomatica})`;
  - `lib/ui/player/player_canais.dart`: `trocaAutomatica`, a mensagem da troca, e ↑/↓ a trocar de fonte;
  - `lib/janelas/janela_player.dart`: a lista por índice e o nome da lista por canal na mensagem `abrir`;
  - `lib/ui/player/tempo_visto.dart`: o tempo visto pela lista da fonte;
  - `lib/main.dart`: o lado `--player` lê a lista por canal.
- Test: `test/ui/player/fontes_jogo_test.dart` (motor falso) e `test/janelas/janela_player_fontes_test.dart`.

**Interfaces:**
- `PlayerCanais(... resolver: (c) => …)`: o resolver procura a lista da fonte pelo índice.
- `trocaAutomatica: true` faz o seguinte:
  - um erro ao abrir, ou o `VigiaAbertura` sem imagem, passa ao índice seguinte com `mostrarMensagem(tr('{0} não respondeu em {1}; a tentar {2}…'))`;
  - quando todas as fontes falharam, mostra o cartão de erro «Nenhuma das {0} fontes funcionou»;
  - um êxito chama `aoFuncionar(FonteCanal)`, que grava a «ultimaFonte».
- Windows: `JanelaPlayer.mostrarFontes(List<FonteCanal>)`. O pedido `fonte` resolve com a conta da lista daquele índice.

- [ ] Testes que falham (Review Focus 4):
  - 3 fontes, as 2 primeiras falham → toca a 3.ª, com 2 mensagens, e cada uma foi tentada uma vez;
  - as 3 falham → cartão de erro, sem nova tentativa;
  - sair durante a troca → nada mais abre;
  - o resolver da fonte 2 usa a conta da lista 2;
  - o tempo visto fica na lista da fonte que tocou;
  - no Windows, a mensagem `abrir` leva o nome da lista por canal, e o pedido `fonte` do índice 1 usa a conta da lista 1.
- [ ] Correr → FALHAM. Implementar. PASSAM; suite + analyze; `flutter build apk` e `flutter build windows` compilam.
- [ ] Commit `feat(player): fontes de várias listas com troca automática`

### Task 10: Serviço «Jogos» (junta tudo)

**Files:** Create `lib/desporto/servico_jogos.dart`; Test `test/desporto/servico_jogos_test.dart`.

**Interfaces:**
- `ServicoJogos extends ChangeNotifier` com `Future<void> carregar(DateTime dia, {bool forcar = false})`.
  - Pede os jogos ao FotMob; as emissões ao guia TV do FotMob, à MEO (os canais do catálogo; hoje e amanhã por omissão, os outros dias quando se escolhem) e à Sport TV; depois casa tudo.
  - Expõe `List<JogoComCanais> jogos(FiltroJogos)` e `estado` (a carregar, pronto, velho, erro por fonte).
- Uma fonte que falha não impede as outras.
- Em dados móveis, sem `forcar`, só usa a cache e o guia do FotMob.

- [ ] Testes que falham:
  - com a MEO a dar erro, os jogos e os canais do FotMob aparecem, e o estado diz «MEO indisponível»;
  - sem rede e com cache de há 2 h → estado «velho» com a data;
  - os filtros (dia, desporto, competição, só em direto, só com canal) dão os jogos certos;
  - mudar de dia não volta a pedir o que está na cache.
- [ ] Correr → FALHAM. Implementar. PASSAM; analyze.
- [ ] Commit `feat(desporto): serviço que junta jogos, grelhas e canais`

### Task 11: Ecrã «Jogos», «Onde ver» e Definições

**Files:**
- Create:
  - `lib/ui/jogos/tela_jogos.dart`;
  - `lib/ui/jogos/linha_jogo.dart`;
  - `lib/ui/jogos/painel_jogo.dart` (coluna à direita e detalhe no telemóvel);
  - `lib/ui/jogos/folha_onde_ver.dart`;
  - `lib/ui/definicoes/secao_jogos.dart`.
- Modify:
  - `lib/ui/principal/tela_principal.dart` (`Seccao.jogos`, ícone e rótulo);
  - `lib/main.dart`;
  - `lib/ui/definicoes/tela_definicoes.dart`;
  - `lib/idioma/ingles.dart`.
- Test: `test/ui/jogos_test.dart`, `test/ui/jogos_telemovel_test.dart`, `test/ui/jogos_dpad_test.dart`.

**Interfaces:** as do §10 da spec.
- **Filtros:** uma fila de chips com dia, desporto e competições, e os interruptores.
- **Linha do jogo:**
  - hora ou «● AO VIVO» com o resultado;
  - emblemas e equipas, competição e ronda;
  - as etiquetas dos canais (`Etiqueta`, com a marca de confiança);
  - «▶ Ver».
- **Coluna à direita** a partir de 900 de largura, no estilo do `PainelCanal`.
- **«Onde ver»:** cada fonte com a lista, a pílula do estado, o nome do canal na lista, a qualidade e «Funcionou da última vez»; OK abre `abrirFontes`. Tem também «Atualizar canais» para as listas sem cache, e «Este não é o canal».
- **Definições › Jogos:** desportos e competições seguidos, equipas favoritas, qualidade preferida, mostrar jogos sem canal e limpar as associações.

- [ ] Testes que falham:
  - **D-pad:**
    - ↓ percorre os jogos; ←/→ na linha escolhe uma etiqueta de canal; OK abre o «Onde ver»; OK mantido faz «Ver»;
    - BACK fecha a folha e devolve o foco à etiqueta;
  - a TV a 960×540 a 80 % mostra pelo menos 5 jogos;
  - **telemóvel:**
    - a 360×800 com a letra a 1,3 não transborda;
    - os filtros ficam numa fila que desliza;
    - tocar num jogo abre o detalhe;
  - os estados vazios do §10;
  - um jogo sem canal só aparece com «Mostrar jogos sem canal».
- [ ] Correr → FALHAM. Implementar. PASSAM; suite + analyze.
- [ ] Commit `feat(jogos): ecrã dos jogos com onde ver e definições`

### Task 12: Lançamento da fase 1

- [ ] Guardar a edição de partilha: `if (!edicaoPartilha)` na secção, nas Definições e no `main`; os anfitriões em `PROIBIDOS_PARTILHA`. O `test/edicao` confirma que a secção não existe.
- [ ] Novidades (pt e en), versão no `pubspec.yaml` (com `sed`) e o procedimento de lançamento habitual.
- [ ] Ver no aparelho (TV, telemóvel, Windows), num dia com jogos da Liga Portugal, da Champions e da DAZN.
- [ ] Commit `feat(jogos): fase 1 — futebol, onde ver e troca automática`

### Task 13 (fase 2): Ténis e basquetebol

**Files:** Create `lib/desporto/fontes/espn.dart` (ATP, WTA e NBA, seguindo os adaptadores do bet-intel em `apps/api/src/services/sportsData/espnTennis.ts` e `espnBasketball.ts`) e `lib/desporto/fontes/fpb.dart`; Modify o catálogo, o casador (ténis por torneio) e o serviço; Tests com respostas gravadas.

- [ ] Primeiro passo: confirmar o campo do nível do torneio na ESPN (para excluir WTA 125 e Challengers) e a estrutura e paginação do HTML da FPB.
- [ ] Testes que falham:
  - **ténis:** um torneio 250 entra e um WTA 125 não; os encontros de «ATP Finals» têm a Sport TV como Possível pela grelha;
  - **NBA:** um jogo às 00:30 UTC aparece no dia certo de Lisboa (pede o dia anterior dos EUA); «INDIANA PACERS X OKLAHOMA CITY THUNDER» na Sport TV casa com o jogo da ESPN;
  - **LPB:** «SC Braga x SL Benfica» de 5/12 às 18:00 aparece e casa com a DAZN quando a grelha o tiver.
- [ ] Correr → FALHAM. Implementar. PASSAM; suite + analyze.
- [ ] Commit `feat(desporto): ténis (ATP/WTA) e basquetebol (NBA e LPB)`

### Task 14 (fase 3): Ao vivo, Início e extras

- [ ] **Resultados ao vivo:** só com o ecrã «Jogos» aberto, a cada 60 s, apenas para os jogos a decorrer (FotMob para o futebol, ESPN para o resto). Testes com relógio falso: pára ao sair do ecrã.
- [ ] **Fila «Hoje há jogo» no Início:** só os jogos das equipas favoritas e das competições seguidas, com «▶ Ver». Os testes de foco e de transbordo do Início continuam verdes.
- [ ] **«Outras fontes» no player:** durante um jogo, um botão abre as outras fontes do mesmo canal sem sair. Testes: muda de fonte e o tempo visto segue.
- [ ] **Logótipos dos canais**, com o endereço da MEO (`Channels/logos/image?callLetter=`) e cache.
- [ ] Commits, um por ponto.
