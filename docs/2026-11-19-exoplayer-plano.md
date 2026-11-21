# Motor ExoPlayer no Android — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** No Android, reproduzir os canais com ExoPlayer numa Surface real (como a IPTV Extreme), com o mpv como recurso e no Windows.

**Architecture:** Interface `MotorReproducao` no Dart com `MotorMpv` (media_kit, o atual) e `MotorExo` (canal de plataforma para um `ReprodutorExo` em Kotlin com Media3 e um `SurfaceView` por baixo da `FlutterView` transparente). O ecrã do player escolhe o motor pelas Definições e troca para o mpv se o ExoPlayer não suportar o canal.

**Tech Stack:** Flutter 3.50 / Dart 3.14, media_kit vendorizado (mpv), Kotlin, androidx.media3 1.5.1.

**Spec:** docs/2026-11-19-exoplayer-design.md

## Global Constraints

- Media3 só `androidx.media3:media3-exoplayer:1.5.1` e `androidx.media3:media3-exoplayer-hls:1.5.1` (download aprovado); nenhuma outra dependência nova.
- Nunca registar nem mostrar URLs completos, cabeçalhos, tokens, cookies, MACs ou credenciais (nem em logs do Kotlin, nem em erros mostrados).
- Cores só de `Tokens`; texto pt-PT; mensagens com `mostrarMensagem`.
- O caminho do vídeo do ExoPlayer nunca passa por textura do Flutter.
- Windows e o motor mpv continuam a funcionar como hoje (salvo as melhorias da Task 5).
- `flutter analyze` sem avisos novos, `flutter test` verde; as tasks com Kotlin também `flutter build apk --release --split-per-abi` a compilar.

## Review Focus

1. Zapping rápido (10 canais em 5 s) no ExoPlayer: um só reprodutor nativo, nenhum vazamento de Surface/MediaCodec, o último canal pedido é o que fica. — Task 3.
2. Sair do player com o ExoPlayer: a `FlutterView` volta a opaca, a Surface é largada e a taxa do ecrã é reposta. — Tasks 2/3.
3. Erro de formato a meio do zapping: o recurso ao mpv não fica preso nem abre dois motores. — Task 4.
4. Pausa/retoma da app (Home no comando) com vídeo ExoPlayer: retoma sem ecrã preto. — Task 2.
5. Cabeçalhos do Stalker (cookies/token) chegam ao ExoPlayer e nunca aparecem em logs. — Task 2.

---

### Task 1: `MotorReproducao` e o motor mpv atrás dele (sem mudar comportamento)

**Files:** Create `lib/ui/player/motor_reproducao.dart`, `lib/ui/player/motor_mpv.dart`; Modify `lib/ui/player/player_canais.dart` (e quem usar `Player`/`MotorMpv` do player); Tests: os existentes do player continuam verdes + `test/ui/motor_reproducao_test.dart`.

**Interfaces:**
- Produces: `abstract interface class MotorReproducao` com `Stream<String> erros`, `Stream<bool> aCarregar`, `Stream<double> percentagemCarga`, `Stream<Size?> tamanhoVideo`, `Stream<Duration> posicao`, `Stream<void> fim`, `Stream<FaixasMotor> faixas`, `Stream<FaixaAtual> faixaAtual`; `Future<void> abrir(String url, Map<String,String> cabecalhos, {Duration? inicio})`, `play()`, `pausar()`, `parar()`, `escolherAudio(FaixaMotor)`, `escolherLegenda(FaixaMotor?)`, `velocidade(double)`, `volume(double)`, `Future<EstatisticasMotor> estatisticas()`, `Widget video({required BoxFit ajuste, double? proporcao})`, `Future<void> descartar()`, `String get nome` (`'mpv'`/`'exoplayer'`), `bool get suportaDesentrelacamento`.
- Produces: `MotorMpv` (a implementação com o `Player` do media_kit e o `MotorForaDaUi` que já existem; o desentrelaçamento/Compatível continuam a usar o motor mpv por um getter específico).
- Os nomes acima são a fronteira; tipos auxiliares (`FaixaMotor`, `FaixasMotor`, `FaixaAtual`, `EstatisticasMotor`) definidos neste ficheiro.

- [ ] Teste que falha: `motor_reproducao_test` com um `MotorFalso` mostra que o ecrã do player (`PlayerCanais`) abre um canal pelo motor injetado e reage a `erros`, `aCarregar` e `faixas` (injeção por parâmetro/fábrica, sem rede).
- [ ] Correr → FALHA. Refatorar `player_canais.dart` para usar só `MotorReproducao` (o mpv atrás de `MotorMpv`). Os testes existentes do player continuam verdes sem os enfraquecer.
- [ ] suite + analyze. Commit `refactor(player): o ecrã do player fala com um MotorReproducao (mpv por trás)`

### Task 2: Reprodutor ExoPlayer nativo (Kotlin) com SurfaceView

**Files:** Modify `android/app/build.gradle(.kts)` (Media3 1.5.1), `android/app/src/main/kotlin/.../MainActivity.kt`; Create `android/app/src/main/kotlin/.../ReprodutorExo.kt`; Test: `flutter build apk --release --split-per-abi` compila; teste Dart do protocolo na Task 3.

**Interfaces (canal `player_iptv/exo`, MethodChannel + EventChannel `player_iptv/exo/eventos`):**
- Métodos: `criar({tunel: bool}) -> id`, `abrir({id, url, cabecalhos, inicioMs?})`, `play`, `pausar`, `parar`, `descartar`, `audio({id, grupo, faixa})`, `legenda({id, grupo?, faixa?})`, `volume({id, v})`, `ajuste({id, modo: 'ajustar'|'preencher'|'esticar', proporcao?})`, `estatisticas({id}) -> map`, `mostrar({id, visivel: bool})`.
- Eventos (mapa com `id` e `tipo`): `aCarregar{valor}`, `pronto`, `tamanho{largura, altura, proporcaoPixel}`, `posicao{ms}` (≤ 4/s), `faixas{audio:[{grupo,faixa,lingua,rotulo}], legendas:[…]}`, `faixaAtual{audio, legenda}`, `erro{codigo, mensagem, formato: bool}` (`formato` = erro de descodificador/formato não suportado), `fim`.
- Surface: um `SurfaceView` acrescentado por baixo da `FlutterView` na Activity; com `mostrar(visivel:true)` a `FlutterView` fica transparente (`TransparencyMode`/fundo transparente) e o `SurfaceView` visível; `false` repõe. `setVideoChangeFrameRateStrategy(VIDEO_CHANGE_FRAME_RATE_STRATEGY_ONLY_IF_SEAMLESS)` por omissão; o modo de ecrã continua a ser pedido pelo canal `player_iptv/ecra`.
- `DefaultHttpDataSource` com os cabeçalhos e o User-Agent do pedido; HLS por extensão/MIME, o resto progressivo; `LoadControl` para direto (buffer mínimo pequeno para abrir depressa, ex.: 1,5 s para começar).
- Logs: nunca o URL nem os cabeçalhos (só o host mascarado, se preciso).

- [ ] Implementar; `flutter build apk --release --split-per-abi` compila; `flutter analyze` e `flutter test` continuam verdes (repor ficheiros gerados).
- [ ] Commit `feat(android): reprodutor ExoPlayer (Media3) numa SurfaceView por baixo da interface`

### Task 3: `MotorExo` no Dart

**Files:** Create `lib/ui/player/motor_exo.dart`; Test `test/ui/motor_exo_test.dart`.

**Interfaces:** Consumes o protocolo da Task 2; Produces `MotorExo implements MotorReproducao` (`nome == 'exoplayer'`, `suportaDesentrelacamento == false`); `video()` devolve uma área transparente que chama `mostrar(visivel:true)` ao montar e `false` ao desmontar, e manda o `ajuste` quando muda.

- [ ] Testes que falham (canal falso com `TestDefaultBinaryMessenger`): abrir manda `abrir` com url e cabeçalhos; eventos viram os streams certos; zapping de 10 canais seguidos deixa um só `criar` e o último `abrir` ganha (os eventos de ids antigos são ignorados); `descartar` manda `descartar` e `mostrar(false)`; `estatisticas` mapeia `perdidas`, `renderizadas`, `fps`, `codec`, `resolucao`; os erros mostrados não contêm o URL.
- [ ] Correr → FALHAM. Implementar. PASSAM; suite + analyze.
- [ ] Commit `feat(player): MotorExo — o ExoPlayer do Android atrás do MotorReproducao`

### Task 4: Escolha do motor, recurso ao mpv e Definições

**Files:** Modify `lib/dados/preferencias.dart`, `lib/ui/player/player_canais.dart`, `lib/ui/definicoes/tela_definicoes.dart`, `lib/ui/player/painel_definicoes.dart` / estatísticas se mostram opções só do mpv; Tests.

**Interfaces:** `enum MotorAndroid { exoplayer, mpv }`; `Preferencias.motorAndroid` (omissão `exoplayer`), `Preferencias.modoTunel` (omissão `false`).

- [ ] Testes que falham: no Android com `exoplayer` o player cria um `MotorExo` (fábrica injetável); no Windows sempre `MotorMpv`; um erro com `formato: true` reabre o mesmo canal no mpv uma vez e mostra «Este canal abriu com o motor mpv»; um 2.º erro de formato no mesmo canal não volta a trocar; erro de rede não troca de motor; Definições (Android) mostram «Motor do player» (ExoPlayer / mpv) e «Modo túnel»; com ExoPlayer as opções de desentrelaçamento/Compatível/descodificação por hardware aparecem com «só no motor mpv» e desativadas.
- [ ] Correr → FALHAM. Implementar. PASSAM; suite + analyze; `flutter build apk` compila.
- [ ] Commit `feat(player): ExoPlayer por omissão no Android, com recurso ao mpv e modo túnel`

### Task 5: Melhorias rápidas no mpv e estatísticas

**Files:** Modify `lib/ui/player/configuracao_mpv.dart`, `lib/ui/player/desentrelacamento.dart`, `lib/ui/player/controlo_desentrelacamento.dart`, `lib/ui/player/estatisticas.dart`; Tests dos mesmos.

- [ ] Testes que falham: configuração do mpv inclui `cache-on-disk=no`; o Compatível desiste com mais de 0,5 imagens perdidas/s (antes 2); um canal visto progressivo fica memorizado na sessão (por id do canal) e ao reabrir não leva shader nem Compatível; as estatísticas mostram «Imagens desenhadas/s (interface)» e «Tempo de desenho» a partir de `SchedulerBinding.addTimingsCallback`.
- [ ] Correr → FALHAM. Implementar. PASSAM; suite + analyze.
- [ ] Commit `perf(mpv): sem cache em disco, Compatível mais exigente, progressivos memorizados e estatísticas do desenho`
