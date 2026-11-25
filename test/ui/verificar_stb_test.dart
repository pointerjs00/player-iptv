import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/ui/tema.dart';
import 'package:player_iptv/tarefas/servico_tarefas.dart';
import 'package:player_iptv/ui/design/componentes.dart';
import 'package:player_iptv/ui/gestor/tela_gestor.dart';
import 'package:player_iptv/verificar/servico.dart';

import '../apoio/servidor_falso.dart';

/// O stbstalker está no sub-ecrã de importar (passo 1).
Future<void> abrirImportar(WidgetTester t) async {
  await t.tap(find.descendant(of: find.byType(CartaoModerno), matching: find.text('Importar')));
  await t.pumpAndSettle();
}

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
            body: TelaGestor(
                biblioteca: bib,
                area: area,
                servico: ServicoVerificacao(bib, colecao: area),
                tarefas: ServicoTarefas(),
                baseStb: '${srv.url}/'))));
    await abrirImportar(t);
    expect(find.text('Listas de um site'), findsOneWidget);
    await t.tap(find.text('Listas de um site'));
    await t.pump();
    expect(find.textContaining('Escolher datas · '), findsOneWidget);
    await t.runAsync(() async {
      await t.tap(find.text('Procurar e juntar'));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await t.pump();
    await t.pump();
    expect(find.text('Novas no Gestor'), findsOneWidget);
    expect(find.text('Verificar as 2 novas'), findsOneWidget);
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
            body: TelaGestor(
                biblioteca: bib,
                area: area,
                servico: ServicoVerificacao(bib, colecao: area),
                tarefas: ServicoTarefas(),
                baseStb: 'http://127.0.0.1:${corta.port}/'))));
    await abrirImportar(t);
    await t.tap(find.text('Listas de um site'));
    await t.pump();
    await t.runAsync(() async {
      await t.tap(find.text('Procurar e juntar'));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await t.pump();
    await t.pump();
    expect(find.text('Com erro (Não foi possível pesquisar: a ligação foi cortada pelo servidor)'), findsOneWidget);
    // o link não aparece na mensagem (o campo do site mostra o endereço, como deve)
    expect(find.textContaining(RegExp(r'(erro|pesquisar).*http')), findsNothing);
  });

  testWidgets('o calendário do stbstalker abre no ecrã, em português', (t) async {
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
        home: Scaffold(
            body: TelaGestor(
                biblioteca: bib, area: area, servico: ServicoVerificacao(bib, colecao: area), tarefas: ServicoTarefas()))));
    await abrirImportar(t);
    await t.tap(find.text('Listas de um site'));
    await t.pump();
    await t.tap(find.widgetWithIcon(OutlinedButton, Icons.calendar_today));
    await t.pumpAndSettle();
    expect(find.text('Escolhe o início e o fim'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^(janeiro|fevereiro|março|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro) \d{4}$')), findsOneWidget);
  });
}
