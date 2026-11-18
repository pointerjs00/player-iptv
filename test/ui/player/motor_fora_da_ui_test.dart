import 'dart:async';
import 'dart:io';
import 'dart:isolate';

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

  bool falha = false;

  @override
  Future<String> getProperty(int handle, String p) async {
    await _talvezPreso();
    if (falha) throw StateError('o isolate morreu');
    chamadas.add('$handle:get $p');
    return 'v-$p';
  }

  @override
  Future<void> command(int handle, List<String> c) async {
    await _talvezPreso();
    chamadas.add('$handle:${c.join(' ')}');
  }

  @override
  Future<List<String>> getProperties(int handle, List<String> ps) async {
    await _talvezPreso();
    if (falha) throw StateError('o isolate morreu');
    chamadas.add('$handle:get ${ps.join(',')}');
    return [for (final p in ps) p == 'nada' ? '' : 'v-$p'];
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

  test('várias propriedades de uma vez: um só pedido ao executor (um isolate)', () async {
    expect(await motor.getProperties(['time-pos', 'nada', 'duration']),
        {'time-pos': 'v-time-pos', 'nada': '', 'duration': 'v-duration'});
    expect(ex.chamadas, ['7:get time-pos,nada,duration']);
  });

  test('várias propriedades com o executor a falhar: tudo vazio, não lança', () async {
    ex.falha = true;
    expect(await motor.getProperties(['a', 'b']), {'a': '', 'b': ''});
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

  group('nunca fica preso', () {
    const limite = Duration(milliseconds: 200);

    MotorForaDaUi motorCom({Future<int?> Function()? handle}) => MotorForaDaUi(
          handle: handle ?? () async => 7,
          executor: ex,
          setRate: (_) async {},
          setVolume: (_) async {},
          limite: limite,
        );

    test('um controlador de vídeo que nunca fica pronto: os pedidos desistem e fechar não espera', () async {
      final m = motorCom(handle: () => Completer<int?>().future);
      expect(await m.getProperty('x'), '');
      await m.setProperty('mute', 'yes');
      await m.fechar().timeout(const Duration(seconds: 1));
      expect(ex.chamadas, isEmpty);
    });

    test('mpv preso: quem chama desiste no limite; o player só é destruído quando o pedido acabar', () async {
      final m = motorCom();
      ex.preso = true;
      expect(await m.getProperty('time-pos'), '');
      var destruido = 0;
      await m.fecharEDestruir(() async => destruido++).timeout(const Duration(seconds: 1));
      expect(destruido, 0, reason: 'destruir com um pedido dentro do mpv seria usar memória já libertada');
      ex.soltar();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(destruido, 1);
    });

    test('aposentar: pausa e tira o som pelo media_kit já, mesmo com o mpv preso; destrói depois', () async {
      final m = motorCom();
      ex.preso = true;
      unawaited(m.getProperty('time-pos'));
      await Future<void>.delayed(Duration.zero);
      final passos = <String>[];
      await m
          .aposentar(
            pausar: () async => passos.add('pausa'),
            silenciar: () async => passos.add('volume 0'),
            destruir: () async => passos.add('destruir'),
          )
          .timeout(const Duration(seconds: 1));
      expect(passos, ['pausa', 'volume 0'], reason: 'um player largado nunca continua a tocar');
      ex.soltar();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(passos.last, 'destruir');
    });

    test('sem pedidos no mpv: destrói logo', () async {
      final m = motorCom();
      var destruido = 0;
      await m.fecharEDestruir(() async => destruido++);
      expect(destruido, 1);
    });

    test('um mpv que deixou de responder fica marcado: os pedidos seguintes nem lhe chegam', () async {
      final m = motorCom();
      ex.preso = true;
      expect(await m.getProperty('time-pos'), '');
      expect(m.semResposta, isTrue);
      ex.preso = false;
      final antes = ex.chamadas.length;
      final t = DateTime.now();
      expect(await m.getProperty('width'), '');
      await m.setProperty('mute', 'yes');
      await m.command(['seek', '1']);
      expect(DateTime.now().difference(t), lessThan(const Duration(milliseconds: 100)));
      expect(ex.chamadas.length, antes, reason: 'nenhum pedido novo ao mpv preso');
    });

    test('um pedido que falha (o isolate morreu) dá o valor vazio, sem exceção', () async {
      ex.falha = true;
      expect(await motorCom().getProperty('x'), '');
    });
  });

  test('o isolate do mpv morre: os pedidos pendentes falham (não ficam pendurados) e o seguinte arranca outro', () async {
    final e = ExecutorIsolate.paraTestes(chamadaDeTeste);
    await expectLater(e.getProperty(1, 'morrer').timeout(const Duration(seconds: 5)), throwsA(isA<StateError>()));
    expect(await e.getProperty(1, 'x').timeout(const Duration(seconds: 5)), 'eco:x');
  });

  test('erro dentro do isolate (mensagem estragada) responde com erro', () async {
    final e = ExecutorIsolate.paraTestes(chamadaDeTeste);
    await expectLater(e.getProperty(1, 'lancar').timeout(const Duration(seconds: 5)), throwsA(isA<StateError>()));
    expect(await e.getProperty(1, 'y').timeout(const Duration(seconds: 5)), 'eco:y');
  });

  test('uma chamada pendurada (o mpv preso) não atrasa as dos outros mpv: cada chamada corre no seu isolate',
      () async {
    final e = ExecutorIsolate.paraTestes(chamadaDeTeste);
    unawaited(e.getProperty(1, 'pendurar').then((_) {}, onError: (_) {}));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    for (final p in ['a', 'b', 'c']) {
      expect(await e.getProperty(2, p).timeout(const Duration(seconds: 1)), 'eco:$p');
    }
  });

  test('as chamadas do mesmo mpv correm pela ordem em que chegam (ex.: mute ligado e desligado depressa)',
      () async {
    final e = ExecutorIsolate.paraTestes(chamadaDeTeste);
    final ordem = <String>[];
    await Future.wait([
      e.getProperty(1, 'lento').then((v) => ordem.add(v)),
      e.getProperty(1, 'rapido').then((v) => ordem.add(v)),
    ]);
    expect(ordem, ['eco:lento', 'eco:rapido']);
  });

  test('o mpv preso de um player não prende os pedidos de outro player saudável (nem o marca nem o perde)',
      () async {
    final e = ExecutorIsolate.paraTestes(chamadaDeTeste);
    MotorForaDaUi motor(int h) => MotorForaDaUi(
        handle: () async => h,
        executor: e,
        setRate: (_) async {},
        setVolume: (_) async {},
        limite: const Duration(milliseconds: 500));
    final preso = motor(1), saudavel = motor(2);
    expect(await preso.getProperty('pendurar'), '');
    expect(preso.semResposta, isTrue);
    // o player novo, depois do zap: as preferências, as estatísticas, a destruição
    expect(await saudavel.getProperty('width'), 'eco:width');
    await saudavel.setProperty('mute', 'no');
    expect(saudavel.semResposta, isFalse, reason: 'o player novo responde: não pode ser marcado');
    var destruido = false;
    await saudavel.fecharEDestruir(() async => destruido = true).timeout(const Duration(seconds: 2));
    expect(destruido, isTrue, reason: 'sem pedidos dele no mpv: destrói-se já (não fica perdido)');
  });
}

/// Uma chamada de mpv de mentira (corre no isolate): "morrer" sai sem responder; "lancar" lança;
/// "pendurar" fica presa (como uma chamada nativa que não volta); "lento" demora; o resto responde
/// "eco:...".
Object? chamadaDeTeste(String op, int handle, List<String> args) {
  switch (args.first) {
    case 'morrer':
      Isolate.exit();
    case 'lancar':
      throw StateError('estragado');
    case 'pendurar':
      sleep(const Duration(seconds: 4));
    case 'lento':
      sleep(const Duration(milliseconds: 300));
  }
  return 'eco:${args.first}';
}
