import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/verificar/estado.dart';
import 'package:player_iptv/verificar/verificador.dart';

/// I-2: "o host não existe" só é prova com o aparelho em linha. Sem rede, o Android responde
/// EAI_NODATA (7) a tudo e o Windows 11001: isso não pode marcar listas como mortas.

SocketException _falha(int codigo) => SocketException('Failed host lookup', osError: OSError('x', codigo));

void main() {
  late List<String> pedidos;

  /// Um resolvedor falso: `respostas[host]` = null (resolve) ou o código do erro.
  Future<List<InternetAddress>> Function(String) procurar(Map<String, Object?> respostas) => (h) async {
        pedidos.add(h);
        final r = respostas.containsKey(h) ? respostas[h] : 7;
        if (r == null) return [InternetAddress('1.2.3.4')];
        if (r is List<int?>) {
          // respostas diferentes a cada pedido do mesmo host
          final c = r.removeAt(0);
          if (c == null) return [InternetAddress('1.2.3.4')];
          throw _falha(c);
        }
        throw _falha(r as int);
      };

  setUp(() => pedidos = []);

  Future<ResultadoVerificacao?> dns(String host, Map<String, Object?> respostas, {bool rede = true}) =>
      resolverDns(host,
          procurar: procurar(respostas), temInterface: () async => rede, nomesControlo: const ['controlo.test']);

  test('o host resolve: existe (null)', () async {
    expect(await dns('h.com', {'h.com': null}), isNull);
  });

  test('IP ou vazio: nem se pergunta', () async {
    expect(await dns('1.2.3.4', {}), isNull);
    expect(await dns('', {}), isNull);
    expect(pedidos, isEmpty);
  });

  for (final codigo in [7, 8, -2, 11001]) {
    test('não existe ($codigo) com rede (o nome de controlo resolve e a 2.ª tentativa falha igual): prova',
        () async {
      final r = await dns('h.com', {'h.com': codigo, 'controlo.test': null});
      expect((r!.estado, r.motivo), (EstadoV.naoFunciona, 'DNS: h.com não existe'));
      expect(pedidos, ['h.com', 'controlo.test', 'h.com']);
    });

    test('não existe ($codigo) mas o nome de controlo também falha (sem rede/DNS em baixo): inconclusivo',
        () async {
      final r = await dns('h.com', {'h.com': codigo, 'controlo.test': codigo});
      expect(r!.estado, EstadoV.inconclusivo);
      expect(r.motivo, contains('sem rede'));
    });
  }

  test('sem nenhuma interface de rede: inconclusivo, sem perguntar o controlo', () async {
    final r = await dns('h.com', {'h.com': 7}, rede: false);
    expect(r!.estado, EstadoV.inconclusivo);
    expect(r.motivo, contains('sem rede'));
    expect(pedidos, ['h.com']);
  });

  test('a rede voltou a meio (a 2.ª tentativa resolve): existe', () async {
    expect(await dns('h.com', {'h.com': <int?>[7, null], 'controlo.test': null}), isNull);
  });

  test('outro erro de DNS (não "não existe"): inconclusivo, como antes', () async {
    final r = await dns('h.com', {'h.com': 110});
    expect((r!.estado, r.motivo), (EstadoV.inconclusivo, 'DNS sem resposta'));
  });
}
