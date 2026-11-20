import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/rede/http.dart';
import 'package:player_iptv/verificar/estado.dart';

void main() {
  late HttpServer srv;
  final portas = <int>{};
  final pingos = <Timer>[];
  setUp(() async {
    portas.clear();
    srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    srv.listen((p) async {
      portas.add(p.connectionInfo!.remotePort);
      switch (p.uri.path) {
        case '/grande':
          p.response.add(Uint8List(5000));
          await p.response.close();
        case '/pinga':
          // um byte de 100 em 100 ms, para sempre: nunca fica parado tempo bastante para o
          // tempo limite entre blocos
          p.response.bufferOutput = false;
          p.response.write('a');
          await p.response.flush();
          pingos.add(Timer.periodic(const Duration(milliseconds: 100), (t) async {
            try {
              p.response.write('a');
              await p.response.flush();
            } catch (_) {
              t.cancel();
            }
          }));
        default:
          p.response.write('ok');
          await p.response.close();
      }
    });
  });
  tearDown(() async {
    for (final t in pingos) {
      t.cancel();
    }
    pingos.clear();
    await srv.close(force: true);
  });

  String url(String c) => 'http://127.0.0.1:${srv.port}$c';

  test('I4: corpo acima de maxBytes lança ErroTamanho em vez de devolver um corpo cortado', () async {
    await expectLater(obterBytes(url('/grande'), maxBytes: 1000), throwsA(isA<ErroTamanho>()));
    expect(await obterBytes(url('/grande'), maxBytes: 6000), hasLength(5000));
  });

  test('I4: ErroTamanho é INC na verificação e tem texto legível', () {
    expect(classificarFalha(ErroTamanho(1000)).estado, EstadoV.inconclusivo);
    expect(descreverErro(ErroTamanho(1000)), contains('grande demais'));
  });

  test('I4: o corpo vem num Uint8List (1 byte por byte, não 8)', () async {
    expect(await obterBytes(url('/grande')), isA<Uint8List>());
  });

  test('I4: pedidos seguidos ao mesmo servidor reutilizam a ligação (keep-alive)', () async {
    for (var i = 0; i < 3; i++) {
      expect(await obterTexto(url('/x')), 'ok');
    }
    expect(portas, hasLength(1));
  });

  test('I4: um servidor que pinga um byte de cada vez não passa do prazo total', () async {
    await expectLater(
        obterBytes(url('/pinga'), timeout: const Duration(milliseconds: 300)).timeout(const Duration(seconds: 8)),
        throwsA(isA<TimeoutException>().having((e) => e.message, 'mensagem', isNot(contains('Future not completed')))));
  });

  test('I4: cancelar a meio da leitura pára logo', () async {
    final can = Cancelamento();
    Timer(const Duration(milliseconds: 300), can.cancelar);
    // se não parasse, só acabava no prazo de 5 s com um TimeoutException, e não com Cancelado
    await expectLater(obterBytes(url('/pinga'), timeout: const Duration(seconds: 5), cancelamento: can),
        throwsA(isA<Cancelado>()));
  });
}
