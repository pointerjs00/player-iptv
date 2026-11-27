import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/ui/design/escala_interface.dart';
import 'package:player_iptv/ui/jogos/folha_onde_ver.dart';
import 'package:player_iptv/ui/jogos/linha_jogo.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';

import 'ajuda_dpad.dart';
import 'jogos_apoio.dart';

/// O ecrã «Jogos» na Android TV (960×540, a interface a 80 %), só com o comando.
void main() {
  late Montagem m;
  tearDown(() => arrumarJogos(m));

  Future<void> montar(WidgetTester t) async {
    ecraTvTeste(t);
    m = (await t.runAsync(prepararJogos))!;
    await t.pumpWidget(MaterialApp(
      theme: temaApp(),
      builder: (_, c) => TemaConformeRealce(child: EscalaInterface(escala: escalaCompacto, child: c!)),
      home: Scaffold(body: m.tela()),
    ));
    await t.pump();
  }

  /// O foco no chip «Filtros» (a fila de cima), e BAIXO até à primeira linha.
  Future<void> irParaPrimeiro(WidgetTester t) async {
    Focus.of(t.element(find.text('Filtros'))).requestFocus();
    await t.pump();
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
  }

  LinhaJogoState linha(String casa) =>
      tFind<LinhaJogoState>(find.ancestor(of: find.text(casa).first, matching: find.byType(LinhaJogo)));

  testWidgets('a 960×540 a 80 % veem-se pelo menos 5 jogos inteiros', (t) async {
    await montar(t);
    final ecra = t.view.physicalSize;
    final inteiras = find.byType(LinhaJogo).evaluate().where((e) {
      final r = t.getRect(find.byWidget(e.widget));
      return r.top >= 0 && r.bottom <= ecra.height;
    });
    expect(inteiras.length, greaterThanOrEqualTo(5));
    expect(t.takeException(), isNull, reason: 'nada transborda');
  });

  testWidgets('BAIXO percorre os jogos, uma paragem por linha, e passa os títulos das competições', (t) async {
    await montar(t);
    await irParaPrimeiro(t);
    expect(textosFocados(), contains('Marítimo'));
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(textosFocados(), contains('Benfica'));
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(textosFocados(), contains('Moreirense'));
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(textosFocados(), contains('Benfica'));
    // até ao fim da Liga Portugal e para o bloco seguinte (o título não recebe o foco)
    for (var i = 0; i < 4; i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    }
    expect(textosFocados(), contains('Famalicão'));
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(textosFocados(), contains('Arsenal'));
  });

  testWidgets('←/→ escolhem a etiqueta; OK abre o «Onde ver» dela; BACK fecha e o foco volta à linha', (t) async {
    await montar(t);
    await irParaPrimeiro(t);
    expect(linha('Marítimo').etiqueta, 0);
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(linha('Marítimo').etiqueta, 1);
    expect(textosFocados(), contains('Marítimo'), reason: 'o foco fica na linha');
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(linha('Marítimo').etiqueta, 1, reason: 'não passa da última');
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(find.byType(FolhaOndeVer), findsOneWidget);
    expect(find.text('Onde ver: Sport TV 2'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(FolhaOndeVer), findsNothing);
    expect(textosFocados(), contains('Marítimo'));
    expect(linha('Marítimo').etiqueta, 1, reason: 'a etiqueta escolhida mantém-se');
    await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
    expect(linha('Marítimo').etiqueta, 0);
  });

  testWidgets('no «Onde ver», OK na primeira fonte abre-a no player', (t) async {
    await montar(t);
    await irParaPrimeiro(t);
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(textosFocados(), contains('Lista 1'), reason: 'o foco começa na primeira fonte');
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(find.byType(FolhaOndeVer), findsNothing);
    expect(m.abertas.single.map((f) => f.lista.id), ['1', '2']);
  });

  testWidgets('OK mantido faz «▶ Ver» (todas as fontes do jogo)', (t) async {
    await montar(t);
    await irParaPrimeiro(t);
    await t.sendKeyDownEvent(LogicalKeyboardKey.select);
    await t.pump(const Duration(milliseconds: 600));
    await t.sendKeyUpEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(find.byType(FolhaOndeVer), findsNothing, reason: 'o OK longo não abre o «Onde ver»');
    expect(m.abertas.single.map((f) => f.canalTv), ['sporttv1', 'sporttv1', 'sporttv2']);
  });
}

T tFind<T extends State>(Finder f) => (f.evaluate().single as StatefulElement).state as T;
