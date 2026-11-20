import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/rede/http.dart';

final _grande = ConteudoLista(['G'], [
  for (var i = 0; i < 100000; i++)
    Canal(id: '$i', nome: 'Canal número $i', grupo: 'G', url: 'http://servidor.exemplo:8080/live/u/p/$i.ts',
        logo: 'http://logos.exemplo/$i.png'),
]);

void main() {
  test('I5: a cache de 100 mil canais escreve-se e lê-se inteira', () async {
    final pasta = Directory.systemTemp.createTempSync('i5');
    addTearDown(() {
      try {
        pasta.deleteSync(recursive: true);
      } on FileSystemException {/* Windows */}
    });
    final bib = await Biblioteca.abrir(pasta);
    await bib.adicionar([Importada(contaDeLinha('http://x.com/l.m3u')!)]);
    final id = bib.listas.single.id;
    await bib.guardarCanais(id, _grande);
    final lido = await bib.canaisEmCache(id);
    expect(lido!.canais, hasLength(100000));
    expect(lido.canais.last.nome, 'Canal número 99999');
  });

  test('I5: um JSON grande (Stalker/Xtream) é descodificado inteiro', () async {
    final corpo = utf8.encode(jsonEncode([for (final c in _grande.canais) c.paraJson()]));
    final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    srv.listen((p) async {
      p.response.add(corpo);
      await p.response.close();
    });
    addTearDown(() => srv.close(force: true));
    final dados = await obterJson('http://127.0.0.1:${srv.port}/');
    expect(dados, hasLength(100000));
  });
}
