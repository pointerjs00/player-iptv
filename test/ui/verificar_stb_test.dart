import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/ui/tema.dart';
import 'package:player_iptv/ui/verificar/tela_verificar.dart';
import 'package:player_iptv/verificar/servico.dart';

import '../apoio/servidor_falso.dart';

String _dd(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

void main() {
  testWidgets('Gestor: pesquisa do stbstalker junta as listas ao Gestor (não ao Player) e mostra o aviso', (t) async {
    HttpOverrides.global = null; // o binding de testes bloqueia a rede
    t.view.physicalSize = const Size(1200, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final hoje = DateTime.now();
    final slug = '${hoje.day}-${hoje.month}-${hoje.year}';
    final srv = ServidorFalso((p) => switch (p.uri.path) {
          '/' => (200, '<a href="/${hoje.year}/01/stb-$slug.html">a</a>'),
          _ => (200, '<p>http://portal.exemplo/c/</p><p>00:1A:79:00:00:01<br/>00:1A:79:00:00:02</p>'),
        });
    final pasta = Directory.systemTemp.createTempSync('stb');
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
            body: TelaVerificar(
                biblioteca: bib, area: area, servico: ServicoVerificacao(bib, colecao: area), baseStb: '${srv.url}/'))));
    expect(find.text('Listas do stbstalker'), findsOneWidget);
    expect(find.text(_dd(hoje)), findsNWidgets(2));
    await t.runAsync(() async {
      await t.tap(find.text('Iniciar pesquisa'));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await t.pump();
    await t.pump();
    expect(find.text('Em ${_dd(hoje)}: 2 linhas em 1 post, 2 listas novas.'), findsOneWidget);
    expect(area.listas.length, 2);
    expect(bib.listas, isEmpty);
  });

  testWidgets('I1: blog que corta a ligação mostra o erro em português e sem o link', (t) async {
    HttpOverrides.global = null;
    t.view.physicalSize = const Size(1200, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final pasta = Directory.systemTemp.createTempSync('stb');
    late Biblioteca bib;
    late AreaGestor area;
    late ServerSocket corta;
    await t.runAsync(() async {
      bib = await Biblioteca.abrir(pasta);
      area = await AreaGestor.abrir(pasta);
      corta = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      corta.listen((s) => s.destroy());
    });
    addTearDown(() async {
      await t.runAsync(corta.close);
      try {
        pasta.deleteSync(recursive: true);
      } on FileSystemException {/* Windows */}
    });
    await t.pumpWidget(MaterialApp(
        theme: temaApp(),
        home: Scaffold(
            body: TelaVerificar(
                biblioteca: bib, area: area, servico: ServicoVerificacao(bib, colecao: area), baseStb: 'http://127.0.0.1:${corta.port}/'))));
    await t.runAsync(() async {
      await t.tap(find.text('Iniciar pesquisa'));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await t.pump();
    await t.pump();
    expect(find.text('Não foi possível pesquisar: a ligação foi cortada pelo servidor'), findsOneWidget);
    expect(find.textContaining('http'), findsNothing);
  });

  testWidgets('o seletor de datas aparece em português', (t) async {
    t.view.physicalSize = const Size(1200, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final pasta = Directory.systemTemp.createTempSync('stb');
    late Biblioteca bib;
    late AreaGestor area;
    await t.runAsync(() async {
      bib = await Biblioteca.abrir(pasta);
      area = await AreaGestor.abrir(pasta);
    });
    addTearDown(() {
      try {
        pasta.deleteSync(recursive: true);
      } on FileSystemException {/* Windows */}
    });
    await t.pumpWidget(MaterialApp(
        theme: temaApp(),
        locale: const Locale('pt', 'PT'),
        supportedLocales: const [Locale('pt', 'PT')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: TelaVerificar(biblioteca: bib, area: area, servico: ServicoVerificacao(bib, colecao: area)))));
    await t.tap(find.byType(OutlinedButton).first);
    await t.pumpAndSettle();
    expect(find.text('Cancelar'), findsOneWidget);
  });
}
