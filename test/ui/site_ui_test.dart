import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/dados/preferencias.dart';
import 'package:player_iptv/importar/stbstalker.dart' show stbBase;
import 'package:player_iptv/tarefas/servico_tarefas.dart';
import 'package:player_iptv/ui/design/componentes.dart';
import 'package:player_iptv/ui/gestor/tela_gestor.dart';
import 'package:player_iptv/ui/tema.dart';
import 'package:player_iptv/verificar/servico.dart';

import '../apoio/servidor_falso.dart';

void main() {
  setUp(() => Preferencias.atual = Preferencias.omissao());
  tearDown(() => Preferencias.atual = Preferencias.omissao());

  testWidgets('Listas de um site: um blog Blogger, entre as datas; o site fica nos recentes', (t) async {
    HttpOverrides.global = null; // o binding de testes bloqueia a rede
    t.view.physicalSize = const Size(1200, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final hoje = DateTime.now().toUtc().toIso8601String();
    final srv = ServidorFalso((p) => p.uri.path == '/feeds/posts/default'
        ? (200, {
            'feed': {
              'entry': [
                {
                  'published': {r'$t': hoje},
                  'content': {r'$t': '<p>http://xt.tv/get.php?username=u&amp;password=p&amp;type=m3u</p>'},
                },
              ],
            },
          })
        : (404, 'nada'));
    final pasta = Directory.systemTemp.createTempSync('site_ui');
    late Biblioteca bib;
    late AreaGestor area;
    await t.runAsync(() async {
      bib = await Biblioteca.abrir(pasta);
      area = await AreaGestor.abrir(pasta);
      await srv.iniciar();
    });
    addTearDown(() async {
      await t.runAsync(srv.parar);
      try {
        pasta.deleteSync(recursive: true);
      } on FileSystemException {/* Windows */}
    });
    await t.pumpWidget(MaterialApp(
        theme: temaApp(),
        home: Scaffold(
            body: TelaGestor(
                biblioteca: bib, area: area, servico: ServicoVerificacao(bib, colecao: area), tarefas: ServicoTarefas()))));
    await t.tap(find.descendant(of: find.byType(CartaoModerno), matching: find.text('Importar')));
    await t.pumpAndSettle();
    await t.tap(find.text('Listas de um site'));
    await t.pump();
    final campo = find.widgetWithText(TextField, 'Endereço do site');
    expect(t.widget<TextField>(campo).controller!.text, stbBase, reason: 'começa no stbstalker');
    await t.tap(campo);
    await t.pump();
    await t.enterText(campo, '${srv.url}/');
    await t.runAsync(() async {
      await t.tap(find.text('Procurar e juntar'));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await t.pump();
    await t.pump();
    expect(area.listas.length, 1);
    expect(area.listas.single.conta.endereco, 'http://xt.tv');
    expect(Preferencias.atual.sitesListas, ['${srv.url}/', stbBase]);
    expect(find.byKey(const Key('site-recente-$stbBase')), findsOneWidget, reason: 'o stbstalker fica à mão');
  });
}
