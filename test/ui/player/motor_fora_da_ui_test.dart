import 'dart:async';
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

    test('sem pedidos no mpv: destrói logo', () async {
      final m = motorCom();
      var destruido = 0;
      await m.fecharEDestruir(() async => destruido++);
      expect(destruido, 1);
    });

    test('um pedido que falha (o isolate morreu) dá o valor vazio, sem exceção', () async {
      ex.falha = true;
      expect(await motorCom().getProperty('x'), '');
    });
  });

  test('o isolate do mpv morre: os pedidos pendentes falham (não ficam pendurados) e o seguinte arranca outro', () async {
    final e = ExecutorIsolate.paraTestes(isolateDeTeste);
    await expectLater(e.getProperty(1, 'morrer').timeout(const Duration(seconds: 5)), throwsA(isA<StateError>()));
    expect(await e.getProperty(1, 'x').timeout(const Duration(seconds: 5)), 'eco:x');
  });

  test('erro dentro do isolate (mensagem estragada) responde com erro', () async {
    final e = ExecutorIsolate.paraTestes(isolateDeTeste);
    await expectLater(e.getProperty(1, 'lancar').timeout(const Duration(seconds: 5)), throwsA(isA<StateError>()));
    expect(await e.getProperty(1, 'y').timeout(const Duration(seconds: 5)), 'eco:y');
  });
}

/// Um isolate de mpv de mentira: "morrer" sai sem responder; "lancar" lança fora de qualquer
/// try (morre com erro); o resto responde "eco:...".
void isolateDeTeste(SendPort respostas) {
  final pedidos = ReceivePort();
  respostas.send(pedidos.sendPort);
  pedidos.listen((m) {
    final (int id, String _, int _, List<String> args) = m as (int, String, int, List<String>);
    if (args.first == 'morrer') Isolate.exit();
    if (args.first == 'lancar') throw StateError('estragado');
    respostas.send((id, 'eco:${args.first}', null));
  });
}
