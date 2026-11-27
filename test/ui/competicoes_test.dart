import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/desporto/preferencias_jogos.dart';
import 'package:player_iptv/ui/design/design.dart';
import 'package:player_iptv/ui/design/escala_interface.dart';
import 'package:player_iptv/ui/jogos/tela_competicoes.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';

import 'ajuda_dpad.dart';
import 'apoio_telemovel.dart';

/// O ecrã «Competições»: as seguidas, pela ordem dos Jogos, e o modo «Reordenar».
void main() {
  late Directory pasta;
  late PreferenciasJogos prefs;

  Future<void> preparar(WidgetTester t) async {
    pasta = Directory.systemTemp.createTempSync('competicoes_ui');
    addTearDown(() {
      try {
        pasta.deleteSync(recursive: true);
      } on FileSystemException {/* Windows */}
    });
    prefs = (await t.runAsync(() => PreferenciasJogos.abrir(pasta)))!;
    prefs.competicoes = {'liga-portugal', 'champions', 'premier-league'};
    prefs.ordemCompeticoes = ['liga-portugal', 'champions', 'premier-league'];
  }

  /// Na TV, por cima de uma página (para o Voltar ter para onde voltar).
  Future<void> montarTv(WidgetTester t) async {
    ecraTvTeste(t);
    await preparar(t);
    await t.pumpWidget(MaterialApp(
      theme: temaApp(),
      builder: (_, c) => TemaConformeRealce(child: EscalaInterface(escala: escalaCompacto, child: c!)),
      home: Builder(
        builder: (c) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(
                  builder: (_) => Scaffold(body: TelaCompeticoes(preferencias: prefs)))),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
  }

  Future<void> focar(WidgetTester t, String nome) async {
    t.widget<CartaoModerno>(find.ancestor(of: find.text(nome), matching: find.byType(CartaoModerno))).focusNode!.requestFocus();
    await t.pump();
  }

  testWidgets('mostra as seguidas pela ordem; sem «Reordenar», OK não muda nada', (t) async {
    await montarTv(t);
    final ys = [for (final n in ['Liga Portugal Betclic', 'Liga dos Campeões', 'Premier League']) t.getRect(find.text(n)).top];
    expect(ys, [...ys]..sort());
    await focar(t, 'Liga dos Campeões');
    await teclaDpad(t, LogicalKeyboardKey.select);
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(prefs.ordemCompeticoes, ['liga-portugal', 'champions', 'premier-league']);
  });

  testWidgets('a reordenar: OK pega, CIMA move (o foco vai com ela), OK larga', (t) async {
    await montarTv(t);
    await t.tap(find.text('Reordenar'));
    await t.pump();
    expect(find.text('Concluído'), findsOneWidget);
    await focar(t, 'Liga dos Campeões');
    await teclaDpad(t, LogicalKeyboardKey.select);
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(prefs.ordemCompeticoes, ['champions', 'liga-portugal', 'premier-league']);
    expect(textosFocados(), contains('Liga dos Campeões'));
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(prefs.ordemCompeticoes, ['champions', 'liga-portugal', 'premier-league'], reason: 'já é a primeira');
    expect(textosFocados(), contains('Liga dos Campeões'));
    await teclaDpad(t, LogicalKeyboardKey.select); // larga
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(prefs.ordemCompeticoes, ['champions', 'liga-portugal', 'premier-league'], reason: 'largada, BAIXO só anda');
    expect(textosFocados(), contains('Liga Portugal Betclic'));
  });

  testWidgets('Voltar com uma pegada larga-a; sem nenhuma sai do modo; depois fecha o ecrã', (t) async {
    await montarTv(t);
    await t.tap(find.text('Reordenar'));
    await t.pump();
    await focar(t, 'Premier League');
    await teclaDpad(t, LogicalKeyboardKey.select);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byType(TelaCompeticoes), findsOneWidget, reason: 'só largou');
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(prefs.ordemCompeticoes.last, 'premier-league', reason: 'largada, CIMA só anda');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Reordenar'), findsOneWidget, reason: 'saiu do modo');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byType(TelaCompeticoes), findsNothing);
  });

  testWidgets('ao abrir, o foco já está na primeira competição', (t) async {
    await montarTv(t);
    expect(textosFocados(), contains('Liga Portugal Betclic'));
  });

  testWidgets('o botão «Voltar» fecha o ecrã; a reordenar, primeiro sai do modo', (t) async {
    await montarTv(t);
    await t.tap(find.text('Reordenar'));
    await t.pump();
    await t.tap(find.byTooltip('Voltar'));
    await t.pumpAndSettle();
    expect(find.byType(TelaCompeticoes), findsOneWidget, reason: 'só saiu do modo');
    expect(find.text('Reordenar'), findsOneWidget);
    await t.tap(find.byTooltip('Voltar'));
    await t.pumpAndSettle();
    expect(find.byType(TelaCompeticoes), findsNothing);
  });

  testWidgets('na TV, CIMA na primeira competição chega ao «Voltar»', (t) async {
    await montarTv(t);
    expect(textosFocados(), contains('Liga Portugal Betclic'));
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
    expect(textosFocados(), 'Voltar');
  });

  testWidgets('sem competições seguidas, diz onde as escolher', (t) async {
    await montarTv(t);
    prefs.competicoes = {};
    await t.pump();
    expect(find.textContaining('Definições › Jogos'), findsOneWidget);
  });

  group('telemóvel', () {
    setUpAll(carregarRoboto);
    noTelemovel('nada transborda; a reordenar veem-se as pegas e arrastar muda a ordem', (t, ecra) async {
      await preparar(t);
      await t.pumpWidget(appTelemovel(Scaffold(body: SafeArea(child: TelaCompeticoes(preferencias: prefs)))));
      await t.pump();
      expect(find.byIcon(Icons.drag_handle_rounded), findsNothing);
      await t.tap(find.text('Reordenar'));
      await t.pump();
      expect(find.byIcon(Icons.drag_handle_rounded), findsNWidgets(3));
      final pega = find.byIcon(Icons.drag_handle_rounded).last;
      final g = await t.startGesture(t.getCenter(pega));
      await t.pump(const Duration(milliseconds: 600));
      for (var i = 0; i < 20; i++) {
        await g.moveBy(const Offset(0, -12));
        await t.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await t.pumpAndSettle();
      expect(prefs.ordemCompeticoes.first, 'premier-league');
    });
  });
}
