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
}
