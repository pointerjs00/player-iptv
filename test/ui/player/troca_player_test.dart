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

  testWidgets('um zap depois de um bloqueio chega ao open a tempo (stop preso, dispose do antigo preso)', (t) async {
    // o stop fica preso (segura o lock do media_kit do player), o dispose desse player nunca
    // acaba: o player novo abre no máximo o limite do stop + o limite da vez do áudio depois
    // com o relógio de mentira: nada espera tempo real, e vê-se quando o open pode avançar
    final vez = VezDoAudio(limite: limiteVez);
    var aberto = false;
    prepararPlayer(
      novo: false,
      zap: true,
      limiteStop: limiteStop,
      parar: () => Completer<void>().future,
      trocar: () {
        final destruido = Completer<void>();
        vez.largar(destruido.future); // como o _aposentar do PlayerCanais
        return destruido.future;
      },
    ).then((_) => vez.esperar()).then((_) => aberto = true); // logo antes do open
    await t.pump();
    await t.pump(limiteStop - const Duration(milliseconds: 1));
    expect(aberto, isFalse, reason: 'o stop preso espera pelo seu limite');
    await t.pump(limiteStop + limiteVez);
    expect(aberto, isTrue, reason: 'passados os dois limites o open avança, com tudo preso');
  });

  test('a aposentação do antigo a falhar não chega a quem abre o canal', () async {
    await prepararPlayer(novo: true, zap: false, parar: () async {}, trocar: () async => throw StateError('x'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });
}
