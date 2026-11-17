# media_kit 1.2.6 — cópia local do Player IPTV

Cópia do pacote [media_kit](https://pub.dev/packages/media_kit) **1.2.6** (pub.dev, licença MIT em
`LICENSE`), usada pelo `pubspec.yaml` da app através de:

```yaml
dependency_overrides:
  media_kit:
    path: third_party/media_kit
```

## O que mudou (uma linha)

`lib/src/player/native/player/real.dart`: o lock do `NativePlayer` passou de **estático** (um para
todos os players) a **um por player**:

```dart
static final Lock lock = Lock();   // original
final Lock lock = Lock();          // aqui
```

## Porquê

Todas as operações de todos os players (`_create`, `open`, `seek`, `stop`, `dispose`…) passavam
por esse lock único. Quando o mpv de um player deixa de responder a um `seek`/`stop` (visto no
emulador ao sair e entrar no player a meio da abertura de um canal; o `seek` é o que o
media_kit_video faz ao recriar a superfície), essa chamada nunca saía do lock e **todos os players
criados depois ficavam à espera para sempre** (spinner até reiniciar a app). Com o lock por player,
o player preso fica sozinho (pausado e sem som pela app) e os seguintes funcionam.

Reprodução, taxas antes/depois e a análise (relatório da tarefa 5): `.superpowers/sdd/2026-11-17-v2-plano/task-5-report.md`,
secções "Fix round 3" e "Fix round 4" (antes: 4 em 11 execuções presas; com o lock por player: 0 em
8).

## Ao atualizar o media_kit

Esta alteração **tem de ser reaplicada** a cada nova versão (copiar a versão nova para aqui e
voltar a tornar o lock por player), a não ser que o media_kit a corrija na origem. O teste
`test/third_party/media_kit_vendorizado_test.dart` falha se a alteração se perder.
