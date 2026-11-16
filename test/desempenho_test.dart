import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/rede/http.dart';

/// Corre `f` e devolve a maior paragem (ms) da thread atual enquanto `f` corria.
Future<int> _maiorParagem(Future<void> Function() f) async {
  var ultimo = DateTime.now();
  var maior = 0;
  final t = Timer.periodic(const Duration(milliseconds: 5), (_) {
    final agora = DateTime.now();
    maior = max(maior, agora.difference(ultimo).inMilliseconds);
    ultimo = agora;
  });
  await Future<void>.delayed(const Duration(milliseconds: 20));
  ultimo = DateTime.now();
  await f();
  // o timer só mede a paragem no tique seguinte
  await Future<void>.delayed(const Duration(milliseconds: 20));
  t.cancel();
  return maior;
}

final _grande = ConteudoLista(['G'], [
  for (var i = 0; i < 100000; i++)
    Canal(id: '$i', nome: 'Canal número $i', grupo: 'G', url: 'http://servidor.exemplo:8080/live/u/p/$i.ts',
        logo: 'http://logos.exemplo/$i.png'),
]);

void main() {
  test('I5: a cache de 100 mil canais é lida e escrita fora da thread da interface', () async {
    final pasta = Directory.systemTemp.createTempSync('i5');
    addTearDown(() {
      try {
        pasta.deleteSync(recursive: true);
      } on FileSystemException {/* Windows */}
    });
    final bib = await Biblioteca.abrir(pasta);
    await bib.adicionar([Importada(contaDeLinha('http://x.com/l.m3u')!)]);
    final id = bib.listas.single.id;
    final escrita = await _maiorParagem(() => bib.guardarCanais(id, _grande));
    ConteudoLista? lido;
    final leitura = await _maiorParagem(() async => lido = await bib.canaisEmCache(id));
    expect(lido!.canais, hasLength(100000));
    // ignore: avoid_print
    print('I5 paragens: escrita $escrita ms, leitura $leitura ms');
    // mandar 100 mil canais para o isolate ainda custa uma cópia (antes: ~170 ms)
    expect(escrita, lessThan(100));
    expect(leitura, lessThan(60));
  });

  test('I5: um JSON grande (Stalker/Xtream) é descodificado fora da thread da interface', () async {
    final corpo = utf8.encode(jsonEncode([for (final c in _grande.canais) c.paraJson()]));
    final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    srv.listen((p) async {
      p.response.add(corpo);
      await p.response.close();
    });
    addTearDown(() => srv.close(force: true));
    Object? dados;
    final paragem = await _maiorParagem(() async => dados = await obterJson('http://127.0.0.1:${srv.port}/'));
    expect(dados, hasLength(100000));
    // ignore: avoid_print
    print('I5 paragem obterJson: $paragem ms');
    expect(paragem, lessThan(60));
  });
}
