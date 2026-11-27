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

  test('lê a versão (sem o «v») e a página da release; rascunhos e pré-versões não contam', () {
    final r = lerUltimaRelease(release('v1.0.26'))!;
    expect(r.versao, '1.0.26');
    expect(r.pagina, 'https://github.com/pointerjs00/player-iptv/releases/tag/v1.0.26');
    expect(lerUltimaRelease(release('1.0.27'))?.versao, '1.0.27');
    expect(lerUltimaRelease(release('v1.0.26', rascunho: true)), isNull);
    expect(lerUltimaRelease(release('v1.0.26', previa: true)), isNull);
    expect(lerUltimaRelease('{"message":"Not Found"}'), isNull);
    expect(lerUltimaRelease('<html>'), isNull);
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
    var texto = release('v1.0.26');
    Future<String> obter(Uri u) async {
      pedidos++;
      expect(u.toString(), enderecoUltimaRelease);
      return texto;
    }

    final v = await novaVersaoPorAvisar(pasta, atual: '1.0.25', obter: obter);
    expect(v?.versao, '1.0.26');
    expect(await novaVersaoPorAvisar(pasta, atual: '1.0.25', obter: obter), isNull, reason: 'já avisada');
    texto = release('v1.0.27');
    expect((await novaVersaoPorAvisar(pasta, atual: '1.0.25', obter: obter))?.versao, '1.0.27');
    expect(await novaVersaoPorAvisar(pasta, atual: '1.0.27', obter: obter), isNull, reason: 'é a que já tem');
    expect(await novaVersaoPorAvisar(pasta, atual: '1.0.25', obter: (_) async => throw const SocketException('x')),
        isNull);
    final antes = pedidos;
    expect(await novaVersaoPorAvisar(pasta, atual: '1.0.20', obter: obter, emDadosMoveis: () async => true), isNull);
    expect(pedidos, antes, reason: 'em dados móveis nem pede');
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
