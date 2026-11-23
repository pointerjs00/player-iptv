import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
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
    expect(find.text('Canal do Telegram'), findsOneWidget);
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
}
