# Player IPTV — design

Data: 2026-11-16 · Estado: aprovado na conversa; as decisões marcadas *(proposta)* são minhas e podem ser corrigidas.

## 1. Porquê

Hoje há o **Verificador IPTV** (`tv-management`): diz que listas funcionam e exporta-as para o sfvip player
(Windows) ou o Stalker Portal Player. Ver os canais obriga a passar para outra app, que não mostra o
resultado da verificação nem corre bem em todos os aparelhos.

O Player IPTV junta as duas coisas: **guarda todas as listas, mostra se funcionam, abre-as e toca os
canais** — no Windows, no telemóvel Android e na TV (Android TV / Fire TV, só com o comando).

## 2. Objetivos

1. **Início = as minhas listas.** Um cartão por lista importada (Accounts.json, .ini, M3U, Xtream,
   linhas "portal MAC"...), com o resultado da **última verificação** (Funciona / Não funciona / INC,
   data, validade) e um botão **"Verificar de novo"**.
2. **Tocar num cartão abre o conteúdo da lista** — não um canal: os **grupos** (categorias) e os
   **canais de cada grupo**, com **pesquisa e filtro** rápidos por grupo e por canal.
3. **Escolher um canal abre o player:**
   - **Windows:** numa **janela separada** da app; a janela principal continua com as listas, o
     conteúdo ou o separador de verificação. Escolher outro canal troca o canal nessa janela.
   - **Android (telemóvel e TV):** **ecrã inteiro**, logo. Sem janela flutuante nem picture-in-picture.
     Voltar (botão/gesto/comando) regressa ao conteúdo da lista.
4. **Separador "Verificar"** com a interface do verificador: importar várias fontes, escolher os
   canais de teste (RTP 1 / SportTV 1 / DAZN 1, um ou mais), analisar, selecionar e exportar
   (Accounts.json ou .ini) — as mesmas regras do verificador atual.
5. **Uma só base de código** para Windows, Android e Android TV.

## 3. Não-objetivos (v1)

- Programação (EPG/XMLTV), gravações, timeshift/catch-up.
- Filmes e séries (VOD) de Xtream/Stalker — v1 é só TV em direto. *(proposta)*
- Sincronização entre aparelhos, contas de utilizador, controlo parental.
- iOS, macOS, Linux.

## 4. Anti-objetivos

- Enviar credenciais (MAC, utilizador, password, links) para qualquer sítio que não seja o próprio
  portal/servidor da lista. Sem telemetria, sem servidores nossos.
- Uma app de TV que exija toque ou rato: tudo tem de se usar com as setas, OK e Voltar.
- Trazer listas dentro da app distribuída (o .apk/.zip nunca leva contas).

## 5. Formatos de entrada

| Formato | Origem | Notas |
|---|---|---|
| Accounts.json (sfvip) | ficheiro | os campos `Name, Address, Mac, Username, Password...` — mesmo modelo do verificador |
| .ini (Stalker Portal Player) | ficheiro(s) / pasta | `[DNS] Address=…, Mac=…`; o nome do ficheiro é o nome da lista |
| M3U / M3U8 | ficheiro ou URL | `#EXTINF` com `group-title`, `tvg-logo`, `tvg-name`; `#EXTVLCOPT` (user-agent, referer) |
| Xtream | URL `get.php?username=&password=` ou servidor + utilizador + password | usa a `player_api.php` |
| Stalker | linha "portal MAC" | handshake, perfil, géneros, canais, `create_link` |
| .txt misto | ficheiro / colar | uma conta por linha (as mesmas linhas que o verificador aceita) |
| Histórico do verificador | `historico.json` | importa listas **e** os resultados já obtidos *(proposta)* |

Listas repetidas juntam-se pela **mesma chave do verificador** (`motor/conta.py: chave`): sem `/c/`,
sem porta por omissão, MAC em maiúsculas. O nome mostrado segue `nome_lista`: `NNNHOST DDMMAA`.

## 6. Ecrãs

```
Windows (janela principal)                       Windows (janela do player)
┌──────────────────────────────────────────┐    ┌───────────────────────────┐
│ [Listas] [Verificar]          ⌕ pesquisar │    │                           │
│ ┌────────────┐ ┌────────────┐ ┌─────────┐ │    │      vídeo do canal       │
│ │001NXTBOX   │ │INC 002ABC  │ │003XYZ   │ │    │                           │
│ │● Funciona  │ │▲ INC       │ │✗ Não fun│ │    │ PT: RTP 1 HD · 001NXTBOX  │
│ │até 16/10/27│ │sem data    │ │há 2 dias│ │    └───────────────────────────┘
│ │[Verificar] │ │[Verificar] │ │[Verif.] │ │
│ └────────────┘ └────────────┘ └─────────┘ │
└──────────────────────────────────────────┘

Conteúdo da lista (todas as plataformas)
┌──────────────────────────────────────────────┐
│ ← 001NXTBOX            ⌕ canal ou grupo…      │
│ GRUPOS (filtrar…)   │ PORTUGAL · 48 canais    │
│ ★ Favoritos         │ ▸ PT: RTP 1 HD      ☆   │
│ ▸ Portugal      48  │ ▸ PT: RTP 2 HD      ☆   │
│   Desporto      31  │ ▸ PT: SIC HD        ☆   │
│   UK            120 │ ...                     │
└──────────────────────────────────────────────┘
```

- **Início:** grelha de cartões (lista na TV estreita), ordenar/filtrar por estado como no verificador;
  "Adicionar listas" (ficheiros, pasta, colar, URL); "Verificar todas".
- **Conteúdo:** duas colunas (grupos | canais); no telemóvel, grupos em cima como chips e canais por
  baixo. A pesquisa procura nos **nomes dos canais de todos os grupos** e o filtro de grupos estreita a
  coluna da esquerda. Pesquisa sem acentos/maiúsculas ("rtp" encontra "RTP 1"). Favoritos por lista.
  A lista de canais é carregada do portal ao abrir e guardada em cache (com "Atualizar").
- **Player (Android):** ecrã inteiro; overlay curto com o nome do canal e o grupo; **cima/baixo** troca
  para o canal anterior/seguinte do grupo; **OK** mostra o overlay; **Voltar** sai.
- **Player (Windows):** janela própria (redimensionável, ecrã inteiro com duplo clique/F11), mesmas
  teclas; fechar a janela pára o canal.
- **Verificar:** paridade com `tv-management/interface.html` (fontes, canais, análise ao vivo com
  cartões, reteste, seleção, exportar JSON/.ini).

## 7. Abordagens consideradas

| | Abordagem | Prós | Contras |
|---|---|---|---|
| **A (escolhida)** | **Flutter** + **media_kit** (libmpv); motor reescrito em Dart | um código para Windows/Android/TV; o mpv toca TS/HLS e aceita headers por canal; o mesmo código lista canais e verifica | reescrever o motor Python (~2 000 linhas, com testes de referência) |
| B | Kotlin + Media3/ExoPlayer no Android e outra app no Windows | o melhor leitor em Android TV | duas apps para manter |
| C | Manter o Python no Windows (pywebview + mpv) e fazer só o Android de raiz | reaproveita tudo no Windows | duas apps diferentes; o Android ficava sem verificação |

Escolhida a **A**: é a única com um só código e verificação em todas as plataformas.

## 8. Arquitetura

```
lib/
  modelo/      conta.dart (Conta, Tipo, chave, nomeLista), lista.dart, canal.dart, resultado.dart
  importar/    accounts_json.dart, ini.dart, m3u.dart, linhas.dart, historico_verificador.dart
  rede/        http.dart (timeouts, cancelamento, ritmo por host, 429), dns.dart
  protocolos/  stalker.dart, xtream.dart, m3u_remoto.dart — cada um: abrir(conta) -> ConteudoLista
               (grupos + canais) e urlDoCanal(canal) -> FonteVideo (url + headers)
  verificar/   canais_teste.dart (perfis RTP1/SportTV1/DAZN1), verificador.dart (3 estados,
               2.ª volta, reteste, validade), exportar.dart (Accounts.json, zip .ini)
  dados/       biblioteca.dart (listas + últimos resultados + favoritos + cache de canais), em JSON
               na pasta de dados da app, escrita atómica
  ui/          inicio/, conteudo/, player/, verificar/, comum/ (cartões, foco/D-pad, tema)
  janelas/     player_windows.dart (janela separada no Windows)
```

- **Referência de comportamento:** `tv-management/motor/*.py` e `tests/*.py`. Os casos de teste Python
  passam para Dart (mesmos nomes onde fizer sentido). Onde o Dart divergir do Python, o Python ganha.
- **Player:** `media_kit` + `media_kit_video`; cada `FonteVideo` leva URL e headers (User-Agent,
  Referer, Cookie `mac=…` e `Authorization: Bearer` no Stalker).
- **Janela do player no Windows:** pacote `desktop_multi_window` — a janela principal cria (ou
  reutiliza) a janela do player e envia-lhe `{fonte, nome, grupo}` por mensagem. *(proposta; se o
  media_kit não funcionar na 2.ª janela, a alternativa é lançar o mesmo .exe com `--player` e falar
  por um socket local 127.0.0.1)*
- **TV:** `Shortcuts`/`Actions` + `FocusTraversalGroup`; foco sempre visível; `android:banner` e
  categoria `LEANBACK_LAUNCHER` para aparecer no ecrã inicial da TV; `minSdk` 21+ (cobre o Fire TV).
- **Dados:** JSON simples (poucas centenas de listas); cache de canais por lista num ficheiro à parte.

## 9. Restrições

- Windows 10/11 x64; Android 7+ (telemóvel, Android TV, Fire TV Stick 4K Max).
- Sem servidores próprios; só pedidos aos portais das listas.
- Credenciais só em armazenamento local da app.
- Texto da interface em português de Portugal.

## 10. Deixado a quem constrói

Escolha de gestão de estado (Riverpod ou ValueNotifier simples), estrutura exata dos widgets, cores
(seguir o tema escuro do verificador), formatos de cache, mensagens de erro.
