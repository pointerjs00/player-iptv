import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/dados/preferencias_player.dart';
import 'package:player_iptv/ui/player/configuracao_mpv.dart';

void main() {
  late Directory pasta;
  setUp(() => pasta = Directory.systemTemp.createTempSync('prefs_player'));
  tearDown(() => pasta.deleteSync(recursive: true));

  test('sem ficheiro: direto; ajustar a taxa ligado só na TV', () async {
    final tv = await PreferenciasPlayer.carregar(pasta, tv: true);
    expect(tv.modoAndroid, ModoDescodificacao.direto);
    expect(tv.ajustarTaxaEcra, isTrue);
    final tele = await PreferenciasPlayer.carregar(pasta, tv: false);
    expect(tele.ajustarTaxaEcra, isFalse);
  });

  test('guarda e volta a ler', () async {
    final p = await PreferenciasPlayer.carregar(pasta, tv: true);
    p.modoAndroid = ModoDescodificacao.compativel;
    p.ajustarTaxaEcra = false;
    await p.guardar();
    final q = await PreferenciasPlayer.carregar(pasta, tv: true);
    expect(q.modoAndroid, ModoDescodificacao.compativel);
    expect(q.ajustarTaxaEcra, isFalse);
  });

  test('ficheiro estragado: valores por omissão', () async {
    File('${pasta.path}${Platform.pathSeparator}preferencias_player.json').writeAsStringSync('{nao json');
    final p = await PreferenciasPlayer.carregar(pasta, tv: false);
    expect(p.modoAndroid, ModoDescodificacao.direto);
  });

  test('valores com o tipo errado: valores por omissão, sem exceção, e guarda uma cópia .bak', () async {
    final f = File('${pasta.path}${Platform.pathSeparator}preferencias_player.json')
      ..writeAsStringSync('{"modoAndroid": 1, "ajustarTaxaEcra": "sim"}');
    final p = await PreferenciasPlayer.carregar(pasta, tv: true);
    expect(p.modoAndroid, ModoDescodificacao.direto);
    expect(p.ajustarTaxaEcra, isTrue);
    expect(File('${f.path}.bak').readAsStringSync(), contains('"modoAndroid": 1'));
  });

  test('JSON inválido ou outra forma (lista): .bak e valores por omissão', () async {
    final f = File('${pasta.path}${Platform.pathSeparator}preferencias_player.json')..writeAsStringSync('[1, 2]');
    final p = await PreferenciasPlayer.carregar(pasta, tv: false);
    expect(p.ajustarTaxaEcra, isFalse);
    expect(File('${f.path}.bak').existsSync(), isTrue);
    f.writeAsStringSync('{nao json');
    await PreferenciasPlayer.carregar(pasta, tv: false);
    expect(File('${f.path}.bak').readAsStringSync(), '{nao json');
  });

  test('a pasta nem existe / não se lê: valores por omissão, nunca exceção', () async {
    final p = await PreferenciasPlayer.carregar(Directory('${pasta.path}${Platform.pathSeparator}nao_existe'), tv: true);
    expect(p.modoAndroid, ModoDescodificacao.direto);
  });
}
