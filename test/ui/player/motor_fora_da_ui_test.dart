import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/ui/player/mpv_fora_da_ui.dart';

/// Um executor que só responde quando o teste deixa (como o mpv ocupado a abrir um canal).
class _ExecutorPreso implements ExecutorMpv {
  final chamadas = <String>[];
  final _travoes = <Completer<void>>[];
  bool preso = false;

  Future<void> _talvezPreso() async {
    if (!preso) return;
    final c = Completer<void>();
    _travoes.add(c);
    await c.future;
  }

  void soltar() {
    for (final c in _travoes) {
      c.complete();
    }
    _travoes.clear();
  }

  @override
  Future<void> setProperty(int handle, String p, String v) async {
    await _talvezPreso();
    chamadas.add('$handle:$p=$v');
  }

  @override
  Future<String> getProperty(int handle, String p) async {
    await _talvezPreso();
    chamadas.add('$handle:get $p');
    return 'v-$p';
  }

  @override
  Future<void> command(int handle, List<String> c) async {
    await _talvezPreso();
    chamadas.add('$handle:${c.join(' ')}');
  }
}

void main() {
  late _ExecutorPreso ex;
  late MotorForaDaUi motor;
  final velocidades = <double>[];
  setUp(() {
    ex = _ExecutorPreso();
    velocidades.clear();
    motor = MotorForaDaUi(
      handle: () async => 7,
      executor: ex,
      setRate: (v) async => velocidades.add(v),
      setVolume: (_) async {},
    );
  });

  test('as chamadas vão para o executor com o handle do mpv', () async {
    await motor.setProperty('mute', 'yes');
    expect(await motor.getProperty('time-pos'), 'v-time-pos');
    await motor.command(['seek', '-10', 'relative']);
    await motor.setRate(1.5);
    expect(ex.chamadas, ['7:mute=yes', '7:get time-pos', '7:seek -10 relative']);
    expect(velocidades, [1.5]);
  });

  test('um mpv ocupado não prende quem chama (a UI segue; o pedido acaba depois)', () async {
    ex.preso = true;
    var acabou = false;
    final f = motor.setProperty('audio-delay', '0.100').then((_) => acabou = true);
    await Future<void>.delayed(Duration.zero);
    expect(acabou, isFalse);
    ex.soltar();
    await f;
    expect(acabou, isTrue);
  });

  test('fechar espera pelos pedidos em curso (o mpv só é destruído depois) e ignora os seguintes', () async {
    ex.preso = true;
    final pedido = motor.setProperty('mute', 'no');
    await Future<void>.delayed(Duration.zero);
    var fechado = false;
    final fecho = motor.fechar().then((_) => fechado = true);
    await Future<void>.delayed(Duration.zero);
    expect(fechado, isFalse, reason: 'ainda há um pedido no mpv');
    ex.soltar();
    await pedido;
    await fecho;
    expect(fechado, isTrue);
    ex.preso = false;
    await motor.setProperty('mute', 'yes');
    expect(await motor.getProperty('time-pos'), '');
    await motor.command(['seek', '1']);
    expect(ex.chamadas, ['7:mute=no']);
  });

  test('sem mpv nativo (handle nulo): nada acontece', () async {
    final m = MotorForaDaUi(handle: () async => null, executor: ex, setRate: (_) async {}, setVolume: (_) async {});
    await m.setProperty('mute', 'yes');
    expect(await m.getProperty('x'), '');
    expect(ex.chamadas, isEmpty);
  });
}
