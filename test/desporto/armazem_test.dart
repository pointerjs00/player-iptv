import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/desporto/armazem_desporto.dart';
import 'package:player_iptv/desporto/cliente_desporto.dart';

/// A cache em disco das fontes dos «Jogos» e o cliente que a usa (sem rede: um `obter` falso e
/// um relógio falso).
void main() {
  late Directory pasta;
  late ArmazemDesporto armazem;
  var agora = DateTime.utc(2026, 11, 27, 12);
  final pedidos = <Uri>[];
  var falhar = false;
  var corpo = 'v1';

  Future<String> obter(Uri u, Map<String, String> cabecalhos) async {
    pedidos.add(u);
    if (falhar) throw const SocketException('sem rede');
    return corpo;
  }

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('desporto');
    armazem = await ArmazemDesporto.abrir(pasta);
    pedidos.clear();
    falhar = false;
    corpo = 'v1';
    agora = DateTime.utc(2026, 11, 27, 12);
  });
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  ClienteDesporto cliente() => ClienteDesporto(armazem, obter: obter, agora: () => agora);
  final uri = Uri.parse('https://exemplo.invalid/a?b=1');

  test('dentro da validade não pede à rede', () async {
    final c = cliente();
    expect((await c.texto('a', uri, const Duration(hours: 1)))!.valor, 'v1');
    corpo = 'v2';
    agora = agora.add(const Duration(minutes: 30));
    final r = (await c.texto('a', uri, const Duration(hours: 1)))!;
    expect(r.valor, 'v1');
    expect(r.velho, isFalse);
    expect(pedidos, hasLength(1));
  });

  test('fora da validade pede e regrava (também noutra sessão da app)', () async {
    await cliente().texto('a', uri, const Duration(hours: 1));
    corpo = 'v2';
    agora = agora.add(const Duration(hours: 2));
    final outra = ClienteDesporto(await ArmazemDesporto.abrir(pasta), obter: obter, agora: () => agora);
    expect((await outra.texto('a', uri, const Duration(hours: 1)))!.valor, 'v2');
    expect(pedidos, hasLength(2));
  });

  test('sem rede, a cache antiga vem marcada como velha (com a data)', () async {
    await cliente().texto('a', uri, const Duration(hours: 1));
    falhar = true;
    agora = agora.add(const Duration(hours: 2));
    final r = (await cliente().texto('a', uri, const Duration(hours: 1)))!;
    expect(r.valor, 'v1');
    expect(r.velho, isTrue);
    expect(r.data, DateTime.utc(2026, 11, 27, 12));
  });

  test('sem rede e sem cache: o erro passa', () async {
    falhar = true;
    expect(cliente().texto('a', uri, const Duration(hours: 1)), throwsA(isA<SocketException>()));
  });

  test('só cache (dados móveis): não pede; sem cache, null', () async {
    final c = cliente();
    expect(await c.texto('a', uri, const Duration(hours: 1), soCache: true), isNull);
    expect(pedidos, isEmpty);
    await c.texto('a', uri, const Duration(hours: 1));
    agora = agora.add(const Duration(hours: 3));
    final r = (await c.texto('a', uri, const Duration(hours: 1), soCache: true))!;
    expect(r.velho, isTrue);
    expect(pedidos, hasLength(1));
  });

  test('arrumar apaga o que tem mais de 8 dias', () async {
    final c = cliente();
    await c.texto('velho', uri, const Duration(hours: 1));
    agora = agora.add(const Duration(days: 9));
    await c.texto('novo', uri, const Duration(hours: 1));
    await armazem.arrumar(agora: agora);
    expect(await armazem.ler('velho'), isNull);
    expect(await armazem.ler('novo'), isNotNull);
  });
}
