import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/ui/player/mpv_fora_da_ui.dart';

void main() {
  test('o player novo só abre depois de o anterior largar o áudio (no máximo o limite)', () async {
    final vez = VezDoAudio(limite: const Duration(milliseconds: 300));
    final largado = Completer<void>();
    vez.largar(largado.future);
    var abriu = false;
    final f = vez.esperar().then((_) => abriu = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(abriu, isFalse, reason: 'o áudio do anterior ainda não foi fechado');
    largado.complete();
    await f;
    expect(abriu, isTrue);
  });

  test('um anterior preso não impede o novo de abrir para sempre', () async {
    final vez = VezDoAudio(limite: const Duration(milliseconds: 100));
    vez.largar(Completer<void>().future);
    await vez.esperar().timeout(const Duration(seconds: 1));
  });

  test('espera por todos os players largados, mesmo os que falham', () async {
    final vez = VezDoAudio(limite: const Duration(seconds: 1));
    final a = Completer<void>(), b = Completer<void>();
    vez
      ..largar(a.future)
      ..largar(b.future);
    var abriu = false;
    final f = vez.esperar().then((_) => abriu = true);
    a.completeError(StateError('x'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(abriu, isFalse);
    b.complete();
    await f;
  });
}
