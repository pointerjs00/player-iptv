# Recuar no direto com gravação no armazenamento — plano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recuar, pausar e voltar ao direto nos dois motores, gravando o direto em blocos no armazenamento interno, com limite garantido e limpeza ao sair do canal.

**Architecture:** `GravadorDireto` (lib/direto/) grava o stream em blocos rotativos com índice de tempo; `ServidorDireto` serve esses bytes em `127.0.0.1`; o ecrã do player abre o motor no URL local e traduz saltos em reaberturas com `desde=`.

**Tech Stack:** Dart (dart:io HttpClient/HttpServer, isolates se preciso), Flutter, Kotlin (StatFs), FFI (Windows), Media3 1.5.1.

**Spec:** docs/2026-11-20-gravacao-direto-design.md

## Global Constraints

- Limite em disco = `reserva` (1/2/3 GB, omissão 2 GB), em blocos de 16 MiB; nunca mais de `reserva ÷ 16 MiB` blocos, contando o bloco em escrita.
- Margem do sistema: 1 GB livre; reserva mínima 256 MiB.
- Pasta: `<cache da app>/direto/<sessão>`; apagada ao mudar de canal, ao sair do player e (toda a `direto/`) no arranque.
- Servidor local só em `127.0.0.1`, com código aleatório de 128 bits no caminho.
- Nunca registar nem mostrar URLs, cabeçalhos, tokens, MACs ou o código do servidor local.
- Texto pt-PT; cores de `Tokens`; mensagens com `mostrarMensagem`.
- Testes sem tempo de parede (relógio injetável); `flutter analyze` sem avisos, `flutter test` verde.

## Review Focus

1. Escrever muito mais do que a reserva (ex.: reserva de 4 blocos de 64 KiB nos testes, 50 blocos escritos): a pasta nunca passa do limite em nenhum momento. — Task 1.
2. Leitor do servidor atrasado quando o bloco que lê é apagado: salta para o bloco mais antigo sem rebentar nem bloquear o gravador. — Task 2.
3. Zapping rápido: cada canal anterior é parado e a sua pasta apagada; nunca há dois gravadores do mesmo player. — Task 3.
4. Falha da origem a meio: o gravador volta a ligar e continua; desiste com a regra do `ContinuarDireto`. — Task 1/3.
5. Espaço livre a descer abaixo de 1 GB durante a gravação: blocos antigos apagados; se não chegar, deixa de gravar em disco com mensagem. — Task 4.

---

### Task 1: `GravadorDireto` — blocos rotativos, índice e religar

**Files:** Create `lib/direto/gravador.dart`; Test `test/direto/gravador_test.dart`.

**Interfaces:**
- Produces: `GravadorDireto({required Uri origem, required Map<String,String> cabecalhos, required Directory pasta, required int reservaBytes, int tamanhoBloco = 16 << 20, DateTime Function()? agora, Future<Stream<List<int>>> Function(Uri, Map<String,String>)? abrir})`; `Future<void> iniciar()`; `Future<void> parar({bool apagar = true})`; `int get inicio` / `int get fim` (posições absolutas em bytes disponíveis); `int posicaoHa(Duration recuo)` (posição alinhada a 188 de há `recuo`, limitada ao início); `Duration get janela` (tempo gravado disponível); `Duration recuoDe(int posicao)` (o inverso, para a barra); `Stream<int> get crescimento` (novo `fim`); `Stream<ErroGravador> get erros`; `Future<List<int>?> ler(int desde, int max)` (null se `desde` já foi apagado).
- `ErroGravador { bool desistiu; String mensagem }` (sem URL).

- [ ] Testes que falham: blocos de 64 KiB e reserva de 256 KiB (4 blocos): escrever 3,2 MiB vindos de uma origem falsa → em cada escrita a soma dos tamanhos na pasta ≤ 256 KiB (verificar a cada bloco) e `inicio` avança; índice: com relógio falso a avançar 1 s por 64 KiB, `posicaoHa(2 s)` = `fim − 128 KiB` alinhado a 188; origem que fecha a meio → volta a ligar e continua com `fim` contínuo; 3 falhas sem proveito → `erros` com `desistiu: true`; `parar()` apaga a pasta.
- [ ] Correr → FALHAM. Implementar. PASSAM; analyze.
- [ ] Commit `feat(direto): gravador em blocos rotativos com limite, índice de tempo e religar`

### Task 2: `ServidorDireto` — servir o gravado em 127.0.0.1

**Files:** Create `lib/direto/servidor.dart`; Test `test/direto/servidor_test.dart`.

**Interfaces:**
- Consumes: `GravadorDireto` (Task 1).
- Produces: `ServidorDireto.iniciar(GravadorDireto g) -> Future<ServidorDireto>`; `Uri urlDesde(int posicao)` / `Uri get urlDireto` (fim menos ~2 s); `Future<void> fechar()`. Caminho `/<código>/direto?desde=N`; código errado → 404; responde `Content-Type: video/mp2t`, sem `Content-Length`, envia e fica à espera de `crescimento`.
- [ ] Testes que falham: GET com `desde` envia os bytes certos e continua a enviar os que chegam; código errado → 404; leitor atrasado com o bloco apagado → continua do `inicio`; fechar o servidor termina as respostas abertas; só escuta em loopback.
- [ ] Correr → FALHAM. Implementar. PASSAM; analyze.
- [ ] Commit `feat(direto): servidor local do direto gravado`

### Task 3: Ligar ao player — recuar, avançar, pausa e voltar ao direto

**Files:** Modify `lib/ui/player/player_canais.dart` (e saltos/barra de progresso/`ContinuarDireto` conforme preciso), `lib/ui/player/motor_exo.dart`/`motor_mpv.dart` só se preciso; Create `lib/direto/sessao_direto.dart`; Tests.

**Interfaces:**
- Produces: `SessaoDireto` (um gravador + um servidor por canal; `abrir(canal)`, `fechar()` que pára, apaga e fecha), injetável no `PlayerCanais`.
- Regras: só canais em direto progressivos (não `.m3u8`, não VOD) e só com «Recuar no direto» = Armazenamento; o motor abre `urlDireto`; recuar/avançar N s → reabrir em `urlDesde(posicaoHa(...))`; «Voltar ao direto» → `urlDireto`; pausa → motor pausa, gravador continua; barra de progresso = janela gravada e posição; erros do gravador com `desistiu` → cartão de erro (a regra existente); ao mudar de canal / sair / erro final → `fechar()` antes de abrir o seguinte.
- HLS/VOD: saltos nativos no `MotorExo` (`seekTo` relativo, janela do HLS); mpv como hoje.
- [ ] Testes que falham (motor e gravador falsos): recuar 30 s reabre o motor no URL com o `desde` do índice; voltar ao direto abre o `urlDireto`; pausa não pára o gravador; zapping de 5 canais deixa 1 sessão aberta e as pastas dos outros apagadas; HLS não cria sessão e recuar chama `seekTo` no ExoPlayer; o URL de origem nunca aparece em erros.
- [ ] Correr → FALHAM. Implementar. PASSAM; suite + analyze; `flutter build apk` compila.
- [ ] Commit `feat(player): recuar, pausar e voltar ao direto com o direto gravado`

### Task 4: Espaço, limpeza no arranque e Definições

**Files:** Modify `lib/dados/preferencias.dart`, `lib/main.dart`, `lib/ui/definicoes/tela_definicoes.dart`, `android/.../MainActivity.kt` (`espacoLivre` no canal `player_iptv/ficheiros`), Create `lib/direto/espaco.dart` (Android por canal, Windows por FFI `GetDiskFreeSpaceExW`, outros: null); ExoPlayer: back buffer 128 MiB para o modo Memória (`ReprodutorExo.kt`, `android:largeHeap="true"`); Tests.

**Interfaces:**
- Produces: `enum RecuoDireto { armazenamento, memoria, desligado }`; `Preferencias.recuoDireto` (omissão `armazenamento`), `Preferencias.reservaDiretoGb` (1/2/3, omissão 2); `Future<int?> espacoLivre(Directory)`.
- [ ] Testes que falham: arranque apaga `direto/` inteira; reserva ajustada quando o espaço livre < reserva + 1 GB (mínimo 256 MiB) com mensagem; abaixo de 1 GB livre a meio → apaga blocos antigos; sem espaço nem para 256 MiB → modo memória com mensagem; Definições mostram «Recuar no direto» e «Espaço reservado» (só com Armazenamento) em linhas; o modo Memória passa o back buffer ao ExoPlayer.
- [ ] Correr → FALHAM. Implementar. PASSAM; suite + analyze; `flutter build apk` e `flutter build windows` compilam.
- [ ] Commit `feat(direto): espaço reservado, limpeza no arranque e definições do recuo`
