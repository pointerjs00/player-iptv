import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/nova_versao.dart';
import 'package:player_iptv/ui/principal/tela_principal.dart';
import 'package:player_iptv/ui/tema.dart';

/// O aviso de nova versão: a última release do GitHub, uma vez por versão.
void main() {
  late Directory pasta;
  setUp(() => pasta = Directory.systemTemp.createTempSync('nova_versao'));
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  String release(String tag, {bool rascunho = false, bool previa = false}) =>
      '{"tag_name":"$tag","html_url":"https://github.com/pointerjs00/player-iptv/releases/tag/$tag",'
      '"draft":$rascunho,"prerelease":$previa}';

  String lista(List<String> rs) => '[${rs.join(',')}]';

  test('cada edição lê só as suas releases (completa: «v…», partilha: «partilha-v…») e fica com a mais recente', () {
    final todas = lista([
      release('partilha-v1.0.27'),
      release('v1.0.26'),
      release('v1.0.28', previa: true),
      release('v1.0.27', rascunho: true),
      release('partilha-v1.0.26'),
      release('v1.0.25'),
    ]);
    final c = lerUltimaRelease(todas, prefixo: prefixoCompleta)!;
    expect(c.versao, '1.0.26', reason: 'rascunhos, pré-versões e as da partilha não contam');
    expect(c.pagina, 'https://github.com/pointerjs00/player-iptv/releases/tag/v1.0.26');
    final p = lerUltimaRelease(todas, prefixo: prefixoPartilha)!;
    expect(p.versao, '1.0.27');
    expect(p.pagina, endsWith('/tag/partilha-v1.0.27'));
    expect(lerUltimaRelease(lista([release('partilha-v1.0.30')]), prefixo: prefixoCompleta), isNull);
    expect(lerUltimaRelease('{"message":"Not Found"}', prefixo: prefixoCompleta), isNull);
    expect(lerUltimaRelease('<html>', prefixo: prefixoCompleta), isNull);
  });

  test('compara as versões pelos números (1.0.10 é mais recente do que 1.0.9)', () {
    expect(maisRecente('1.0.26', '1.0.25'), isTrue);
    expect(maisRecente('1.0.10', '1.0.9'), isTrue);
    expect(maisRecente('1.0.9', '1.0.10'), isFalse);
    expect(maisRecente('1.0.25', '1.0.25'), isFalse);
    expect(maisRecente('1.1', '1.0.25'), isTrue);
    expect(maisRecente('x', '1.0.25'), isFalse);
  });

  test('avisa uma vez por versão nova; a mesma, sem rede, ou em dados móveis não avisa', () async {
    var pedidos = 0;
    var texto = lista([release('v1.0.26')]);
    Future<String> obter(Uri u) async {
      pedidos++;
      expect(u.toString(), enderecoReleases);
      return texto;
    }

    final v = await novaVersaoPorAvisar(pasta, atual: '1.0.25', obter: obter);
    expect(await novaVersaoPorAvisar(pasta, atual: '1.0.25', obter: obter, prefixo: prefixoPartilha), isNull,
        reason: 'a partilha não é avisada de uma versão completa');
    expect(v?.versao, '1.0.26');
    expect(await novaVersaoPorAvisar(pasta, atual: '1.0.25', obter: obter), isNull, reason: 'já avisada');
    texto = lista([release('v1.0.27')]);
    expect((await novaVersaoPorAvisar(pasta, atual: '1.0.25', obter: obter))?.versao, '1.0.27');
    expect(await novaVersaoPorAvisar(pasta, atual: '1.0.27', obter: obter), isNull, reason: 'é a que já tem');
    expect(await novaVersaoPorAvisar(pasta, atual: '1.0.25', obter: (_) async => throw const SocketException('x')),
        isNull);
    final antes = pedidos;
    expect(await novaVersaoPorAvisar(pasta, atual: '1.0.20', obter: obter, emDadosMoveis: () async => true), isNull);
    expect(pedidos, antes, reason: 'em dados móveis nem pede');
  });

  test('a release traz os pacotes: nome, endereço, tamanho e SHA-256 (quando o GitHub o dá)', () {
    const texto = '[{"tag_name":"v1.0.28","html_url":"https://github.com/x/y/releases/tag/v1.0.28",'
        '"draft":false,"prerelease":false,"assets":['
        '{"name":"TVIntel-1.0.28-android-arm64.apk","size":58215542,'
        '"browser_download_url":"https://github.com/x/y/releases/download/v1.0.28/TVIntel-1.0.28-android-arm64.apk",'
        '"digest":"sha256:ab12cd"},'
        '{"name":"TVIntel-1.0.28-windows.zip","size":72191988,'
        '"browser_download_url":"https://github.com/x/y/releases/download/v1.0.28/TVIntel-1.0.28-windows.zip"},'
        '{"name":"sem-endereco.apk","size":1}'
        ']}]';
    final v = lerUltimaRelease(texto, prefixo: prefixoCompleta)!;
    expect(v.pacotes.map((p) => p.nome), ['TVIntel-1.0.28-android-arm64.apk', 'TVIntel-1.0.28-windows.zip'],
        reason: 'um asset sem endereço não conta');
    final apk = v.pacotes.first;
    expect(apk.url, 'https://github.com/x/y/releases/download/v1.0.28/TVIntel-1.0.28-android-arm64.apk');
    expect(apk.tamanho, 58215542);
    expect(apk.sha256, 'ab12cd');
    expect(v.pacotes.last.sha256, isNull);
    expect(lerUltimaRelease(lista([release('v1.0.26')]), prefixo: prefixoCompleta)!.pacotes, isEmpty);
  });

  test('a procura manual: há nova, em dia, ou sem resposta (sem olhar para a versão já avisada)', () async {
    Future<String> obter(Uri _) async => lista([release('v1.0.29'), release('partilha-v1.0.28')]);
    final nova = await procurarVersao(atual: '1.0.28', obter: obter);
    expect(nova, isA<HaNova>());
    expect((nova as HaNova).v.versao, '1.0.29');
    expect(await novaVersaoPorAvisar(pasta, atual: '1.0.28', obter: obter), isNotNull);
    expect(await procurarVersao(atual: '1.0.28', obter: obter), isA<HaNova>(), reason: 'mesmo já avisada');
    final emDia = await procurarVersao(atual: '1.0.28', obter: obter, prefixo: prefixoPartilha);
    expect((emDia as EmDia).versao, '1.0.28');
    expect(await procurarVersao(atual: '1.0.29', obter: obter), isA<EmDia>());
    expect(await procurarVersao(atual: '1.0.28', obter: (_) async => throw const SocketException('x')),
        isA<SemResposta>());
    expect(await procurarVersao(atual: '1.0.28', obter: (_) async => '[]'), isA<SemResposta>(),
        reason: 'sem nenhuma release desta edição não se sabe');
  });

  testWidgets('a casca mostra o aviso quando há versão nova', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: temaApp(),
      home: TelaPrincipal(
        verTv: const SizedBox(),
        gestor: const SizedBox(),
        definicoes: const SizedBox(),
        novaVersao: () async => const NovaVersao('1.0.26', 'https://github.com/pointerjs00/player-iptv/releases/tag/v1.0.26'),
      ),
    ));
    await t.pump();
    await t.pump();
    expect(find.textContaining('1.0.26'), findsOneWidget);
    expect(find.textContaining('github.com/pointerjs00/player-iptv/releases'), findsOneWidget);
    await t.pump(const Duration(seconds: 30));
  });
}
