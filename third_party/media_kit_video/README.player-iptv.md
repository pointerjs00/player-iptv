# media_kit_video 2.0.1 — cópia local do Player IPTV

Cópia do pacote [media_kit_video](https://pub.dev/packages/media_kit_video) **2.0.1** (pub.dev,
licença MIT em `LICENSE`), usada pela app com `dependency_overrides` (`path: third_party/media_kit_video`),
junto com a cópia local do media_kit (`third_party/media_kit`).

## O que mudou

- `lib/src/utils/query_decoders.dart`: a leitura do `decoder-list` (chamada síncrona ao libmpv)
  corre num isolate (`foraDaUi`, do media_kit local), nunca na thread da UI.
- `lib/src/video_controller/android_video_controller/real.dart`:
  - as propriedades do mpv (`vo`, `wid`, `android-surface-size`, `vid`…) já passam pelo
    `NativePlayer.setProperty` do media_kit local, que as corre fora da thread da UI pela mesma
    ordem (quem chama espera por cada uma);
  - antes de a superfície mudar de tamanho (`VideoOutputManager.SetSurfaceSize`) e antes de ser
    libertada (`VideoOutputManager.Dispose`), o mpv larga-a (`vo=null`): o descodificador deixava
    de poder desenhar numa superfície já libertada.

## Porquê

No Android a UI do Flutter corre na thread principal. Estas chamadas esperam pelo núcleo do mpv;
quando um mpv deixa de responder (visto no emulador ao fazer zapping e ao sair/entrar no player a
meio da abertura de um canal), a app era morta por ANR. Reprodução, taxas antes/depois e análise:
`.superpowers/sdd/2026-11-17-v2-plano/task-5-report.md` (relatório da tarefa 5, "Fix round 5").

## Ao atualizar o media_kit_video

Estas alterações **têm de ser reaplicadas** a cada versão nova (procurar "player-iptv" no código).
O teste `test/third_party/fora_da_ui_test.dart` falha se voltar a haver chamadas síncronas ao libmpv
fora dos isolates.
