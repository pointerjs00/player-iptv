# Recuar no direto com gravação no armazenamento — design

## Porquê
Com o ExoPlayer não há recuo no direto (só o mpv tinha um buffer de 64 MiB em memória). O utilizador quer
recuar vários minutos e decidiu gravar no armazenamento interno do Fire TV Stick (12 GB, 6 GB livres),
**2 GB reservados por omissão**, com duas garantias pedidas explicitamente:
1. o espaço usado **nunca excede** o valor reservado;
2. **ao sair do canal, os dados são apagados** (não encher o armazenamento com dados inúteis).

## O que muda
- **Gravador do direto (Dart, para os dois motores e as duas plataformas):** para canais em direto
  progressivos (MPEG-TS/HTTP — não `.m3u8`), a app abre ela própria o stream com os mesmos cabeçalhos do
  canal e grava-o em **blocos de 16 MiB** numa pasta própria da app (`getApplicationCacheDirectory()/direto/
  <sessão>`). No máximo `reserva ÷ 16 MiB` blocos (2 GB → 128); cada bloco fecha ao chegar a 16 MiB; antes
  de abrir um bloco novo apaga-se o mais antigo. O total em disco nunca passa de `blocos × 16 MiB`,
  contando o bloco em escrita.
- **Índice de tempo:** a cada bloco (e a cada ~1 s dentro dele) regista-se `(instante de chegada, posição
  em bytes)`, alinhada a pacotes TS de 188 bytes, para traduzir «recuar 30 s» numa posição.
- **Servidor local:** um `HttpServer` em `127.0.0.1` (porta aleatória), com um **código aleatório no
  caminho** (outras apps do aparelho não conseguem ler). `GET /<código>/direto?desde=<posição>` envia os
  bytes a partir dessa posição e continua a enviar o que vai chegando (stream sem fim). Se a posição pedida
  já foi apagada, começa no bloco mais antigo.
- **No player:** o motor (ExoPlayer ou mpv) abre o URL local em vez do do servidor.
  - recuar/avançar → reabrir o motor no URL local com `desde=` a posição do índice;
  - «Voltar ao direto» → reabrir no fim;
  - pausa → pausa o motor; o gravador continua; ao retomar, continua a ler de onde estava (pausa real);
  - a barra de progresso mostra a janela gravada (do mais antigo ao direto) e a posição atual.
  - Uma falha da ligação ao servidor de origem é tratada pelo gravador (volta a ligar e continua no mesmo
    ficheiro), com a mesma regra de desistência do `ContinuarDireto`; o player só vê o fim se o gravador
    desistir.
- **HLS e filmes/séries:** não passam pelo gravador. Saltos nativos do motor (ExoPlayer `seekTo` na janela
  do HLS; mpv como hoje). Sem janela, recuo em memória (ExoPlayer: back buffer 128 MiB no Fire TV / Android
  TV com `largeHeap`; mpv: o seu 64 MiB).
- **Proteções do espaço:**
  - Antes de começar: espaço livre ≥ reserva + 1 GB de margem; senão a reserva baixa para o que couber
    (mínimo 256 MiB) e a app diz quanto; se nem isso, só memória, com mensagem.
  - Durante: se o espaço livre do aparelho cair abaixo de 1 GB, apagam-se blocos antigos até voltar a 1 GB
    (ou até restar 1 bloco); se não chegar, o gravador pára de gravar para disco e o canal continua sem recuo
    em disco (mensagem).
- **Limpeza:**
  - mudar de canal ou sair do player → a pasta da sessão é apagada logo;
  - no arranque da app, antes de tudo, apaga-se toda a pasta `direto/` (sobras de um fecho à força);
  - a pasta é de cache da app (o Android também a pode limpar e apaga-a ao desinstalar).
- **Definições › Imagem e som:** «Recuar no direto» — Armazenamento (omissão) / Memória / Desligado;
  «Espaço reservado» — 1 GB / 2 GB (omissão) / 3 GB (só com Armazenamento).

## Fora do âmbito
Gravar programas para ver depois; pen USB (pode vir depois: só muda a pasta); HLS pelo gravador.

## Abordagens
(A) Gravador + servidor local em Dart — funciona igual nos dois motores e no Windows, testável em Dart;
(B) cache do ExoPlayer (`SimpleCache`) — só ExoPlayer, sem controlo fino do limite nem do índice;
(C) `stream-record` do mpv — só mpv. Escolhida A.

## Decisões minhas
- Blocos de 16 MiB; índice a cada ~1 s; posições alinhadas a 188 bytes.
- Código aleatório de 128 bits no caminho do servidor local; servidor só em `127.0.0.1`.
- Espaço livre: Android por um método novo no canal `player_iptv/ficheiros` (`StatFs`); Windows por
  `GetDiskFreeSpaceExW` (FFI).
- Nunca registar URLs, cabeçalhos ou o código do servidor local.
