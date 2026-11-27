import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/ui/design/design.dart';
import 'package:player_iptv/ui/jogos/fila_hoje.dart';

import 'ajuda_dpad.dart';
import 'apoio_telemovel.dart';
import 'jogos_apoio.dart';

/// A fila «Hoje há jogo» do Início (plano dos Jogos, Task 14): os jogos de hoje das equipas
/// favoritas, com «▶ Ver».
void main() {
  late Montagem m;
  tearDown(() => arrumarJogos(m));

  Widget fila() => FilaHojeHaJogo(
        servico: m.servico,
        fontes: m.fontes,
        preferencias: m.prefs,
        agora: agoraJogos,
        abrir: (context, f, {aoFuncionar}) async => m.abertas.add(f),
      );

  Future<void> montar(WidgetTester t, {List<String> favoritas = const ['Benfica']}) async {
    m = (await t.runAsync(prepararJogos))!;
    m.prefs.equipasFavoritas = favoritas;
    await t.pumpWidget(appTeste(Scaffold(body: ListView(children: [fila()]))));
    await t.pump();
  }

  testWidgets('só os jogos de hoje das favoritas, e OK faz «▶ Ver»', (t) async {
    ecraTvTeste(t);
    await montar(t);
    expect(find.text('Hoje há jogo · 1'), findsOneWidget);
    expect(find.text('Benfica'), findsOneWidget);
    expect(find.text('Marítimo'), findsNothing, reason: 'não é favorita');
    // o foco do cartão (não o de dentro, que não o recebe)
    final focos = find.ancestor(of: find.text('Benfica'), matching: find.byType(Focus)).evaluate();
    focos.map((e) => (e.widget as Focus).focusNode).firstWhere((n) => n != null && n.canRequestFocus)!.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pump();
    expect(m.abertas.single.map((f) => f.canalTv), ['btv']);
  });

  testWidgets('sem jogos das favoritas hoje, a fila não aparece', (t) async {
    await montar(t, favoritas: const ['Sporting']);
    expect(find.textContaining('Hoje há jogo'), findsNothing);
    expect(find.byType(CartaoModerno), findsNothing);
  });

  testWidgets('a fila acompanha as favoritas', (t) async {
    await montar(t, favoritas: const []);
    expect(find.textContaining('Hoje há jogo'), findsNothing);
    m.prefs.equipasFavoritas = ['Porto', 'Arsenal'];
    await t.pump();
    expect(find.text('Hoje há jogo · 2'), findsOneWidget);
  });

  group('telemóvel', () {
    setUpAll(carregarRoboto);
    noTelemovel('nada transborda', (t, ecra) async {
      m = (await t.runAsync(prepararJogos))!;
      m.prefs.equipasFavoritas = ['Benfica', 'Marítimo', 'Arsenal'];
      await t.pumpWidget(appTelemovel(Scaffold(body: ListView(children: [fila()]))));
      await t.pump();
      expect(find.text('Hoje há jogo · 3'), findsOneWidget);
    });
  });
}
