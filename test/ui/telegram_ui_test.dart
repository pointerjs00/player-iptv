import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/dados/preferencias.dart';
import 'package:player_iptv/tarefas/servico_tarefas.dart';
import 'package:player_iptv/ui/design/componentes.dart';
import 'package:player_iptv/ui/gestor/tela_gestor.dart';
import 'package:player_iptv/ui/tema.dart';
import 'package:player_iptv/verificar/servico.dart';

import '../apoio/servidor_falso.dart';

Future<void> abrirImportar(WidgetTester t) async {
  await t.tap(find.descendant(of: find.byType(CartaoModerno), matching: find.text('Importar')));
  await t.pumpAndSettle();
}

/// Uma página do canal com uma mensagem publicada hoje (ao meio-dia UTC).
String _paginaHoje(String lista) {
  final h = DateTime.now().toUtc();
  final dia = '${h.year.toString().padLeft(4, '0')}-${h.month.toString().padLeft(2, '0')}-${h.day.toString().padLeft(2, '0')}';
  return '<div class="tgme_widget_message_wrap"><div class="tgme_widget_message" data-post="michelstv4/100">'
      '<div class="tgme_widget_message_text js-message_text" dir="auto">'
      '<a href="${lista.replaceAll('&', '&amp;')}">$lista</a></div>'
      '<div class="tgme_widget_message_footer"><time datetime="${dia}T12:00:00+00:00"></time></div></div></div>';
}

void main() {
  testWidgets('Gestor: a pesquisa do Telegram junta as listas ao Gestor (não ao Player)', (t) async {
    HttpOverrides.global = null; // o binding de testes bloqueia a rede
    t.view.physicalSize = const Size(1200, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final srv = ServidorFalso((p) => p.uri.path == '/s/michelstv4'
        ? (200, _paginaHoje('http://a.tv/get.php?username=u&password=p&type=m3u'))
        : (404, 'nada'));
    final pasta = Directory.systemTemp.createTempSync('tg');
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
                biblioteca: bib,
                area: area,
                servico: ServicoVerificacao(bib, colecao: area),
                tarefas: ServicoTarefas(),
                baseTelegram: '${srv.url}/s/'))));
    await abrirImportar(t);
    expect(find.text('Listas do Telegram'), findsOneWidget);
    await t.tap(find.text('Listas do Telegram'));
    await t.pump();
    expect(find.text('@michelstv4'), findsOneWidget, reason: 'o canal de omissão já vem guardado');
    await t.runAsync(() async {
      await t.tap(find.text('Procurar e juntar'));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await t.pump();
    await t.pump();
    expect(find.text('Novas no Gestor'), findsOneWidget);
    expect(find.text('Verificar a 1 nova'), findsOneWidget);
    expect(area.listas.length, 1);
    expect(bib.listas, isEmpty);
  });

  group('gestão dos canais do Telegram', () {
    late Directory pasta;
    late Biblioteca bib;
    late AreaGestor area;
    late ServidorFalso srv;
    setUp(() => Preferencias.atual = Preferencias.omissao());
    tearDown(() => Preferencias.atual = Preferencias.omissao());

    Future<void> montar(WidgetTester t) async {
      HttpOverrides.global = null;
      t.view.physicalSize = const Size(1200, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      srv = ServidorFalso((p) => switch (p.uri.path) {
            '/s/michelstv4' => (200, _paginaHoje('http://a.tv/get.php?username=u&password=p&type=m3u')),
            '/s/outro_canal' => (200, _paginaHoje('http://b.tv/get.php?username=x&password=y&type=m3u')),
            _ => (404, 'nada'),
          });
      pasta = Directory.systemTemp.createTempSync('tg_gestao');
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
                  biblioteca: bib,
                  area: area,
                  servico: ServicoVerificacao(bib, colecao: area),
                  tarefas: ServicoTarefas(),
                  baseTelegram: '${srv.url}/s/'))));
      await abrirImportar(t);
      await t.tap(find.text('Listas do Telegram'));
      await t.pump();
    }

    Future<void> juntar(WidgetTester t, String canal) async {
      final campo = find.widgetWithText(TextField, 'Juntar um canal');
      await t.tap(campo);
      await t.pump();
      await t.enterText(campo, canal);
      await t.tap(find.byKey(const Key('juntar-canal-tg')));
      await t.pump();
    }

    testWidgets('juntar um canal (também com o link), favoritos primeiro e «Todos os favoritos»', (t) async {
      await montar(t);
      await juntar(t, 'https://t.me/outro_canal');
      expect(Preferencias.atual.canaisTelegram, ['michelstv4', 'outro_canal']);
      expect(find.text('@outro_canal'), findsOneWidget);
      expect(t.widget<ListTile>(find.byKey(const Key('canal-tg-outro_canal'))).selected, isTrue,
          reason: 'o canal junto fica escolhido');
      // repetido (com outras maiúsculas): não duplica
      await juntar(t, '@Outro_Canal');
      expect(Preferencias.atual.canaisTelegram, hasLength(2));
      // favoritos: o outro passa para cima
      await t.tap(find.byKey(const Key('favorito-tg-outro_canal')));
      await t.pump();
      expect(Preferencias.atual.favoritosTelegram, {'outro_canal'});
      expect(t.getTopLeft(find.text('@outro_canal')).dy, lessThan(t.getTopLeft(find.text('@michelstv4')).dy));
      expect(find.textContaining('Todos os favoritos'), findsNothing, reason: 'só com dois ou mais favoritos');
      await t.tap(find.byKey(const Key('favorito-tg-michelstv4')));
      await t.pump();
      expect(find.text('Todos os favoritos (2)'), findsOneWidget);
    });

    testWidgets('«Todos os favoritos» procura em cada um e junta tudo, sem duplicar', (t) async {
      await montar(t);
      await juntar(t, 'outro_canal');
      await t.tap(find.byKey(const Key('favorito-tg-outro_canal')));
      await t.tap(find.byKey(const Key('favorito-tg-michelstv4')));
      await t.pump();
      await t.tap(find.text('Todos os favoritos (2)'));
      await t.pump();
      await t.runAsync(() async {
        await t.tap(find.text('Procurar e juntar'));
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      });
      await t.pump();
      await t.pump();
      expect(area.listas.length, 2);
      expect(srv.pedidos.map((p) => p.uri.path).toSet(), {'/s/michelstv4', '/s/outro_canal'});
    });

    testWidgets('remover um canal, com «Desfazer»', (t) async {
      await montar(t);
      await juntar(t, 'outro_canal');
      await t.tap(find.byKey(const Key('favorito-tg-outro_canal')));
      await t.tap(find.byKey(const Key('remover-tg-outro_canal')));
      await t.pump();
      expect(find.text('@outro_canal'), findsNothing);
      expect(Preferencias.atual.canaisTelegram, ['michelstv4']);
      expect(Preferencias.atual.favoritosTelegram, isEmpty);
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('@outro_canal saiu dos canais'), findsOneWidget);
      await t.tap(find.text('Desfazer'));
      await t.pump(const Duration(milliseconds: 600));
      expect(Preferencias.atual.canaisTelegram, ['michelstv4', 'outro_canal']);
      expect(Preferencias.atual.favoritosTelegram, {'outro_canal'}, reason: 'volta como estava, favorito incluído');
    });
  });
}
