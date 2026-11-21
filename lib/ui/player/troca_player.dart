import 'dart:async';

import 'package:flutter/foundation.dart';

import 'mpv_fora_da_ui.dart' show VezDoAudio;

/// Antes de abrir um canal: ou se troca de player (`novo`: o modo de descodificação mudou ou o
/// mpv deixou de responder), ou, num zap, pára-se o canal anterior no mesmo player; um `stop`
/// que não acaba em [limiteStop] é de um mpv que deixou de responder e troca-se de player.
///
/// `trocar` cria o player novo e devolve a aposentação do antigo (pausa, fecha, destrói). Não se
/// espera por ela: o `dispose` de um player preso precisa do lock dele no media_kit, que um
/// `seek`/`stop` preso nunca larga (nunca acaba), e o fecho espera até 10 s pelos pedidos que lá
/// estão. A ordem do áudio entre o antigo e o novo fica com a [VezDoAudio] (no máximo uns
/// segundos por player largado), logo antes do `open`.
Future<void> prepararPlayer({
  required bool novo,
  required bool zap,
  required Future<void> Function() parar,
  required Future<void> Function() trocar,
  Duration limiteStop = const Duration(seconds: 5),
}) async {
  void largarAntigo() => unawaited(trocar().then((_) {}, onError: (Object e) {
        debugPrint('mpv: o player antigo não foi destruído ($e)');
      }));
  if (novo) {
    largarAntigo();
  } else if (zap) {
    try {
      await parar().timeout(limiteStop);
    } on TimeoutException {
      debugPrint('mpv: stop sem resposta; player novo');
      largarAntigo();
    }
  }
}
