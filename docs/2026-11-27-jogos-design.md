# Jogos (onde dá o jogo e ver com um toque): análise e design

Data da análise: 27/11/2026. As fontes foram vistas no browser da app, a partir do teu PC, a partir do que as próprias
páginas públicas carregam; os pedidos diretos a APIs a partir do terminal foram recusados pelas permissões desta
sessão, por isso os formatos abaixo vêm das respostas que as páginas receberam.

## 1. Resumo

1. **É possível fazer o que pediste.** Há fontes que dizem o jogo, a hora e **em que canal português** dá. Juntando-as às
   tuas listas, o botão do canal mostra logo as fontes, ordenadas pela probabilidade de funcionar. «▶ Ver» abre a
   melhor e, se falhar, passa sozinho à seguinte.
2. **Futebol:** o **FotMob** dá os jogos de todas as competições que pediste e um **guia de TV para Portugal** (7 dias)
   com os canais de cada jogo (Sport TV 1–7, Sport TV +, DAZN 1–4, BTV, Canal 11, TVI, SIC, RTP…). Os ids de 36
   competições foram confirmados (§4).
3. **Grelhas oficiais dos canais:**
   - A **MEO** dá a grelha de 213 canais por canal e por dia (JSON), incluindo todos os que referiste: Sport TV,
     DAZN, BTV, Eurosport, RTP, SIC, TVI, V+, Canal 11, Sporting TV e Porto Canal.
   - A **Sport TV** dá a sua grelha oficial (10 dias), com a modalidade e a marca «DIRETO».
   - Juntas, cobrem o ténis e o basquetebol, que o FotMob não tem.
4. **Ténis e NBA:** a **ESPN**, já estudada e usada no bet-intel, tem todos os torneios ATP e WTA 250+, os Grand Slams
   e a NBA.
5. **LPB:** o calendário vem do site da **FPB** (página HTML). Em 2026/27 a liga passou a ser transmitida pela
   **DAZN**, segundo a Advanced Television.
6. **O bet-intel não se aproveita como código** (TypeScript, num servidor com Postgres e Redis). Aproveitam-se o
   estudo, os endpoints, as particularidades já descobertas e o desenho dos adaptadores. A app IPTV fala diretamente
   com as fontes, com cache em disco e poucos pedidos.
7. **Riscos principais:**
   - todas as fontes são **não documentadas** e podem mudar;
   - o **casamento de nomes** (equipas e canais) tem de ser cuidadoso. Por exemplo, «SPORTV» do Brasil não é a
     «SPORT TV», e a DAZN existe em vários países.
   
   Mitigação: várias fontes, níveis de confiança, testes com respostas gravadas e associação manual.
8. **Proposta:** 3 fases.
   1. Futebol e todo o «Onde ver» com troca automática de fonte.
   2. Ténis e basquetebol.
   3. Ao vivo, Início e extras.

## 2. O que se pretende

- Um ecrã **«Jogos»** com filtros por **dia**, **desporto** e **competição**, e a informação básica de cada jogo.
- Em cada jogo, os **canais** onde dá ou vai dar. Carregar num canal abre a lista desse canal **em todas as listas do
  Ver TV que o têm**.
- O objetivo é não ter de:
  1. ver em que canal dá;
  2. abrir uma lista;
  3. procurar o canal;
  4. experimentar, e repetir tudo se não funcionar.
- **Competições:**
  - **Futebol:**
    - **Ligas:** Liga Portugal Betclic, Premier League, Ligue 1, LaLiga, Bundesliga, Serie A, Eredivisie,
      Süper Lig, Saudi Pro League, Pro League (Bélgica), Scottish Premiership, Brasileirão, Liga Portugal 2 e
      Libertadores.
    - **Taças** das ligas e dos países dessas ligas.
    - **Europeias:** Champions, Liga Europa e Conference League.
    - **Seleções:** amigáveis, Liga das Nações, Europeu, Mundial, Copa América…
  - **Ténis:** ATP e WTA 250+ e Grand Slams.
  - **Basquetebol:** LPB e NBA.

## 3. Fontes avaliadas

| Fonte | O que dá | Acesso | Visto a 27/11 | Veredicto |
|---|---|---|---|---|
| **FotMob — jogos do dia** `fotmob.com/api/data/matches?date=AAAAMMDD&timezone=Europe/Lisbon&ccode3=PRT` | Todos os jogos de futebol do dia, por competição: id, equipas (id, nome, nome curto), resultado, estado (`utcTime`, `started`, `finished`, `cancelled`), jornada | Sem chave | Resposta vista. A competição vem com um id de época (`id`) e o id fixo em **`primaryId`**: a Bélgica aparece como 937988 com `primaryId` 40 | **Base dos jogos de futebol** |
| **FotMob — guia de TV PT** `fotmob.com/api/data/tvguide?country=pt&timezone=Europe/Lisbon` | 7 dias, por competição. Cada jogo traz id, `utcTime`, equipas, **`channels[].name`** e `isLive` | Sem chave | Resposta vista. Exemplos: Marítimo–Nacional → Sport TV 1; Nottm Forest–Chelsea → DAZN 1; Sporting B–Amarante → Sporting TV; Moreirense–Santa Clara → «Canal a confirmar» | **Base dos canais no futebol** (o jogo já vem ligado ao canal) |
| FotMob — canais por jogo `api/data/liveTvChannels?countryCode=PT&ids=…` | Canais de jogos escolhidos | Sem chave | Só vi o pedido, não a resposta | Reserva, se o guia não chegar |
| FotMob — competição `api/data/leagues?id=N` | Calendário e classificação de uma competição | Sem chave | Pedido visto | Para jogos para lá dos 7 dias (opcional) |
| **MEO — grelha** `meogouser.apps.meo.pt/Services/GridTv/GridTv.svc/GetLiveChannelProgramsByDate?callLetter=SPT1HD&date=AAAA-MM-DD&userAgent=IPTV_OFR_GTV` | Programas de **um canal num dia**: `Title`, `Synopsis`, `StartDate`, `EndDate`, `ProgramId` | GET sem chave | Respostas vistas para os canais do §5 (todos menos a Sport TV 5). O seletor vai de 6 dias atrás a 6 dias à frente (21/11 a 3/12) | **Base das grelhas** (todos os canais) |
| **Sport TV — guia oficial** `sporttv.pt/guia` | A grelha vem dentro da página (`<script id="__NUXT_DATA__">`, formato *devalue*): 1600 programas em 8 canais, com `canal.nome` (SPORT.TV1…7, SPORT.TV +), `descricao`, `data`, `duracao`, `modalidade`, `evento`, **`tipoEmissao`** (DIRETO, Recorded, Magazine…) | HTML | Descodificada: 24/11 a 7/12, ou seja, 10 dias à frente. Página com ~0,94 MB | **Confirmação na Sport TV** (ténis, NBA, Euroliga, futebol) |
| **ESPN** `site.api.espn.com/apis/site/v2/sports/tennis/{atp,wta}/scoreboard?dates=` e `…/basketball/nba/scoreboard?dates=` | Ténis: torneio, ronda, jogadores, hora e sets. NBA: equipas, hora e resultado | Sem chave | Validada no estudo do bet-intel (10/11/2026); adaptadores em `bet-intel/apps/api/src/services/sportsData` | **Base do ténis e da NBA** |
| **FPB — calendário** `fpb.pt/calendario/?epoca=2026/2027&genero=masculino&escalao=Sénior` | Jogos da Liga Betclic Masculina: data, hora, equipas, pavilhão | HTML | Página vista com os jogos de dezembro | **Base da LPB** |
| EPG das listas IPTV (já na app) | O guia de cada lista | — | Já existe (`lib/guia`) | Último recurso (canais que nenhuma grelha cobre) |
| A Bola `abola.pt/programacao/<data>` | Só a grelha do canal A Bola TV | — | Vista | Descartada |
| Eurosport.pt / NOS guia TV | — | — | 404 | Descartadas (a MEO cobre a Eurosport) |
| SofaScore, FlashScore | — | Bloqueiam pedidos normais (estudo do bet-intel) | — | Descartadas |
| football-data.org, TheSportsDB | Só calendário, sem canais | Chave | — | Desnecessárias |

**Particularidades a respeitar:**
- **FotMob:**
  - filtrar as competições por `primaryId`, porque o `id` muda por época ou fase;
  - o minuto ao vivo traz caracteres invisíveis de direção do texto, segundo o estudo do bet-intel;
  - os nomes das equipas vêm em inglês, com `shortName` (por exemplo, «Nottm Forest»).
- **MEO:**
  - as horas vêm sem fuso (`2026-11-27T00:30:00`). Assume-se a hora de Lisboa, o que tem de ser confirmado no
    horário de verão;
  - há títulos de enchimento: o nome do canal («DAZN 3») e «Fora de Horas: Sem Transmissão»;
  - **a DAZN repete os jogos no dia seguinte com o mesmo título** e nem sempre marca «(Direto)», por isso o direto
    tem de se decidir pela hora.
- **Formato dos títulos da MEO**, sempre `[Modalidade[ Fem.]: ]Casa x Fora - Competição[ (Direto)]`. Exemplos:
  - «Feyenoord x FC Porto - Liga dos Campeões»;
  - «Ténis: Estados Unidos x Hungria - Billie Jean King Cup Play-Offs»;
  - «Basquetebol Fem.: Benfica x Uzkk Student Nis - Eurocup Women»;
  - «Padel: México Major - Premier Padel (Direto)».
- **Sport TV:**
  - o título vem em maiúsculas («MARÍTIMO X CD NACIONAL») e a competição em `evento.nome`;
  - os programas «ANTEVISÃO …» ficam de fora.
- **ESPN:**
  - a NBA usa dias dos EUA: um jogo às 19:30 de Nova Iorque é à 00:30 UTC do dia seguinte, por isso pede-se também
    o dia anterior;
  - no futebol há um pedido por dia e por competição. Aqui não é preciso, porque o futebol vem do FotMob.

## 4. Competições: fonte e identificador

**Futebol (FotMob, `primaryId`):** ✓ significa confirmado a 27/11, abrindo a página de cada competição.

| Competição | id | Competição | id |
|---|---|---|---|
| Liga Portugal Betclic | 61 ✓ | Taça de Portugal | 186 ✓ |
| Liga Portugal 2 | 185 ✓ | Taça da Liga (PT) | 187 ✓ |
| Premier League | 47 ✓ | FA Cup · Taça da Liga (EFL Cup) | 132 ✓ · 133 ✓ |
| LaLiga | 87 ✓ | Copa del Rey | 138 ✓ |
| Bundesliga | 54 ✓ | DFB-Pokal | 209 ✓ |
| Serie A | 55 ✓ | Coppa Italia | 141 ✓ |
| Ligue 1 | 53 ✓ | Coupe de France | 134 ✓ |
| Eredivisie | 57 ✓ | KNVB Beker | 235 ✓ |
| Süper Lig | 71 ✓ | Taça da Turquia | 151 ✓ |
| Pro League (Bélgica) | 40 ✓ | Taça da Bélgica | 149 ✓ |
| Scottish Premiership | 64 ✓ | Scottish Cup · League Cup (Escócia) | 137 ✓ · 180 ✓ |
| Saudi Pro League | 536 ✓ | Taça do Rei (Arábia Saudita) | a confirmar |
| Brasileirão | 268 ✓ | Copa do Brasil | 9067 ✓ |
| Libertadores | 45 ✓ | Champions · Liga Europa · Conference | 42 ✓ · 73 ✓ · 10216 ✓ |
| Liga das Nações (Liga A) | 9806 ✓ | Ligas B, C e D | a confirmar |
| Europeu · Mundial | 50 ✓ · 77 ✓ | Qualificações (Europeu; Mundial UEFA e CONMEBOL) | a confirmar |
| Copa América | 44 ✓ | Amigáveis de seleções | 114 ✓ |

Os ids «a confirmar» encontram-se na 1.ª tarefa do plano, pelo nome e pelo país, nas respostas de
`matches?date=`. O catálogo fica num único ficheiro, fácil de corrigir.

**Ténis (ESPN):** ATP e WTA de 250 a Grand Slam. A ESPN também traz WTA 125 (e talvez Challengers); filtra-se pelo
nível do torneio, que ainda está por confirmar no formato da resposta. A Taça Davis e a BJK Cup ficam como opção,
desligadas por omissão.

**Basquetebol:** NBA pela ESPN; LPB (Liga Betclic Masculina) pela FPB.

## 5. Canais portugueses: o mesmo canal em cada fonte

| Canal (canónico) | MEO `callLetter` | Sport TV `canal.nome` | Nomes típicos nas listas IPTV |
|---|---|---|---|
| Sport TV + | SPTVHD | SPORT.TV + | SPORT TV+, SPORT TV PLUS, SPORTTV+ |
| Sport TV 1…7 | SPT1HD…SPT7HD | SPORT.TV1…7 | SPORT TV 1, SPORTTV1, STV1, \|PT\| SPORT TV 1 FHD |
| DAZN 1…5 | DAZN1…DAZN5 | — | DAZN 1, DAZN 1 PT, ELEVEN 1, ELEVEN SPORTS 1 (nome antigo) |
| BTV | SLBHD | — | BTV, BENFICA TV, SL BENFICA TV |
| Sporting TV | SCPHD | — | SPORTING TV |
| Porto Canal | PORTO | — | PORTO CANAL |
| Canal 11 | C11 | — | CANAL 11, 11 |
| A Bola TV | ABOLA | — | A BOLA TV |
| RTP1 · RTP2 | RTP1 · RTP2 | — | RTP 1, RTP1 HD |
| SIC · TVI · V+ TVI | SIC · TVI · VMAISTVI | — | SIC HD, TVI HD, V+ TVI, V MAIS |
| Eurosport 1 · 2 | EURHD · EURS2HD | — | EUROSPORT 1, EUROSPORT 2 |

Para cada canal, o nome que o FotMob usa (por exemplo «Sport TV 1», «DAZN 1», «Canal 11») liga-se ao mesmo canal
canónico. A MEO também serve os logótipos: `cdn-er-images.online.meo.pt/api/Channels/logos/image?callLetter=…`.

## 6. Arquitetura

```
 Jogos                      Grelhas (o que dá em cada canal)              As tuas listas
 FotMob (futebol)           FotMob guia TV PT (jogo → canal, direto)      caches de canais (Biblioteca)
 ESPN (ténis, NBA)          MEO (todos os canais, por dia)                        │
 FPB (LPB)                  Sport TV (oficial, DIRETO, modalidade)        IndiceCanais (isolate):
     │                      EPG das listas (último recurso)               canal canónico → [(lista, canal)]
     ▼                               ▼                                            │
  Jogo ───────────► Casador (equipas + hora + competição) ◄── Emissao             │
                          │                                                       │
                          ▼                                                       │
                Transmissao (jogo, canal canónico, confiança, origem)             │
                          │                                                       │
                          └──────────────► OndeVer ◄──────────────────────────────┘
                                    fontes ordenadas (funcionou da última vez, estado da lista,
                                    qualidade, validade)
                                           │
                                           ▼
                         Player com fontes de várias listas + troca automática
```

- **Tudo na app (Dart), sem servidor.** Pasta nova `lib/desporto/`, com os adaptadores em funções puras testadas
  com respostas gravadas, como no bet-intel.
- **Cache em disco** (`<dados>/desporto/`) com validade por fonte, para se poder ver «Jogos» sem rede:

  | Fonte | Validade |
  |---|---|
  | Jogos FotMob | 30 min no dia de hoje e 6 h nos dias seguintes |
  | Guia TV FotMob | 1 h |
  | MEO | 6 h por canal e por dia |
  | Sport TV | 3 h |
  | ESPN | 30 min hoje |
  | FPB | 24 h |

  Os dados com mais de 8 dias apagam-se.
- **Volume de pedidos:**

  | Pedido | Quantos |
  |---|---|
  | FotMob jogos | 1 por dia mostrado |
  | Guia TV FotMob | 1 para os 7 dias |
  | MEO | 25 canais × dias vistos; por omissão hoje e amanhã, 50 pedidos pequenos |
  | Sport TV | 1 página de ~1 MB |
  | ESPN | 2 por dia (ATP e WTA) + 2 da NBA |
  | FPB | 1 |

  Tudo sobre o cliente HTTP da app (`lib/rede/http.dart`, com as raízes TLS incluídas), com `RitmoHost` e
  identificação genérica, sem dados pessoais.
- **Poupar dados móveis:** em dados móveis não se atualiza em segundo plano. Atualizar à mão pede autorização
  (`PoupancaDados`), exceto o guia do FotMob, que é pequeno.

## 7. Casar jogos e emissões

1. **Normalizar os nomes das equipas:**
   - tirar acentos (`semAcentos`), passar a minúsculas e tirar pontuação;
   - tirar sufixos (FC, SC, CF, CD, SAD, «Futebol SAD») e abreviaturas («Brighton & Hove A.» → «brighton»);
   - usar um **dicionário de nomes alternativos**:
     - clubes portugueses: Sporting CP / Sporting; FC Porto / Porto; SL Benfica / Benfica;
       Vitória de Guimarães / Vitória SC;
     - clubes estrangeiros: Bayern München / Bayern Munique; Man United / Manchester United; Nottm Forest;
     - seleções: nomes em português e em inglês (como o `countryToPt` do bet-intel).
2. **Ler o título da emissão** com o padrão `[Modalidade[ Fem.]: ]A x B[ - Competição][ (Direto)]`. Na Sport TV,
   `descricao` dá «A X B», e `evento.nome` e `modalidade` dão o resto.
3. **Regras do casamento:**
   - **as duas equipas** correspondem (por igualdade dos nomes normalizados, ou por semelhança de tokens ≥ 0,8 com
     o resto do nome compatível);
   - **o início da emissão** fica entre 30 min antes e 15 min depois do início do jogo;
   - **o mesmo género:** «Fem.» só casa com jogos femininos;
   - **«B», «Sub-23» e «Sub-19»** não casam com a equipa principal;
   - ficam de fora as emissões «Antevisão», «Resumo», «Highlights», «Magazine», as repetições (`tipoEmissao` ≠
     DIRETO na Sport TV) e as que começam horas depois do jogo (as repetições da DAZN);
   - ignoram-se os títulos de enchimento: o nome do próprio canal, «Fora de Horas» e «Sem Transmissão».
4. **Confiança:**
   - **Confirmado:** o guia do FotMob liga o jogo (pelo id) ao canal, ou a Sport TV marca DIRETO com as duas
     equipas.
   - **Provável:** um título da MEO com as duas equipas, à hora certa.
   - **Possível:**
     - só a competição e a hora batem certo (por exemplo, «Ténis: ATP Finals (Direto)» cobre os jogos desse
       torneio nessa janela);
     - ou o jogo só aparece no EPG de uma lista.
   - No ecrã, Provável e Possível levam uma marca discreta.
5. **Ténis:** um jogo casa com o canal se o torneio do título for o mesmo e a emissão cobrir a hora prevista. Os
   encontros do mesmo torneio partilham o canal, com a nota «Transmissão do torneio». A hora dos encontros a seguir
   a outros é aproximada.

## 8. Índice de canais das listas («Onde ver»)

- Lê-se a cache de canais de cada lista (`Biblioteca.canaisEmCache`, num isolate para listas de 100 mil canais).
  Guarda-se um **índice pequeno** por lista: canal canónico → `[(id do canal, nome, qualidade)]`. Só se refaz
  quando muda a data da cache (`dataCache`), como o `Resumidor` do Início.
- **Reconhecer o canal pelo nome:**
  - tirar prefixos de país (`|PT|`, `PT:`, `[PT]`, `PT -`);
  - tirar a qualidade (4K, UHD, FHD, HD, SD, HEVC, H265, 50FPS, ᴴᴰ, ⁴ᴷ), «(backup)», «VIP» e «Alt»;
  - comparar com os nomes alternativos do §5.
- **Evitar falsos positivos:**
  - «SPORTV» (Brasil) não é «SPORT TV»;
  - a DAZN existe em Espanha, na Alemanha e em Itália, por isso um «DAZN 1» só conta como português com `PT` no
    nome ou no grupo, ou sem outro país à vista;
  - «ELEVEN» sem país é tratado como antigo nome da DAZN em Portugal, com confiança mais baixa.
- **Listas sem cache:** não se descarregam sozinhas (os portais Stalker são pesados e podem bloquear). O «Onde ver»
  diz «N listas ainda sem canais» e tem «Atualizar canais», que usa o código do Início (`_atualizarCanais`).
- **Associação manual:** no «Onde ver», «Este não é o canal» ou «Associar outro canal» guarda a correção, por
  lista e por canal canónico.

**Ordem das fontes no «Onde ver»:**
1. **Funcionou da última vez:** a app guarda a última fonte que tocou cada canal canónico, com a data.
2. Listas que **funcionam** (estado da última verificação), pela data da verificação mais recente.
3. A **qualidade preferida** (Definições: 4K, FHD ou HD).
4. Inconclusivas e por verificar.
5. As que **não funcionam**, no fim e esbatidas.

## 9. Player: fontes de várias listas e troca automática

- Hoje o player toca canais de **uma** lista: `PlayerCanais(canais, resolver)`, onde o `resolver` usa a conta dessa
  lista. No Windows, `JanelaPlayer.mostrar(lista, canais, i)` resolve os links no processo principal, com
  `_lista.conta`.
- **Mudança:** um tipo `FonteCanal(lista, canal)`.
  - O `resolver` usa a conta da lista **de cada fonte**.
  - No Windows, a `JanelaPlayer` guarda a lista de cada índice, e a mensagem `abrir` leva o nome da lista por canal
    para o painel do player.
  - O tempo visto (`contadorDeTempo`) e o `registarVisto` passam a seguir a lista da fonte que está a tocar.
- **Troca automática** (modo «Jogo»):
  - se a fonte falhar a abrir (erro do protocolo ou do motor) ou não der imagem no tempo do `VigiaAbertura`, o player
    passa sozinho à seguinte, com a mensagem «Sport TV 1 não respondeu na lista X; a tentar a lista Y…»;
  - para quando todas falharem, com «Nenhuma das N fontes funcionou»;
  - ↑/↓ no player passam a «trocar de fonte»;
  - um êxito fica guardado em «funcionou da última vez».
- **«Outras fontes» (fase 3):** um botão no player, durante o jogo, que mostra as outras fontes do mesmo canal sem
  sair.

## 10. Ecrã «Jogos»

- **Onde fica:** uma secção nova na barra lateral, entre «Ver TV» e «Gestor» (`Seccao.jogos`). No telemóvel é um
  separador da barra de baixo.
- **Em cima, uma só fila de filtros** que desliza:
  - **Dia:** Hoje, Amanhã, Sáb 29…, até 7 dias;
  - **Desporto:** Todos, Futebol, Ténis, Basquetebol;
  - **Competição:** as seguidas do desporto escolhido;
  - interruptores **«Só em direto»** e **«Só com canal»**.
- **Lista** agrupada por hora, ou por competição (à escolha). Cada linha mostra:
  - a hora, ou «● AO VIVO 67'» com o resultado;
  - os emblemas e as equipas, ou os jogadores;
  - a competição e a jornada;
  - as **etiquetas dos canais**;
  - **«▶ Ver»**.
  
  As equipas favoritas aparecem primeiro.
- **Coluna à direita (TV e computador):** com o foco num jogo, mostra o detalhe (estado, estádio, ronda) e o
  **«Onde ver»** já preenchido. No telemóvel, tocar no jogo abre o detalhe.
- **Etiqueta de um canal:** abre o «Onde ver» desse canal, ou seja, as fontes de todas as listas pela ordem do §8.
  Cada fonte mostra:
  - a lista e a pílula do estado;
  - o nome do canal como aparece nessa lista, com a qualidade;
  - «Funcionou da última vez», quando é o caso.
- **«▶ Ver»:** junta as fontes de todos os canais do jogo e abre o player em modo «Jogo», com troca automática.
- **Estados vazios:**
  - «Nenhum jogo das tuas competições neste dia»;
  - «Ainda sem canal anunciado»;
  - «Nenhuma das tuas listas tem este canal» (com «Atualizar canais»);
  - «Sem rede: a mostrar os dados de há 2 h».
- **D-pad:** as mesmas regras do Ver TV. Os filtros são uma fila, a lista é uma coluna, e cada linha é uma só
  paragem do foco. As etiquetas dos canais escolhem-se com ←/→ dentro da linha, OK abre o «Onde ver» e OK mantido
  faz «Ver».
- **Definições › Jogos:**
  - os desportos e as competições a seguir (por omissão, as do §2);
  - as equipas favoritas;
  - a qualidade preferida;
  - mostrar ou não os jogos sem canal;
  - as associações manuais de canais.

## 11. Riscos e mitigação

| Risco | Mitigação |
|---|---|
| As fontes mudam de formato ou endereço (todas são não documentadas) | Adaptadores isolados, testes com respostas gravadas, e cada fonte pode falhar sem derrubar as outras (os jogos continuam e o canal vem de outra grelha); «Estado das fontes» nas Definições › Sobre |
| Bloqueio por excesso de pedidos | Volume baixo, cache, `RitmoHost`, sem atualização em segundo plano em dados móveis |
| Casamento errado de equipas ou canais | Regras do §7 e §8, níveis de confiança à vista, associação manual, testes com títulos reais |
| Fuso horário da MEO no horário de verão | Converter de hora de Lisboa para UTC com a regra portuguesa (último domingo de março e de outubro); teste com datas de verão; confirmar em março |
| Listas sem cache de canais | Aviso e «Atualizar canais»; sem descarregar sozinho |
| Termos de uso das fontes e distribuição | Uso pessoal; na **edição de partilha** a funcionalidade fica desligada na 1.ª versão (decisão abaixo) e os anfitriões entram em `PROIBIDOS_PARTILHA` |
| Desempenho com listas enormes | Índice num isolate, refeito só quando a cache muda |

## 12. O que não ficou verificado

- A resposta de `liveTvChannels` do FotMob e se o guia de TV vai além de 7 dias.
- O fuso das horas da MEO no verão, o limite de dias para a frente (vi até 6) e se há limite de pedidos.
- O nível dos torneios no formato da ESPN, para excluir WTA 125 e Challengers.
- A estrutura HTML da FPB (paginação e filtros pelo endereço).
- Os ids «a confirmar» do §4.
- O tamanho exato da página da Sport TV em cada pedido (o JSON tinha ~0,94 MB).

Cada um destes pontos é o primeiro passo da tarefa que usa essa fonte (ver o plano).

## 13. Decisões

**Tomadas por mim (podes mudar):**
- FotMob para o futebol (não a ESPN), por cobrir todas as competições pedidas e já trazer os canais portugueses.
- A MEO como grelha principal de todos os canais, a Sport TV como confirmação e o EPG das listas como último recurso.
- Sem servidor: a app fala com as fontes, com cache em disco.
- Sem descarregar sozinha as listas que ainda não têm canais.

**Decididas por ti (27/11/2026):**
1. **Edição de partilha:** «Jogos» desligado (o código nem entra nessa edição).
2. **Resultados ao vivo:** a cada 60 s, só com o ecrã «Jogos» aberto (fase 3).
3. **Taça Davis e BJK Cup:** incluídas, mas desligadas por omissão nas Definições (fase 2).

## 14. Fases

1. **Fundação e futebol:**
   - catálogo, nomes e cache;
   - jogos e guia de TV do FotMob; grelha da MEO;
   - casador, índice de canais e «Onde ver»;
   - player com várias fontes e troca automática;
   - ecrã «Jogos» e Definições.
2. **Ténis e basquetebol:** ESPN (ATP, WTA e NBA), grelha da Sport TV e FPB (LPB).
3. **Extras:**
   - resultados ao vivo;
   - a fila «Hoje há jogo» no Início;
   - equipas favoritas em destaque;
   - «Outras fontes» no player;
   - logótipos dos canais (MEO).

O detalhe de cada tarefa está em `docs/2026-11-27-jogos-plano.md`.

Fontes externas consultadas: [FotMob, guia de TV de Portugal](https://www.fotmob.com/pt-PT/tv-guide/pt) ·
[Sport TV, guia](https://www.sporttv.pt/guia) · [MEO, guia TV](https://www.meo.pt/tv/canais-programacao/guia-tv) ·
[FPB, calendário](https://www.fpb.pt/calendario/) ·
[DAZN e a LPB (Advanced Television)](https://www.advanced-television.com/?p=293216) ·
[ATP, transmissões por país](https://www.atptour.com/en/tournaments/tv-schedule) · estudo do bet-intel
(`bet-intel/ESTUDO_FONTES_DADOS.md`).
