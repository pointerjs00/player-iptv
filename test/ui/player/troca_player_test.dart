import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/ui/player/mpv_fora_da_ui.dart';
import 'package:player_iptv/ui/player/troca_player.dart';

void main() {
  const limiteStop = Duration(milliseconds: 200);
  const limiteVez = Duration(milliseconds: 300);

  test('primeiro canal: nem pára nem troca', () async {
    final passos = <String>[];
    await prepararPlayer(
        novo: false, zap: false, parar: () async => passos.add('parar'), trocar: () async => passos.add('trocar'));
    expect(passos, isEmpty);
  });

  test('zap num player saudável: pára o canal anterior no mesmo player', () async {
    final passos = <String>[];
    await prepararPlayer(
        novo: false, zap: true, parar: () async => passos.add('parar'), trocar: () async => passos.add('trocar'));
    expect(passos, ['parar']);
  });

  test('player novo: não espera que o antigo (preso) acabe de ser destruído', () async {
    // o dispose do antigo precisa do lock dele, que um seek/stop preso nunca larga
    var trocou = false;
    await prepararPlayer(
      novo: true,
      zap: true,
      parar: () async => fail('não se pára um player que se vai trocar'),
      trocar: () {
        trocou = true;
        return Completer<void>().future;
      },
    ).timeout(const Duration(seconds: 1));
    expect(trocou, isTrue);
  });

  test('um zap depois de um bloqueio chega ao open a tempo (stop preso, dispose do antigo preso)', () async {
    // o stop fica preso (segura o lock do media_kit do player), o dispose desse player nunca
    // acaba: o player novo abre no máximo o limite do stop + o limite da vez do áudio depois
    final vez = VezDoAudio(limite: limiteVez);
    final relogio = Stopwatch()..start();
    await prepararPlayer(
      novo: false,
      zap: true,
      limiteStop: limiteStop,
      parar: () => Completer<void>().future,
      trocar: () {
        final destruido = Completer<void>();
        vez.largar(destruido.future); // como o _aposentar do PlayerCanais
        return destruido.future;
      },
    ).timeout(const Duration(seconds: 2));
    await vez.esperar(); // logo antes do open
    expect(relogio.elapsed, lessThan(limiteStop + limiteVez + const Duration(milliseconds: 250)));
  });

  test('a aposentação do antigo a falhar não chega a quem abre o canal', () async {
    await prepararPlayer(novo: true, zap: false, parar: () async {}, trocar: () async => throw StateError('x'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });
}
