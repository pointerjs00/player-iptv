# Coser as religações do direto — plano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que um servidor que fecha a ligação a cada poucos segundos (e reenvia 10–30 s já enviados) se veja como um direto contínuo, sem «A carregar…».

**Architecture:** O `GravadorDireto` cose cada religação à anterior (só grava o que vem depois do último ponto já gravado); os canais Stalker passam sempre pelo gravador (em memória quando o recuo está desligado); o ExoPlayer lê a rajada inteira; sem gravador, o link seguinte é pedido cedo e a reabertura espera menos.

**Tech Stack:** Dart (lib/direto), Kotlin (ReprodutorExo), Flutter.

**Spec:** relatório `.superpowers/sdd/diag-buffer-jinbox.md` (medições: o servidor fecha a cada 1–22 s, mediana ~6 s; cada ligação recomeça 10–30 s antes do fim da anterior com bytes idênticos; links de uso único — HTTP 462 ao repetir; rajada inicial de 20–30 s de vídeo e depois tempo real) e docs/2026-11-20-gravacao-direto-design.md.

## Global Constraints

- As garantias do recuo mantêm-se: nunca exceder a reserva; apagar ao sair do canal.
- Uma só ligação à origem de cada vez; Stalker: link novo em cada religação.
- Nunca registar URLs, cabeçalhos, tokens, MACs; dados de teste sintéticos.
- Testes sem tempo de parede; `flutter analyze` e `flutter test` verdes; APK compila.

## Review Focus

1. Religação que repete 10–30 s com bytes idênticos: o gravado fica sem repetição e sem PCR a andar para trás. — Task 1.
2. Religação sem sobreposição (o servidor saltou à frente) ou com bytes diferentes: cose por PCR/PTS no início de uma imagem, sem perder a sincronização TS. — Task 1.
3. Canal Stalker com recuo «Desligado»: passa pelo gravador em memória, sem disco. — Task 2.

---

### Task 1: Costura no `GravadorDireto`

**Files:** Modify `lib/direto/gravador.dart` (e auxiliar `lib/direto/costura.dart`); Test `test/direto/costura_test.dart`, `test/direto/gravador_test.dart`.

**Interfaces:** Produces `int? pontoDeCostura(List<int> cauda, List<int> novo)` (posição em `novo` logo a seguir à cauda: procura os últimos 20 pacotes de 188 bytes — 3760 bytes — da ligação anterior dentro dos primeiros N MiB da nova); fallback por PCR: `int? costuraPorPcr(int ultimoPcr, List<int> novo)` (primeiro pacote com PCR > último PCR gravado, recuado ao início da imagem/PES mais próximo).

- [ ] Testes que falham: nova ligação que repete os últimos 25 s idênticos → o gravado continua exatamente no byte seguinte (sem duplicados); sem sobreposição em bytes mas PCR contínuo → cose por PCR; ligação que começa à frente (salto) → grava a partir do início da nova (aceita o salto); os primeiros MiB guardados para procurar a costura não contam para a reserva antes de se decidir (ou contam e o limite mantém-se — documentar); o índice de tempo continua monótono.
- [ ] FALHAM → implementar → PASSAM; suite + analyze.
- [ ] Commit `fix(direto): coser as religações (sem repetir o que o servidor reenvia)`

### Task 2: Stalker pelo gravador e reabertura mais rápida

**Files:** Modify `lib/ui/player/player_canais.dart`, `lib/direto/sessao_direto.dart`, `android/.../ReprodutorExo.kt` (LoadControl), `lib/ui/player/configuracao_mpv.dart`; Tests.

- [ ] Testes que falham: canal Stalker em direto com recuo «Desligado» → sessão em memória (sem pasta), recuar/pausa continuam desligados na interface; ExoPlayer: `DefaultLoadControl` com `maxBufferMs` 60 000 (mín. 30 000, início 1 500, retoma 2 500); sem gravador: quando o buffer desce abaixo de ~5 s num canal Stalker, o link seguinte é pedido antes (e usado na reabertura; se falhar, pede-se outro); mpv: `cache-pause-wait` 1 s na reabertura de um direto.
- [ ] FALHAM → implementar → PASSAM; suite + analyze; build apk.
- [ ] Commit `perf(direto): canais Stalker sempre pelo gravador e reabertura mais rápida`
