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

  test('um anterior preso atrasa no máximo uma vez: as aberturas seguintes não esperam', () async {
    // o dispose de um player preso nunca acaba: a espera por ele conta desde que foi largado e
    // acaba no limite (antes, cada abertura e cada zap esperavam o limite até ao fim da sessão)
    const limite = Duration(milliseconds: 300);
    final vez = VezDoAudio(limite: limite);
    vez.largar(Completer<void>().future);
    final relogio = Stopwatch()..start();
    await vez.esperar();
    expect(relogio.elapsed, lessThan(limite * 2), reason: 'a primeira espera vai até ao limite');
    for (var i = 0; i < 4; i++) {
      relogio.reset();
      await vez.esperar();
      expect(relogio.elapsed, lessThan(limite ~/ 3), reason: 'abertura ${i + 2}: o preso já não conta');
    }
  });

  test('um dispose lento (acaba depois do limite contado desde largar) continua a ser esperado', () async {
    // a ordem do áudio: o limite conta desde a primeira espera; antes contava desde largar e um
    // dispose que acabasse depois dele deixava o player novo abrir com o áudio do antigo aberto
    // (o crash "mid == null" do audiotrack)
    const limite = Duration(milliseconds: 200);
    final vez = VezDoAudio(limite: limite, maximo: const Duration(seconds: 2));
    final lento = Completer<void>();
    vez.largar(lento.future);
    Timer(const Duration(milliseconds: 350), lento.complete);
    await Future<void>.delayed(const Duration(milliseconds: 250)); // já passou o limite desde largar
    var abriu = false;
    final f = vez.esperar().then((_) => abriu = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(abriu, isFalse, reason: 'o anterior ainda está a fechar o áudio');
    await f.timeout(const Duration(seconds: 1));
    expect(lento.isCompleted, isTrue);
  });

  test('um player largado há muito (para lá do máximo) já não atrasa ninguém', () async {
    const limite = Duration(milliseconds: 200);
    final vez = VezDoAudio(limite: limite, maximo: const Duration(milliseconds: 300));
    vez.largar(Completer<void>().future);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final relogio = Stopwatch()..start();
    await vez.esperar();
    expect(relogio.elapsed, lessThan(limite ~/ 2));
  });

  test('um preso antigo não encurta a espera por um player largado depois (a ordem do áudio fica)', () async {
    const limite = Duration(milliseconds: 300);
    final vez = VezDoAudio(limite: limite);
    vez.largar(Completer<void>().future);
    await Future<void>.delayed(limite * 1.5);
    final novo = Completer<void>();
    vez.largar(novo.future);
    var abriu = false;
    final f = vez.esperar().then((_) => abriu = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(abriu, isFalse, reason: 'o largado agora ainda não fechou o áudio');
    novo.complete();
    await f;
  });
}
